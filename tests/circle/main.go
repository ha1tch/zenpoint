// SPDX-License-Identifier: Apache-2.0 OR GPL-2.0-only OR GPL-3.0-only OR MPL-2.0
// Differential test for the swap-ROM CIRCLE (T-18): runs src/circle.asm
// under zen80 against the real 48K ROM's PLOT-SUB, recording every
// PLOT-SUB entry (C = x, B = y), and compares the point multiset with
// the reference from tools/gencircle.py. Any duplicate plot, missing
// point, extra point, or error-restart hit is a failure.
package main

import (
	"bufio"
	"fmt"
	"os"

	zio "github.com/ha1tch/zen80/io"
	"github.com/ha1tch/zen80/memory"
	"github.com/ha1tch/zen80/z80"
)

const (
	plotSub = 0x22E5
	entry   = 0x8000
	driver  = 0x7000
	maxStep = 2_000_000
)

func runCase(rom, bin []uint8, cx, cy, r uint8) (map[[2]uint8]int, int, bool) {
	mem := memory.NewRAM()
	cpu := z80.New(mem, zio.NewNullIO())
	mem.Load(0x0000, rom)
	mem.Load(entry, bin)

	// minimal sysvars for PLOT-SUB / PO-ATTR
	mem.Write(0x5C8F, 0x38) // ATTR-T
	mem.Write(0x5C90, 0x00) // MASK-T
	mem.Write(0x5C91, 0x00) // P-FLAG: OVER 0, INVERSE 0

	// driver: CALL entry / HALT
	mem.Write(driver, 0xCD)
	mem.Write(driver+1, uint8(entry&0xFF))
	mem.Write(driver+2, uint8(entry>>8))
	mem.Write(driver+3, 0x76)

	cpu.Reset()
	cpu.SP = 0xFF00
	cpu.IYH, cpu.IYL = 0x5C, 0x3A
	cpu.PC = driver
	cpu.A = r
	cpu.B = cy
	cpu.C = cx

	got := map[[2]uint8]int{}
	total := 0
	steps := 0
	for !cpu.Halted && steps < maxStep {
		if cpu.PC == 0x0008 {
			return nil, 0, false // error restart: clipping failed
		}
		if cpu.PC == plotSub {
			got[[2]uint8{cpu.C, cpu.B}]++
			total++
		}
		cpu.Step()
		steps++
	}
	if !cpu.Halted {
		return nil, 0, false
	}
	return got, total, true
}

func main() {
	vec := "../../tests/vectors/circle.txt"
	if len(os.Args) > 1 {
		vec = os.Args[1]
	}
	romPath := os.Getenv("VICKERS_ROM")
	if romPath == "" {
		romPath = "../../rom/base/48.rom"
		if _, err := os.Stat(romPath); err != nil {
			romPath = "/usr/share/spectrum-roms/48.rom"
		}
	}
	rom, err := os.ReadFile(romPath)
	if err != nil {
		fmt.Println("cannot read ROM:", err)
		os.Exit(1)
	}
	bin, err := os.ReadFile("../../build/circle.bin")
	if err != nil {
		fmt.Println("cannot read build/circle.bin:", err)
		os.Exit(1)
	}
	f, err := os.Open(vec)
	if err != nil {
		fmt.Println("cannot read vectors:", err)
		os.Exit(1)
	}
	defer f.Close()
	rd := bufio.NewReader(f)

	var ncases int
	fmt.Fscan(rd, &ncases)
	pass, fail := 0, 0
	for i := 0; i < ncases; i++ {
		var cx, cy, r, n int
		fmt.Fscan(rd, &cx, &cy, &r, &n)
		want := map[[2]uint8]int{}
		for j := 0; j < n; j++ {
			var px, py int
			fmt.Fscan(rd, &px, &py)
			want[[2]uint8{uint8(px), uint8(py)}]++
		}
		got, total, ok := runCase(rom, bin, uint8(cx), uint8(cy), uint8(r))
		bad := !ok || total != n || len(got) != len(want)
		if !bad {
			for k, v := range want {
				if got[k] != v {
					bad = true
					break
				}
			}
		}
		if bad {
			fail++
			if fail <= 10 {
				fmt.Printf("FAIL cx=%d cy=%d r=%d want=%d pts got=%d calls %d uniq ok=%v\n",
					cx, cy, r, n, total, len(got), ok)
			}
		} else {
			pass++
		}
	}
	fmt.Printf("%d/%d circle cases passed\n", pass, pass+fail)
	if fail > 0 {
		os.Exit(1)
	}
}
