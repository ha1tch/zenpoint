// SPDX-License-Identifier: Apache-2.0 OR GPL-2.0-only OR GPL-3.0-only OR MPL-2.0
// Three-way speed benchmark: Vickers 48K ROM / OpenSE 3.2.1 / zenpoint,
// T-states counted by zen80 over the shared vectors from tools/genbench.py.
//
// ROM implementations are driven through RST 28 calculator bytecode (the
// only public interface their transcendentals have); the reported figure
// subtracts a measured empty-program baseline (RST 28 + end-calc) so it
// approximates the per-operation cost. zenpoint is called at its entry
// table with a CALL+HALT stub, baseline-subtracted the same way.
// Every timed run's 5-byte result is sanity-checked against the true
// value (loose relative bound — the three implementations round
// differently by design); a run that errors or misses the bound is
// reported and excluded.
package main

import (
	"encoding/binary"
	"fmt"
	"math"
	"os"
	"sort"

	zio "github.com/ha1tch/zen80/io"
	"github.com/ha1tch/zen80/memory"
	"github.com/ha1tch/zen80/z80"
)

var calcOp = map[uint8]uint8{ // differential-harness op id -> calc opcode
	1: 0x0F, 2: 0x03, 4: 0x04, 5: 0x05,
	14: 0x28, 15: 0x25, 16: 0x26, 17: 0x1F, 18: 0x20, 19: 0x21,
	20: 0x24, 21: 0x22, 22: 0x23,
}

var zpEntry = map[uint8]uint16{
	1: 0x8000, 2: 0x8003, 4: 0x8009, 5: 0x800C, 14: 0x8027,
	15: 0x802A, 16: 0x802D, 17: 0x8030, 18: 0x8033, 19: 0x8036,
	20: 0x8039, 21: 0x803C, 22: 0x803F,
}

var opName = map[uint8]string{
	1: "add", 2: "sub", 4: "mul", 5: "div", 14: "sqrt", 15: "ln",
	16: "exp", 17: "sin", 18: "cos", 19: "tan", 20: "atn",
	21: "asn", 22: "acs",
}

var opOrder = []uint8{1, 2, 4, 5, 14, 15, 16, 17, 18, 19, 20, 21, 22}

const (
	stkBase  = 0x9000
	driver   = 0x7000
	stackTop = 0x6F00
	maxStep  = 3_000_000
)

// decode a 5-byte value to float64 (both forms)
func decode(b []uint8) float64 {
	if b[0] == 0 {
		u := uint16(b[2]) | uint16(b[3])<<8
		v := float64(u)
		if b[1] == 0xFF {
			v = v - 65536.0
		}
		return v
	}
	m := (uint32(b[1])|0x80)<<24 | uint32(b[2])<<16 | uint32(b[3])<<8 | uint32(b[4])
	v := float64(m) * math.Pow(2, float64(int(b[0])-160))
	if b[1]&0x80 != 0 {
		v = -v
	}
	return v
}

type romDriver struct {
	rom []uint8
}

// run executes one calculator program over the operands and returns
// (cycles, result, ok). opcode 0 means empty program (baseline).
func (r *romDriver) run(opcode uint8, a, b []uint8) (uint64, [5]uint8, bool) {
	mem := memory.NewRAM()
	cpu := z80.New(mem, zio.NewNullIO())
	mem.Load(0x0000, r.rom)

	// minimal Spectrum environment for CALCULATE
	// sysvars: MEM -> MEMBOT, STKBOT/STKEND -> our calc stack
	membot := uint16(0x5C92)
	mem.Write(0x5C68, uint8(membot&0xFF)) // MEM
	mem.Write(0x5C69, uint8(membot>>8))
	mem.Write(0x5C63, uint8(stkBase&0xFF)) // STKBOT
	mem.Write(0x5C64, uint8(stkBase>>8))
	n := 1
	if b != nil {
		n = 2
	}
	end := uint16(stkBase + 5*n)
	mem.Write(0x5C65, uint8(end&0xFF)) // STKEND
	mem.Write(0x5C66, uint8(end>>8))
	mem.Write(0x5C3D, uint8(stackTop&0xFF)) // ERR-SP (unused if no error)
	mem.Write(0x5C3E, uint8(stackTop>>8))
	for i := 0; i < 5; i++ {
		mem.Write(uint16(stkBase+i), a[i])
	}
	if b != nil {
		for i := 0; i < 5; i++ {
			mem.Write(uint16(stkBase+5+i), b[i])
		}
	}
	// driver: RST 28 / [opcode] / end-calc / HALT
	p := uint16(driver)
	mem.Write(p, 0xEF) // RST 28
	p++
	if opcode != 0 {
		mem.Write(p, opcode)
		p++
	}
	mem.Write(p, 0x38) // end-calc
	p++
	mem.Write(p, 0x76) // HALT

	cpu.Reset()
	cpu.SP = 0xFF00 // must sit ABOVE STKEND or TEST-ROOM reports out-of-memory
	cpu.IYH, cpu.IYL = 0x5C, 0x3A
	cpu.PC = driver

	var cycles uint64
	steps := 0
	for !cpu.Halted && steps < maxStep {
		if cpu.PC == 0x0008 { // error restart hit
			return 0, [5]uint8{}, false
		}
		cycles += uint64(cpu.Step())
		steps++
	}
	if !cpu.Halted {
		return 0, [5]uint8{}, false
	}
	// result: top of calc stack = STKEND-5
	se := uint16(mem.Read(0x5C65)) | uint16(mem.Read(0x5C66))<<8
	var res [5]uint8
	for i := 0; i < 5; i++ {
		res[i] = mem.Read(se - 5 + uint16(i))
	}
	return cycles, res, true
}

type zpDriver struct {
	bin []uint8
}

func (z *zpDriver) run(op uint8, a, b []uint8) (uint64, [5]uint8, bool) {
	mem := memory.NewRAM()
	cpu := z80.New(mem, zio.NewNullIO())
	mem.Load(0x8000, z.bin)
	if os.Getenv("ZP_Z80N") == "1" {
		cpu.Z80N = true
	}
	// well clear of the zenpoint image (0x8000 + ~6.4K)
	const aBuf, bBuf, rBuf = 0xA000, 0xA008, 0xA010
	for i := 0; i < 5; i++ {
		mem.Write(uint16(aBuf+i), a[i])
	}
	if b != nil {
		for i := 0; i < 5; i++ {
			mem.Write(uint16(bBuf+i), b[i])
		}
	}
	// driver: CALL entry / HALT   (op 0 = baseline: CALL a bare RET)
	entry := uint16(0x7800)
	mem.Write(0x7800, 0xB7) // OR A: clear the post-reset carry
	mem.Write(0x7801, 0xC9) // RET stub for baseline
	if op != 0 {
		entry = zpEntry[op]
	}
	mem.Write(driver, 0xCD) // CALL nn
	mem.Write(driver+1, uint8(entry&0xFF))
	mem.Write(driver+2, uint8(entry>>8))
	mem.Write(driver+3, 0x76) // HALT
	cpu.Reset()
	cpu.SP = stackTop
	cpu.H, cpu.L = uint8(aBuf>>8), uint8(aBuf&0xFF)
	cpu.D, cpu.E = uint8(bBuf>>8), uint8(bBuf&0xFF)
	cpu.IXH, cpu.IXL = uint8(rBuf>>8), uint8(rBuf&0xFF)
	cpu.PC = driver
	var cycles uint64
	steps := 0
	for !cpu.Halted && steps < maxStep {
		cycles += uint64(cpu.Step())
		steps++
	}
	if !cpu.Halted || cpu.F&1 != 0 {
		return 0, [5]uint8{}, false
	}
	var res [5]uint8
	for i := 0; i < 5; i++ {
		res[i] = mem.Read(rBuf + uint16(i))
	}
	return cycles, res, true
}

type runner interface {
	run(op uint8, a, b []uint8) (uint64, [5]uint8, bool)
}

func main() {
	vecPath := "../../tests/vectors/bench.bin"
	if len(os.Args) > 1 {
		vecPath = os.Args[1]
	}
	vecs, err := os.ReadFile(vecPath)
	if err != nil {
		panic(err)
	}
	n := binary.LittleEndian.Uint32(vecs[:4])
	recs := vecs[4:]

	impls := []struct {
		name string
		r    runner
		bops map[uint8]uint8 // op id -> implementation opcode (ROMs)
	}{}
	vickersPath := os.Getenv("VICKERS_ROM")
	if vickersPath == "" {
		vickersPath = "../../rom/base/48.rom"
		if _, err := os.Stat(vickersPath); err != nil {
			vickersPath = "/usr/share/spectrum-roms/48.rom"
		}
	}
	opensePath := os.Getenv("OPENSE_ROM")
	if opensePath == "" {
		opensePath = "../../../opense321/rom.bin"
	}
	if rom, err := os.ReadFile(vickersPath); err == nil {
		impls = append(impls, struct {
			name string
			r    runner
			bops map[uint8]uint8
		}{"vickers", &romDriver{rom}, calcOp})
	}
	if rom, err := os.ReadFile(opensePath); err == nil {
		impls = append(impls, struct {
			name string
			r    runner
			bops map[uint8]uint8
		}{"opense", &romDriver{rom}, calcOp})
	}
	zpBin := os.Getenv("ZP_BIN")
	if zpBin == "" {
		zpBin = "../../build/zenpoint.bin"
	}
	if bin, err := os.ReadFile(zpBin); err == nil {
		impls = append(impls, struct {
			name string
			r    runner
			bops map[uint8]uint8
		}{"zenpoint", &zpDriver{bin}, nil})
	}

	type stat struct{ vals []uint64 }
	results := map[string]map[uint8]*stat{}
	skipped := map[string]int{}

	for _, im := range impls {
		results[im.name] = map[uint8]*stat{}
		// baseline
		base, _, ok := im.r.run(0, make([]uint8, 5), nil)
		if !ok {
			fmt.Printf("%s: BASELINE FAILED\n", im.name)
			continue
		}
		const rec = 19
		for i := uint32(0); i < n; i++ {
			r := recs[i*rec : (i+1)*rec]
			op := r[0]
			a, bb := r[1:6], r[6:11]
			truth := math.Float64frombits(binary.LittleEndian.Uint64(r[11:19]))
			var b []uint8
			if op == 1 || op == 2 || op == 4 || op == 5 {
				b = bb
			}
			runOp := op
			if im.bops != nil {
				runOp = im.bops[op]
			}
			cyc, res, ok := im.r.run(runOp, a, b)
			if !ok {
				fmt.Fprintf(os.Stderr, "%s %s: no result (a=%x)\n", im.name, opName[op], a)
				skipped[im.name]++
				continue
			}
			got := decode(res[:])
			tol := 2e-6 * math.Max(1.0, math.Abs(truth))
			if math.Abs(got-truth) > tol && math.Abs(truth) > 1e-30 {
				skipped[im.name]++
				continue
			}
			if results[im.name][op] == nil {
				results[im.name][op] = &stat{}
			}
			results[im.name][op].vals = append(results[im.name][op].vals, cyc-base)
		}
	}

	fmt.Printf("%-6s", "op")
	for _, im := range impls {
		fmt.Printf("  %22s", im.name+" med/min/max")
	}
	fmt.Println()
	for _, op := range opOrder {
		fmt.Printf("%-6s", opName[op])
		for _, im := range impls {
			s := results[im.name][op]
			if s == nil || len(s.vals) == 0 {
				fmt.Printf("  %22s", "-")
				continue
			}
			v := append([]uint64(nil), s.vals...)
			sort.Slice(v, func(i, j int) bool { return v[i] < v[j] })
			fmt.Printf("  %8d %6d %6d", v[len(v)/2], v[0], v[len(v)-1])
		}
		fmt.Println()
	}
	for name, k := range skipped {
		fmt.Printf("skipped %s: %d (error path or accuracy bound)\n", name, k)
	}
}
