// SPDX-License-Identifier: Apache-2.0 OR GPL-2.0-only OR GPL-3.0-only OR MPL-2.0
// single-vector tracer for zenpoint debugging
package main

import (
	"bufio"
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"

	zio "github.com/ha1tch/zen80/io"
	"github.com/ha1tch/zen80/memory"
	"github.com/ha1tch/zen80/z80"
	"github.com/ha1tch/zendis/pkg/disasm"
)

func loadSyms(path string) func(uint16) string {
	f, _ := os.Open(path)
	defer f.Close()
	type sym struct{ a uint16; n string }
	var syms []sym
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		// pasmo format: "name EQU 0xxxxH" or "name equ $xxxx" variants
		fl := strings.Fields(sc.Text())
		if len(fl) >= 3 {
			v := strings.TrimSuffix(strings.TrimPrefix(strings.TrimPrefix(fl[2], "$"), "0x"), "H")
			if n, err := strconv.ParseUint(v, 16, 16); err == nil {
				syms = append(syms, sym{uint16(n), fl[0]})
			}
		}
	}
	sort.Slice(syms, func(i, j int) bool { return syms[i].a < syms[j].a })
	return func(pc uint16) string {
		best := ""
		var ba uint16
		for _, s := range syms {
			if s.a <= pc && (best == "" || s.a >= ba) { best, ba = s.n, s.a }
		}
		if best == "" { return fmt.Sprintf("%04X", pc) }
		return fmt.Sprintf("%s+%d", best, pc-ba)
	}
}

func hx(b []uint8) string { return fmt.Sprintf("%x", b) }

func main() {
	// args: op aHex bHex
	op, _ := strconv.Atoi(os.Args[1])
	parse := func(s string) []uint8 {
		out := make([]uint8, 5)
		for i := 0; i < 5; i++ {
			v, _ := strconv.ParseUint(s[i*2:i*2+2], 16, 8)
			out[i] = uint8(v)
		}
		return out
	}
	a, b := parse(os.Args[2]), parse(os.Args[3])
	bin, _ := os.ReadFile("../../build/zenpoint.bin")
	name := loadSyms("../../build/zenpoint.sym")

	mem := memory.NewRAM()
	cpu := z80.New(mem, zio.NewNullIO())
	mem.Load(0x0000, []uint8{0x76})
	mem.Load(0x8000, bin)
	mem.Load(0x7000, a)
	mem.Load(0x7005, b)
	mem.Load(0x700A, []uint8{0xAA, 0xAA, 0xAA, 0xAA, 0xAA})
	cpu.Reset()
	cpu.SP = 0x6F00 - 2
	mem.Write(0x6EFE, 0x00)
	mem.Write(0x6EFF, 0x00)
	cpu.H, cpu.L = 0x70, 0x00
	cpu.D, cpu.E = 0x70, 0x05
	cpu.IXH, cpu.IXL = 0x70, 0x0A
	switch op {
	case 1: cpu.PC = 0x8000
	case 2: cpu.PC = 0x8003
	case 3: cpu.PC = 0x8006
	case 4: cpu.PC = 0x8009
	case 5: cpu.PC = 0x800C
	case 13:
		cpu.D, cpu.E = 0x70, 0x20
		cpu.PC = 0x8024
	case 15: cpu.PC = 0x802A
	case 16: cpu.PC = 0x802D
	case 17: cpu.PC = 0x8030
	case 18: cpu.PC = 0x8033
	case 19: cpu.PC = 0x8036
	case 20: cpu.PC = 0x8039
	case 21: cpu.PC = 0x803C
	case 22: cpu.PC = 0x803F
	}
	code := make([]byte, 4)
	limit := 3000
	if len(os.Args) > 4 {
		limit, _ = strconv.Atoi(os.Args[4])
	}
	for i := 0; i < limit && !cpu.Halted; i++ {
		for j := range code {
			code[j] = mem.Read(cpu.PC + uint16(j))
		}
		asm := "?"
		if ins, err := disasm.Decode(code, 0, cpu.PC); err == nil {
			asm = ins.Mnemonic
			if ins.Operands != "" {
				asm += " " + ins.Operands
			}
		}
		fmt.Printf("%-24s %-16s A=%02X F=%02X BC=%02X%02X DE=%02X%02X HL=%02X%02X IX=%02X%02X IY=%02X%02X SP=%04X | BC'=%02X%02X DE'=%02X%02X HL'=%02X%02X\n",
			name(cpu.PC), asm, cpu.A, cpu.F, cpu.B, cpu.C, cpu.D, cpu.E, cpu.H, cpu.L,
			cpu.IXH, cpu.IXL, cpu.IYH, cpu.IYL, cpu.SP,
			cpu.B_, cpu.C_, cpu.D_, cpu.E_, cpu.H_, cpu.L_)
		cpu.Step()
	}
	res := make([]uint8, 5)
	for j := 0; j < 5; j++ { res[j] = mem.Read(uint16(0x700A + j)) }
	fmt.Printf("RESULT=%s A=%02X CF=%d\n", hx(res), cpu.A, cpu.F&1)
}
