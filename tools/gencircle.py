#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 OR GPL-2.0-only OR GPL-3.0-only OR MPL-2.0
# Reference for the swap-ROM CIRCLE (T-18): midpoint integer circle with
# clipping and duplicate-pixel suppression. Emits test vectors as the
# exact multiset of points the Z80 routine must hand to PLOT-SUB, per
# (cx, cy, r) case. The Z80 side (src/circle.asm) must match point for
# point: same clipping, same duplicate suppression; order is free.
import random
import sys


def circle_points(cx, cy, r):
    pts = []

    def plot(px, py):
        if 0 <= px <= 255 and 0 <= py <= 175:
            pts.append((px, py))

    def plot4(dx, dy):
        # rows cy+dy and (if dy != 0) cy-dy; in each row cx+dx and
        # (if dx != 0) cx-dx -- mirrors src/circle.asm exactly
        for py in ([cy + dy] if dy == 0 else [cy + dy, cy - dy]):
            plot(cx + dx, py)
            if dx != 0:
                plot(cx - dx, py)

    if r == 0:
        plot4(0, 0)
        return pts
    x, y, d = r, 0, 1 - r
    while y <= x:
        plot4(x, y)
        if x != y:
            plot4(y, x)
        y += 1
        if d < 0:
            d += 2 * y + 1
        else:
            x -= 1
            d += 2 * (y - x) + 1
    return pts


def cases():
    cs = []
    for r in (0, 1, 2, 3, 4, 5, 7, 10, 17, 44, 87, 88, 120, 175, 254, 255):
        cs.append((128, 88, r))
    for c in ((0, 0), (255, 175), (0, 175), (255, 0)):
        for r in (1, 5, 20, 100, 254):
            cs.append((c[0], c[1], r))
    for c, r in (((5, 88), 10), ((250, 88), 10), ((128, 3), 10),
                 ((128, 173), 10), ((200, 200), 40), ((3, 250), 60)):
        cs.append((c[0], c[1], r))
    rng = random.Random(42)
    for _ in range(250):
        cs.append((rng.randint(0, 255), rng.randint(0, 255),
                   rng.randint(0, 255)))
    return cs


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "tests/vectors/circle.txt"
    with open(out, "w") as f:
        cs = cases()
        f.write(f"{len(cs)}\n")
        for cx, cy, r in cs:
            pts = circle_points(cx, cy, r)
            f.write(f"{cx} {cy} {r} {len(pts)}\n")
            for px, py in pts:
                f.write(f"{px} {py}\n")
    print(f"{len(cs)} cases -> {out}")


if __name__ == "__main__":
    main()
