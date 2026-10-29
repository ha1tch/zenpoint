# zenpoint

Z80 floating point in the Sinclair 5-byte format ("Vickers maths"), original
clean-room implementation. Two deployment shapes from one source tree:

1. **Library** — relocatable, linkable into ual programs on targets with no
   ROM and no hardware floating point. Improved numerics by default. Includes
   the IEEE-754 interchange module (lossy binary32 pair, lossless binary64
   pair).
2. **ROM builds** — address-pinned to the ZX Spectrum 48K ROM entry points,
   shipped as patch sets. A QUIRKS build reproduces original ROM results
   bit-for-bit.

Status: pre-release, M0/M1 in progress. See `docs/PLAN.md`.

## License

Quad-licensed (`Apache-2.0 OR GPL-2.0-only OR GPL-3.0-only OR MPL-2.0`) --
see [LICENSE](LICENSE) for the full explanation and [LICENSES/](LICENSES/)
for the license texts. Every source file carries the SPDX expression.
Contributions are accepted under the same quad terms.

The bundled ROM binary (`rom/` in each release, `build/rompatch/`
locally) is a different case: it is a derivative of Amstrad's copyrighted
ZX Spectrum ROM and is not covered by zenpoint's own licence. See
[rompatch/AMSTRAD-ROM-PERMISSION.md](rompatch/AMSTRAD-ROM-PERMISSION.md)
for the redistribution permission it is carried under. The original,
unmodified Amstrad images the build patches are carried in `rom/base/`
under the same permission, with SHA-256 sums alongside.

Copyright (c) 2026 haitch <h@ual.li>

## Requirements

- zenas assembler, v0.9.0 or later (Z80 source; the DDCB/FDCB
  indexed bit group and 0xxH-style hex literals require 0.9.0;
  v0.9.0 and v0.11.2 assemble every target to identical bytes)
- Go 1.25+ (test drivers; they build against the published zen80 and
  zendis modules pinned in `tests/*/go.mod`, fetched on first use --
  no sibling checkouts needed)
- Python 3.10+ with mpmath (`pip install -r requirements.txt`): oracle
  model, vector, table and coefficient generation
- The original 48K ROM image, for the swap-ROM build and the circle and
  boot tests: bundled as `rom/base/48.rom`; `VICKERS_ROM=/path/to/48.rom`
  overrides it, and the Debian/Ubuntu `spectrum-roms` package
  (`/usr/share/spectrum-roms/48.rom`) is the fallback if the bundled
  copy is absent
- `git` and `repoman` (gorepoman), only for `tools/release.sh`

## Running the gate

    ./run_all.sh [--quiet]

Works from a bare checkout. It creates `build/`, generates any missing
untracked test vectors with fixed seeds (`tools/genvectors.sh`), then runs
the oracle self-tests, both builds (plain and Z80N) against every vector
file, the circle test, and the interim swap-ROM build with its boot test.
Allow a few minutes.

## Repository layout

| Path | Contents |
|---|---|
| `src/` | Z80 assembly source |
| `docs/spec/` | Format and interface specifications (clean-room phase-one notes) |
| `tools/` | Oracle model, vector generators, coefficient tooling |
| `tests/` | Differential and conformance test drivers |
| `tests/vectors/` | Generated, not tracked: `sh tools/genvectors.sh` (fixed seeds; `run_all.sh` runs it when files are missing) |
| `run_all.sh` | The canonical verification gate |
| `requirements.txt` | Python dependencies (mpmath) |
| `rom/` | Built interim ROM images; `rom/base/` holds the original, unmodified Amstrad images (48K, 128K, +2, +3) with `SHA256SUMS` |
| `LICENSE` | Explains the licensing scheme, links to `LICENSES/` |
| `LICENSES/` | The four licence texts |
| `rompatch/AMSTRAD-ROM-PERMISSION.md` | Third-party notice: Amstrad's own permission for redistributing the bundled ROM |
