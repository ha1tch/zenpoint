#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 OR GPL-2.0-only OR GPL-3.0-only OR MPL-2.0
# JSON-plan-driven ROM patcher. Nothing about the patch set is
# hardcoded here: the plan declares regions to clear and patches to
# apply; every patch is a .bin file assembled/generated for its target
# destination. The tool verifies fit, containment, and overlap before
# writing anything, and refuses rather than guessing.
#
# Plan format (all numbers hex strings or ints):
# {
#   "base":   "path to the base ROM image",
#   "output": "path for the patched image",
#   "size":   16384,
#   "regions": [ {"name": ..., "start": ..., "end": ..., "fill": "0x00"} ],
#   "patches": [ {"name": ..., "org": ..., "bin": ...,
#                 "src": optional .asm assembled here with $ZENAS,
#                 "region": optional region name for containment check} ]
# }
# Regions are cleared to their fill byte first; patches land on top.
# The tool emits <output>.watch.json listing every cleared byte range
# NOT covered by a patch, for execution watchdogs in tests.
import json
import os
import subprocess
import sys


def num(v):
    return int(v, 0) if isinstance(v, str) else int(v)


def read_version():
    # Resolved relative to this script's own location, not cwd, since
    # callers invoke this from the repo root by convention but nothing
    # enforces it (matches tools/genmsgtab.py's read_version()).
    here = os.path.dirname(os.path.abspath(__file__))
    root = os.path.dirname(here)
    with open(os.path.join(root, "VERSION")) as f:
        return f.read().strip()


def versioned_path(path, version):
    # Insert -vX.Y.Z before the extension: zenpoint-interim.rom ->
    # zenpoint-interim-v0.0.1.rom. The plan's own "output" path stays
    # the stable, unversioned name every consumer (tests/boot, the
    # watchdog) reads; this is an additional, clearly labelled copy
    # for delivery.
    base, ext = os.path.splitext(path)
    return f"{base}-v{version}{ext}"


def die(msg):
    print(f"rompatch: REFUSED: {msg}")
    sys.exit(1)


def main():
    if len(sys.argv) < 2:
        die("usage: rompatch.py <plan.json> [--base PATH] [--output PATH]")
    plan_path = sys.argv[1]
    with open(plan_path) as f:
        plan = json.load(f)
    args = sys.argv[2:]
    for i in range(0, len(args) - 1, 2):
        if args[i] == "--base":
            plan["base"] = args[i + 1]
        elif args[i] == "--output":
            plan["output"] = args[i + 1]

    base = os.environ.get("ROMPATCH_BASE", plan["base"])
    try:
        rom = bytearray(open(base, "rb").read())
    except OSError as ex:
        die(f"cannot read the base ROM image: {ex} (the bundled copy is "
            f"rom/base/48.rom; override with ROMPATCH_BASE or --base)")
    size = num(plan.get("size", 16384))
    if len(rom) != size:
        die(f"base image is {len(rom)} bytes, plan says {size}")

    regions = {}
    for reg in plan.get("regions", []):
        s, e = num(reg["start"]), num(reg["end"])
        if not (0 <= s < e <= size):
            die(f"region {reg['name']}: bad range {s:04X}-{e:04X}")
        regions[reg["name"]] = (s, e)
        fill = num(reg.get("fill", 0))
        rom[s:e] = bytes([fill]) * (e - s)

    zenas = os.environ.get("ZENAS", "zenas")
    covered = []
    report = []
    for p in plan["patches"]:
        org, binp = num(p["org"]), p["bin"]
        if "src" in p:
            os.makedirs(os.path.dirname(binp) or ".", exist_ok=True)
            r = subprocess.run([zenas, "assemble", p["src"], binp],
                               capture_output=True, text=True)
            if r.returncode != 0:
                die(f"{p['name']}: assembly failed:\n{r.stdout}{r.stderr}")
        try:
            blob = open(binp, "rb").read()
        except OSError as ex:
            die(f"{p['name']}: {ex}")
        end = org + len(blob)
        if end > size:
            die(f"{p['name']}: {org:04X}+{len(blob)} exceeds the image")
        if "region" in p:
            if p["region"] not in regions:
                die(f"{p['name']}: unknown region {p['region']}")
            rs, re_ = regions[p["region"]]
            if not (rs <= org and end <= re_):
                die(f"{p['name']}: {org:04X}-{end:04X} outside "
                    f"{p['region']} {rs:04X}-{re_:04X}")
        for (co, ce, cn) in covered:
            if org < ce and co < end:
                die(f"{p['name']} overlaps {cn} at {max(org, co):04X}")
        covered.append((org, end, p["name"]))
        rom[org:end] = blob
        slack = ""
        if "region" in p:
            rs, re_ = regions[p["region"]]
            slack = f"  region slack {re_ - end}"
        report.append(f"  {org:04X}-{end - 1:04X} {len(blob):5d} B  "
                      f"{p['name']}{slack}")

    # watchdog ranges: cleared bytes not covered by any patch
    watch = []
    for (rs, re_) in regions.values():
        pts = sorted((o, e) for (o, e, _) in covered if rs <= o < re_)
        cur = rs
        for (o, e) in pts:
            if o > cur:
                watch.append([cur, o])
            cur = max(cur, e)
        if cur < re_:
            watch.append([cur, re_])

    out = plan["output"]
    os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
    with open(out, "wb") as f:
        f.write(rom)
    with open(out + ".watch.json", "w") as f:
        json.dump({"ranges": sorted(watch)}, f)

    version = read_version()
    vout = versioned_path(out, version)
    with open(vout, "wb") as f:
        f.write(rom)
    with open(vout + ".watch.json", "w") as f:
        json.dump({"ranges": sorted(watch)}, f)

    print(f"rompatch: {base} + {len(plan['patches'])} patches -> {out}")
    for line in report:
        print(line)
    freed = sum(e - s for (s, e) in watch)
    print(f"  free (cleared, unpatched): {freed} bytes in "
          f"{len(watch)} ranges -> {out}.watch.json")
    print(f"  versioned copy (v{version}) -> {vout}")


if __name__ == "__main__":
    main()
