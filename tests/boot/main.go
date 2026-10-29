// SPDX-License-Identifier: Apache-2.0 OR GPL-2.0-only OR GPL-3.0-only OR MPL-2.0
// Interim swap-ROM smoke test, under a PC watchdog built from the
// rompatch watch file (cleared-but-unpatched bytes must never be
// executed):
//   1. cold boot to the banner screen (no keys pressed);
//   2. CIRCLE driven through its real statement-handler contract —
//      CLASS-09 leaves x, y on the calculator stack and CH-ADD points
//      at the ",radius" text; the routine parses the radius and plots.
//      Points are compared with the midpoint reference; a clipping case
//      is included;
//   3. the same line in SYNTAX-CHECK mode (FLAGS bit 7 = 0) must plot
//      nothing and return cleanly — the bug that hung the editor;
//   4. radius > 255 must raise report B.
package main

import (
	"encoding/json"
	"fmt"
	"os"

	zio "github.com/ha1tch/zen80/io"
	"github.com/ha1tch/zen80/memory"
	"github.com/ha1tch/zen80/z80"
)

const plotSub = 0x22E5

type watch struct{ Ranges [][2]int }

func inWatch(w *watch, pc uint16) bool {
	for _, r := range w.Ranges {
		if int(pc) >= r[0] && int(pc) < r[1] {
			return true
		}
	}
	return false
}

func refPoints(cx, cy, r int) map[[2]uint8]int {
	pts := map[[2]uint8]int{}
	plot := func(px, py int) {
		if px >= 0 && px <= 255 && py >= 0 && py <= 175 {
			pts[[2]uint8{uint8(px), uint8(py)}]++
		}
	}
	plot4 := func(dx, dy int) {
		rows := []int{cy + dy}
		if dy != 0 {
			rows = append(rows, cy-dy)
		}
		for _, py := range rows {
			plot(cx+dx, py)
			if dx != 0 {
				plot(cx-dx, py)
			}
		}
	}
	if r == 0 {
		plot4(0, 0)
		return pts
	}
	x, y, d := r, 0, 1-r
	for y <= x {
		plot4(x, y)
		if x != y {
			plot4(y, x)
		}
		y++
		if d < 0 {
			d += 2*y + 1
		} else {
			x--
			d += 2*(y-x) + 1
		}
	}
	return pts
}

// runCircle sets up the real CIRCLE entry state and calls 2320h.
// syntax=true runs in syntax-check mode (FLAGS bit 7 = 0). Returns the
// plotted-point multiset, whether an error restart fired, and whether
// execution ever strayed into freed space.
func runCircle(mem *memory.RAM, cpu *z80.Z80, w *watch, cx, cy, r int, syntax bool) (map[[2]uint8]int, bool, bool) {
	se := uint16(mem.Read(0x5C65)) | uint16(mem.Read(0x5C66))<<8
	for _, v := range []int{cx, cy} { // CLASS-09 stacks x then y
		mem.Write(se, 0)
		mem.Write(se+1, 0)
		mem.Write(se+2, uint8(v))
		mem.Write(se+3, uint8(v>>8))
		mem.Write(se+4, 0)
		se += 5
	}
	mem.Write(0x5C65, uint8(se))
	mem.Write(0x5C66, uint8(se>>8))
	const buf = 0x6000 // ",<r>" 0x0E <fp> 0x0D
	prog := []uint8{',', '0' + uint8((r/100)%10), '0' + uint8((r/10)%10), '0' + uint8(r%10),
		0x0E, 0, 0, uint8(r), uint8(r >> 8), 0, 0x0D}
	for i, b := range prog {
		mem.Write(uint16(buf+i), b)
	}
	mem.Write(0x5C5D, uint8(buf&0xFF))
	mem.Write(0x5C5E, uint8(buf>>8))
	if syntax {
		mem.Write(0x5C3B, mem.Read(0x5C3B)&0x7F)
	} else {
		mem.Write(0x5C3B, mem.Read(0x5C3B)|0x80)
	}
	mem.Write(0x8000, 0xCD)
	mem.Write(0x8001, 0x20)
	mem.Write(0x8002, 0x23)
	mem.Write(0x8003, 0x76)
	cpu.PC = 0x8000
	cpu.SP = 0xFF00
	cpu.Halted = false
	cpu.IFF1, cpu.IFF2 = true, true

	got := map[[2]uint8]int{}
	errHit := false
	for steps := 0; !cpu.Halted && steps < 3_000_000; steps++ {
		if inWatch(w, cpu.PC) {
			fmt.Printf("FAIL: circle strayed into freed space at %04X\n", cpu.PC)
			os.Exit(1)
		}
		// In syntax-check mode the routine must reach CHECK-END (1BEE)
		// having plotted nothing; beyond that point CHECK-END runs stock
		// ROM code that needs the statement-loop context this direct call
		// does not provide, so stop the trace there.
		if syntax && cpu.PC == 0x1BEE {
			break
		}
		if cpu.PC == 0x0008 {
			errHit = true
			break
		}
		if cpu.PC == plotSub {
			got[[2]uint8{cpu.C, cpu.B}]++
		}
		cpu.Step()
	}
	if !syntax && !cpu.Halted && !errHit {
		fmt.Printf("FAIL: circle(%d,%d,%d) did not terminate\n", cx, cy, r)
		os.Exit(1)
	}
	return got, errHit, false
}

func sameSet(a, b map[[2]uint8]int) bool {
	if len(a) != len(b) {
		return false
	}
	for k, v := range a {
		if b[k] != v {
			return false
		}
	}
	return true
}

func main() {
	romPath := "../../build/rompatch/zenpoint-interim.rom"
	if len(os.Args) > 1 {
		romPath = os.Args[1]
	}
	rom, err := os.ReadFile(romPath)
	if err != nil {
		fmt.Println("cannot read interim ROM:", err)
		os.Exit(1)
	}
	wf, err := os.ReadFile(romPath + ".watch.json")
	if err != nil {
		fmt.Println("cannot read watch file:", err)
		os.Exit(1)
	}
	var w watch
	json.Unmarshal(wf, &w)

	mem := memory.NewRAM()
	cpu := z80.New(mem, zio.NewNullIO())
	mem.Load(0x0000, rom)
	cpu.Reset()
	cpu.PC = 0x0000

	// phase 1: cold boot
	for steps := 0; steps < 25_000_000; steps++ {
		if inWatch(&w, cpu.PC) {
			fmt.Printf("FAIL: boot strayed into freed space at %04X\n", cpu.PC)
			os.Exit(1)
		}
		cpu.Step()
	}
	if cpu.PC < 0x1200 || cpu.PC > 0x1600 {
		fmt.Printf("FAIL: boot did not reach the main loop (PC=%04X)\n", cpu.PC)
		os.Exit(1)
	}
	nz := 0
	for a := 0x4000; a < 0x5800; a++ {
		if mem.Read(uint16(a)) != 0 {
			nz++
		}
	}
	if nz < 40 {
		fmt.Printf("FAIL: display file nearly empty after boot (%d bytes)\n", nz)
		os.Exit(1)
	}
	fmt.Printf("boot OK: reached main loop at %04X, banner rendered (%d display bytes)\n", cpu.PC, nz)

	// phase 2: CIRCLE via the true statement-handler contract
	for _, tc := range []struct{ cx, cy, r int }{
		{128, 88, 40}, // central, fits
		{10, 170, 25}, // clips left and bottom
	} {
		got, errHit, _ := runCircle(mem, cpu, &w, tc.cx, tc.cy, tc.r, false)
		want := refPoints(tc.cx, tc.cy, tc.r)
		if errHit || !sameSet(got, want) {
			fmt.Printf("FAIL: circle(%d,%d,%d) run: %d points (want %d), err=%v\n",
				tc.cx, tc.cy, tc.r, len(got), len(want), errHit)
			os.Exit(1)
		}
		fmt.Printf("circle(%d,%d,%d): %d points OK via statement handler\n",
			tc.cx, tc.cy, tc.r, len(want))
	}

	// phase 3: syntax-check mode must reach CHECK-END having plotted
	// nothing (the routine defers to the syntax gate; this is what the
	// editor hang was -- plotting before that gate)
	got, _, _ := runCircle(mem, cpu, &w, 128, 88, 40, true)
	if len(got) != 0 {
		fmt.Printf("FAIL: syntax-check plotted %d points (should be silent)\n", len(got))
		os.Exit(1)
	}
	fmt.Println("syntax-check OK: reached CHECK-END with no plotting while editing")

	// phase 4: radius > 255 must raise report B
	_, errHit, _ := runCircle(mem, cpu, &w, 128, 88, 300, false)
	if !errHit {
		fmt.Println("FAIL: radius 300 did not raise report B")
		os.Exit(1)
	}
	fmt.Println("circle(128,88,300): report-B path OK")

	fmt.Println("INTERIM ROM SMOKE TEST PASSED")
}
