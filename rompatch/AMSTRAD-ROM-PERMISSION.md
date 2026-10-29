# Amstrad ROM redistribution permission

This project's ROM builds (`rompatch/`, and the `rom/` directory of
each release archive) contain a **derivative of the original
Sinclair/Amstrad ZX Spectrum 48K ROM**: most of its bytes are
unmodified Amstrad-copyright code (in particular the Vickers
floating-point routines this project studies and, eventually,
replaces). Only the reclaimed regions listed in
`rompatch/interim.json` are zenpoint's own code.

**The ROM binary is therefore not covered by this project's own
licence** (see `../LICENSE`). Amstrad's copyright in the unmodified
portions is retained, and is redistributed here solely under
Amstrad's own permission, described below -- not under the
Apache-2.0/GPL-2.0-only/GPL-3.0-only/MPL-2.0 terms that cover
zenpoint's own source.

## The permission

On 31 August 1999, Cliff Lawson of Amstrad plc posted to the Usenet
group `comp.sys.sinclair` (cross-posted to `comp.sys.amstrad.8bit`)
giving blanket permission for emulator writers to distribute
Sinclair/Amstrad ZX Spectrum ROM images:

> Amstrad are happy for emulator writers to include images of our
> copyrighted code as long as the (c)opyright messages are not
> altered.

Modification for emulation purposes is explicitly permitted, under
that same copyright proviso. Amstrad asked that any program or manual
distributing the ROM include a note to this effect -- reproduced here
as that note:

> Amstrad have kindly given their permission for the redistribution of
> their copyrighted material but retain that copyright.

Conditions, per the original post: no charge may be made for the ROM
code itself (emulator authors may charge for their own written code
separately); the permission covers the Spectrum 48K/128K and
Amstrad's own +2/+2A/+3 ROMs -- **not** the ZX80/ZX81 or Interface 1/2
ROMs, whose copyright Amstrad stated it does not hold.

## Scope of this project's use

zenpoint's swap-ROM builds patch the 48K ROM in place: most of the
image remains Amstrad's original, unmodified code, falling squarely
within the permission above. The patched regions -- BEEP, tape/
printer/Interface 1 stubs, the message table, SCREEN$, CIRCLE, DRAW,
boot colours and the boot banner (see `rompatch/interim.json`) -- are
zenpoint's own work, licensed as stated in `../LICENSE`. No charge is
made for the ROM code in any zenpoint release.

## Unmodified images (`rom/base/`)

This tree also carries the original, unmodified images the swap-ROM
build patches, so the gate runs without any external ROM package:
`48.rom`, `128-0.rom`, `128-1.rom`, `plus2-0.rom`, `plus2-1.rom` and
`plus3-0.rom` to `plus3-3.rom` -- the Spectrum 48K/128K and Amstrad
+2/+3 ROMs the permission above covers. They are byte-identical to the
Debian `spectrum-roms` package (version 20081224-5); SHA-256 sums are in
`rom/base/SHA256SUMS`, and Amstrad's copyright messages are unaltered.
The same conditions apply: no charge is made for the ROM code.

Deliberately left out: the Interface 1/2 ROM (excluded by the permission),
the Timex TC2048 ROM, and the Spanish-language 128K ROMs (a localisation
whose copyright position the wording above does not settle).

## Sources

This notice quotes and paraphrases Cliff Lawson's original post as
compiled by four independent sources, cross-checked for consistency
of the quoted wording:

- Usenet archive via `comp.sys.amstrad.8bit`:
  <https://groups.google.com/g/comp.sys.amstrad.8bit/c/HtpBU2Bzv_U/m/HhNDSU3MksAJ>
- World of Spectrum's own permissions page (endorses the same
  permission for Spectrum ROM distribution):
  <https://worldofspectrum.net/permits/>
- The Fuse emulator project's own ROM distribution notice, which
  documents the same permission for its bundled ROMs:
  <https://github.com/rpmfusion/fuse-emulator-roms/blob/master/rom-distribution.txt>
- Debian/Ubuntu's own `spectrum-roms` package copyright file
  (`/usr/share/doc/spectrum-roms/copyright`, Colin Watson's original
  Debian packaging), which excerpts the same Usenet post directly and
  additionally confirms point 4 of Cliff Lawson's own Q&A -- "Can you
  distribute modified ROMs? If you like (with that (c) proviso)" --
  covering this project's swap-ROM case explicitly. This project's own
  CI and local builds get the base 48K ROM from this same package
  (`apt-get install spectrum-roms`), so it is both a citation and the
  actual supply chain for the base image every zenpoint ROM build
  patches.

If Amstrad's position on ROM redistribution has changed since 1999, or
a current rights holder disputes this, open an issue rather than
relying on this notice alone -- it was last verified 2026-09-05.
