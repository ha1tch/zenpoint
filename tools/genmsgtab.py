#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 OR GPL-2.0-only OR GPL-3.0-only OR MPL-2.0
# Generates the compressed report-message table for the swap ROM
# (decided wordings, docs/notes/SIZE_COMPARISON.md) plus the two
# 2-byte PO-MSG base-operand patches that re-anchor the ", "
# separator and the banner after the table shrinks.
#
# Layout (bit-7-terminated strings, walked by terminator count):
#   1392h: messages 0..R in order, then ", ", then the banner.
# The byte at 1391h (the 0x80 marker) is not touched.
# PO-MSG bases point at the TERMINATOR BEFORE the wanted entry:
#   134Bh operand (was 1536h) -> last byte of message R
#   1297h operand (was 1538h) -> last byte of ", "
import os
import sys

ORG = 0x1392
MSGS = [
    "OK",                    # 0
    "Bad NEXT",              # 1
    "Variable not found",    # 2
    "Subscript wrong",       # 3
    "Out of memory",         # 4
    "Bad coords",            # 5
    "Num overflow",          # 6
    "Bad RETURN",            # 7
    "?",                     # 8  (dead: End of file)
    "Stopped",               # 9
    "Invalid argument",      # A
    "Integer out of range",  # B
    "Bad BASIC",             # C
    "BREAK",                 # D
    "Out of DATA",           # E
    "?",                     # F  (dead: Invalid file name)
    "No room for line",      # G
    "Stopped",               # H
    "Bad FOR",               # I
    "Bad I/O device",        # J
    "Invalid colour",        # K
    "BREAK",                 # L
    "Bad RAMTOP",            # M
    "Statement lost",        # N
    "Bad stream",            # O
    "Bad FN",                # P
    "Bad Param",             # Q
    "?",                     # R  (dead: Tape loading error)
]
COMMA = ", "
def read_version():
    # The swap ROM's boot banner tracks the library's own VERSION file
    # directly -- one version number for the whole project, kept in
    # sync everywhere (including here) by repoman's syncver. Resolved
    # relative to this script's own location, not cwd, since callers
    # invoke this from the repo root by convention but nothing enforces
    # it.
    here = os.path.dirname(os.path.abspath(__file__))
    root = os.path.dirname(here)
    with open(os.path.join(root, "VERSION")) as f:
        return f.read().strip()


# Boot banner: exactly one 32-column line, no wrap. 7Fh is the
# charset's (c) glyph. The guard in main() refuses anything wider
# than the bottom line holds.
ROM_VERSION = read_version()
BANNER = f"\x7f 1982 Sinclair  zenpoint v{ROM_VERSION}"


def enc(s):
    b = bytes(ord(c) for c in s[:-1]) + bytes([ord(s[-1]) | 0x80])
    return b


def main(outdir="build/rompatch"):
    if len(BANNER) > 32:
        raise SystemExit(f"banner is {len(BANNER)} columns, wraps the line")
    tab = b""
    addr = ORG
    r_last = comma_last = None
    for i, m in enumerate(MSGS):
        e = enc(m)
        addr += len(e)
        tab += e
        if i == len(MSGS) - 1:
            r_last = addr - 1
    tab += enc(COMMA)
    addr += len(COMMA)
    comma_last = addr - 1
    tab += enc(BANNER)
    addr += len(BANNER)
    end = addr

    os.makedirs(outdir, exist_ok=True)
    with open(f"{outdir}/msgtable.bin", "wb") as f:
        f.write(tab)
    with open(f"{outdir}/msgref_comma.bin", "wb") as f:
        f.write(bytes([r_last & 0xFF, r_last >> 8]))
    with open(f"{outdir}/msgref_banner.bin", "wb") as f:
        f.write(bytes([comma_last & 0xFF, comma_last >> 8]))
    print(f"msgtable: {ORG:04X}-{end - 1:04X} ({len(tab)} bytes), "
          f"hole {end:04X}-1554 ({0x1555 - end} bytes)")
    print(f"comma anchor {r_last:04X} -> patch 134Bh; "
          f"banner anchor {comma_last:04X} -> patch 1297h")
    print(f"banner {len(BANNER)}/32 columns: {BANNER.replace(chr(0x7f), '(c)')}")


if __name__ == "__main__":
    main(*sys.argv[1:])
