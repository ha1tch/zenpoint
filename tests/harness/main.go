// SPDX-License-Identifier: Apache-2.0 OR GPL-2.0-only OR GPL-3.0-only OR MPL-2.0
// zenpoint differential harness: runs assembled routines on the zen80 core
// against oracle-generated vectors (record format v2, 26 bytes).
package main

import (
	"encoding/binary"
	"fmt"
	"os"

	zio "github.com/ha1tch/zen80/io"
	"github.com/ha1tch/zen80/memory"
	"github.com/ha1tch/zen80/z80"
)

const (
	orgAddr  = 0x8000
	aBuf     = 0x7000
	bBuf     = 0x7008
	rBuf     = 0x7010
	stackTop = 0x6F00
	haltAddr = 0x0000
)

var entries = map[uint8]uint16{
	1: 0x8000, 2: 0x8003, 3: 0x8006, 4: 0x8009, 5: 0x800C,
	6: 0x800F, 7: 0x8012, 8: 0x8015, 9: 0x8018, 10: 0x801B, 11: 0x801E,
	14: 0x8027, 15: 0x802A, 16: 0x802D, 17: 0x8030, 18: 0x8033, 19: 0x8036,
	20: 0x8039, 21: 0x803C, 22: 0x803F,
}

func srcLen(op uint8) int {
	switch op {
	case 7:
		return 8
	case 9:
		return 4
	}
	return 5
}

func resLen(op uint8) int {
	switch op {
	case 6:
		return 8
	case 8:
		return 4
	}
	return 5
}

func main() {
	binPath := "../../build/zenpoint.bin"
	if len(os.Args) > 2 {
		binPath = os.Args[2]
	}
	bin, err := os.ReadFile(binPath)
	if err != nil {
		panic(err)
	}
	vecPath := "../../tests/vectors/all.bin"
	if len(os.Args) > 1 {
		vecPath = os.Args[1]
	}
	vecs, err := os.ReadFile(vecPath)
	if err != nil {
		panic(err)
	}
	mem := memory.NewRAM()
	cpu := z80.New(mem, zio.NewNullIO())
	if os.Getenv("ZEN_Z80N") == "1" {
		cpu.Z80N = true
	}

	if len(vecs) > 4 && string(vecs[:4]) == "ZS1\x00" {
		runStrings(mem, cpu, bin, vecs[4:])
		return
	}
	n := binary.LittleEndian.Uint32(vecs[:4])
	recs := vecs[4:]

	fails, total := 0, 0
	const rec = 26
	for i := uint32(0); i < n; i++ {
		r := recs[i*rec : (i+1)*rec]
		op, a, b, status, want := r[0], r[1:9], r[9:17], r[17], r[18:26]

		mem.Load(0x0000, []uint8{0x76}) // HALT
		mem.Load(orgAddr, bin)
		mem.Load(aBuf, a[:srcLen(op)])
		mem.Load(bBuf, b[:5])
		mem.Load(rBuf, []uint8{0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA})
		cpu.Reset()
		cpu.SP = stackTop - 2
		mem.Write(stackTop-2, uint8(haltAddr&0xFF))
		mem.Write(stackTop-1, uint8(haltAddr>>8))
		cpu.H, cpu.L = uint8(aBuf>>8), uint8(aBuf&0xFF)
		cpu.D, cpu.E = uint8(bBuf>>8), uint8(bBuf&0xFF)
		cpu.IXH, cpu.IXL = uint8(rBuf>>8), uint8(rBuf&0xFF)
		cpu.PC = entries[op]

		steps := 0
		for !cpu.Halted && steps < 200000 {
			cpu.Step()
			steps++
		}
		total++
		if !cpu.Halted {
			fmt.Printf("TIMEOUT op=%d a=%x\n", op, a)
			fails++
			continue
		}
		carry := cpu.F & 0x01
		if op == 3 {
			if carry != 0 || cpu.A != want[0] {
				fails++
				if fails <= 20 {
					fmt.Printf("FAIL cmp a=%x b=%x got A=%02x CF=%d want %02x\n",
						a[:5], b[:5], cpu.A, carry, want[0])
				}
			}
			continue
		}
		if status != 0 {
			if carry == 0 || cpu.A != status {
				fails++
				if fails <= 20 {
					fmt.Printf("FAIL op=%d a=%x want err %d got A=%02x CF=%d\n",
						op, a, status, cpu.A, carry)
				}
			}
			continue
		}
		rl := resLen(op)
		got := make([]uint8, rl)
		ok := carry == 0
		for j := 0; j < rl; j++ {
			got[j] = mem.Read(uint16(rBuf + j))
			if got[j] != want[j] {
				ok = false
			}
		}
		if !ok {
			fails++
			if fails <= 20 {
				fmt.Printf("FAIL op=%d a=%x b=%x got=%x CF=%d want=%x\n",
					op, a[:srcLen(op)], b[:5], got, carry, want[:rl])
			}
		}
	}
	fmt.Printf("%d/%d passed\n", total-fails, total)
	if fails > 0 {
		os.Exit(1)
	}
	fmt.Println("PASS")
}

// runStrings executes ZS1 string-conversion vectors (36-byte records).
func runStrings(mem *memory.RAM, cpu *z80.Z80, bin []uint8, data []uint8) {
	n := binary.LittleEndian.Uint32(data[:4])
	recs := data[4:]
	const rec = 36
	const strBuf, outBuf = 0x7000, 0x7020
	fails, total := 0, 0
	for i := uint32(0); i < n; i++ {
		r := recs[i*rec : (i+1)*rec]
		op, ln := r[0], r[1]
		payload, status, resLen, want := r[2:18], r[18], r[19], r[20:36]

		mem.Load(0x0000, []uint8{0x76})
		mem.Load(0x8000, bin)
		for j := 0; j < 32; j++ {
			mem.Write(uint16(strBuf+j), 0xAA)
			mem.Write(uint16(outBuf+j), 0xAA)
		}
		mem.Load(strBuf, payload[:ln])
		mem.Write(uint16(strBuf+int(ln)), 0) // terminator / stop byte
		cpu.Reset()
		cpu.SP = 0x6F00 - 2
		mem.Write(0x6EFE, 0)
		mem.Write(0x6EFF, 0)
		cpu.H, cpu.L = 0x70, 0x00
		total++
		if op == 12 {
			cpu.IXH, cpu.IXL = 0x70, 0x20
			cpu.PC = 0x8021
		} else {
			cpu.D, cpu.E = 0x70, 0x20
			cpu.PC = 0x8024
		}
		steps := 0
		for !cpu.Halted && steps < 400000 {
			cpu.Step()
			steps++
		}
		if !cpu.Halted {
			fmt.Printf("TIMEOUT op=%d %q\n", op, payload[:ln])
			fails++
			continue
		}
		carry := cpu.F & 0x01
		if status != 0 {
			if carry == 0 || cpu.A != status {
				fails++
				if fails <= 20 {
					fmt.Printf("FAIL op=%d %q want err %d got A=%02x CF=%d\n",
						op, payload[:ln], status, cpu.A, carry)
				}
			}
			continue
		}
		ok := carry == 0 && cpu.A == resLen
		var cmpLen int
		if op == 12 {
			cmpLen = 5
		} else {
			cmpLen = int(resLen) + 1 // string plus NUL
		}
		got := make([]uint8, cmpLen)
		for j := 0; j < cmpLen; j++ {
			got[j] = mem.Read(uint16(outBuf + j))
			exp := want[j]
			if op == 13 && j == int(resLen) {
				exp = 0
			}
			if got[j] != exp {
				ok = false
			}
		}
		if !ok {
			fails++
			if fails <= 20 {
				fmt.Printf("FAIL op=%d in=%q got=%x A=%d CF=%d want=%x len=%d\n",
					op, payload[:ln], got, cpu.A, carry, want[:cmpLen], resLen)
			}
		}
	}
	fmt.Printf("%d/%d passed\n", total-fails, total)
	if fails > 0 {
		os.Exit(1)
	}
	fmt.Println("PASS")
}
