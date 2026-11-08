# Emulation components

This is a local macOS prototype. The user interface and libretro host are in
`Sources/App` and `Sources/Core/RetroBridge.c`. Star Pilot is an original cartridge
generated from `scripts/make_demo.py` and is not a commercial game ROM.

Unmodified Apple Silicon core builds are downloaded from the official Libretro
buildbot. Original download URLs and SHA-256 checksums are recorded in
`.cache/cores/manifest.json` and copied into the app as `source-manifest.json`.
Local ad-hoc code signing changes the packaged binary's signature.

| Component | Source and license information |
| --- | --- |
| libretro API header | https://github.com/libretro/libretro-common/blob/master/include/libretro.h · MIT (notice retained in the header) |
| FCEUmm (NES) | https://github.com/libretro/libretro-fceumm · GPL-2.0 |
| Snes9x (SNES) | https://github.com/libretro/snes9x · Snes9x license, noncommercial restrictions |
| Gambatte (GB/GBC) | https://github.com/libretro/gambatte-libretro · GPL-2.0 |
| Genesis Plus GX (MD/SMS/GG) | https://github.com/libretro/Genesis-Plus-GX · project license, noncommercial restrictions |
| FinalBurn Neo (arcade) | https://github.com/finalburnneo/FBNeo · project license, noncommercial restrictions |

Upstream license copies are included in `Resources/Licenses`. Consult upstream
license terms before distributing a product built from this prototype. No
console BIOS files are included.

## Separate game resource repository

The repository owner explicitly authorized importing the complete contents of
their two private-use backup repositories into this local application:

- https://github.com/mengfei523060/nesrom
- https://github.com/tomiaa12/nesRoms

The separate `zeelinkCN/game-bench-library` repository's `catalog.json` records
the displayed title, repository URL and SHA-256 content hash of every ROM. Its `sources.json`
records the exact repository commits, input counts and cross-repository
deduplication result. Public repository visibility and the platform's MIT license
do not relicense the ROMs or legacy artwork; those retain their original rights.

NES cheat presets are factual code mappings from
https://github.com/libretro/libretro-database/tree/master/cht/Nintendo%20-%20Nintendo%20Entertainment%20System
for the named ROM editions. Presets are off by default. They are not tested against
every ROM edition; users should verify a preset against the named edition.

## Translation resources

Jixun's Contra NES translation code is included as the original upstream source
archive under `Resources/Translations`. The project identifies the translation
code as BSD-3-Clause and includes separate notices for its assembler. No original
Contra game ROM is in this archive. Its source and release links, download URL,
and SHA-256 are recorded in `Resources/Translations/sources.json`.

Repository filenames are retained as display titles while bundled files are
renamed only by their content hash. Filename-based Chinese-language labels and
user-applied patches are explicitly marked as unverified. Classic series pages
match the installed editions by filename and allow manual correction.
