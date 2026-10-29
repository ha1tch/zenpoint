#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 OR GPL-2.0-only OR GPL-3.0-only OR MPL-2.0
# Generates the two default cold-boot colour patches from the
# "colours" block in the JSON plan (rompatch/interim.json) -- nothing
# hardcoded here. Both patches are single bytes, no assembler needed:
#   bordercol.bin (1 B, org 11CDh): the LD A,n operand OUT (FEh),A
#                 paints as the border before the RAM test.
#   attrinit.bin  (1 B, org 1266h): the LD A,n operand RAM-DONE stores
#                 into ATTR-P (5C8Dh), ATTR-T (5C8Fh) and BORDCR
#                 (5C48h) together -- one byte controls all three.
import json
import os
import sys


def attr_byte(paper, ink, bright=0, flash=0):
    return (flash & 1) << 7 | (bright & 1) << 6 | (paper & 7) << 3 | (ink & 7)


def main(plan_path="rompatch/interim.json", outdir="build/rompatch"):
    plan = json.load(open(plan_path))
    c = plan["colours"]
    border, paper, ink = c["border"], c["paper"], c["ink"]
    bright, flash = c.get("bright", 0), c.get("flash", 0)
    for name, v in (("border", border), ("paper", paper), ("ink", ink),
                     ("bright", bright), ("flash", flash)):
        if not 0 <= v <= 7:
            raise SystemExit(f"colours.{name} must be 0-7, got {v}")
    if bright not in (0, 1) or flash not in (0, 1):
        raise SystemExit("colours.bright/flash must be 0 or 1")

    attr = attr_byte(paper, ink, bright, flash)
    os.makedirs(outdir, exist_ok=True)
    open(f"{outdir}/bordercol.bin", "wb").write(bytes([border]))
    open(f"{outdir}/attrinit.bin", "wb").write(bytes([attr]))
    print(f"colours: border {border}, paper {paper}, ink {ink}, "
          f"bright {bright}, flash {flash} -> ATTR-P/ATTR-T/BORDCR "
          f"byte {attr:02X}h, border-paint byte {border:02X}h")


if __name__ == "__main__":
    main(*sys.argv[1:])
