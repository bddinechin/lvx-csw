# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This project builds a minimal GCC + GNU Binutils cross-toolchain for the **LVX** architecture, a new VLIW ISA inspired by (but not compatible with) Kalray's KVX architecture. The target triple is `lvx-mbr` (LVX bare/MBR runtime). The toolchain cross-compiles from x86_64-linux-gnu.

The typical workflow is **porting KVX features down to the LVX subset**. The KVX reference toolchain (binutils, gcc, newlib, gdb) is the primary reference when adding or modifying LVX features; see "KVX Reference Sources" below for where to get it — it is not checked out here.

Planned components beyond this repo: `lvx-newlib`, `lvx-gdb`, and an Instruction Set Simulator (ISS).

## LVX vs KVX Architecture

KVX has three variants: `kv3-1` (KV3_V1), `kv3-2` (KV3_V2), `kv4-1` (KV4_V1).

LVX has two variants:
- `lvx-1` (LVX_1) — current, a simplification of `kv4-1`
- `lvx-2` (LVX_2) — not yet specified; planned extension of `lvx-1` with 512-bit SIMD instructions

LVX and KVX binaries are not and will not be compatible. The LVX encoding will eventually diverge further from KVX.

**LVX is LP64 only.** There is no 32-bit mode. The `-m32` option and associated `TARGET_32` guards in the code are KVX artifacts that should be removed.

## KVX Reference Sources

**Checked out at `/home/bd3/Work2/kvx-csw`** (~1.6 GB). Paths below are written
`<kvx-csw>/…` against it, so they survive a move.

It is `github.com/bddinechin/kvx-csw`, and like `lvx-csw` a **submodule superproject** —
a plain `git clone` leaves every directory below empty, and an empty submodule directory
*exists*, so a test like `[ -e gcc ]` passes on nothing. Two things bite when re-cloning:

- **Every `.gitmodules` URL is `git@github.com:`, and SSH is not set up here**
  (`Permission denied (publickey)`), so `--recurse-submodules` fails on all of them even
  though the superproject clones fine over HTTPS. Rewrite the scheme:
  `git config url."https://github.com/".insteadOf "git@github.com:"` in the superproject,
  then `git submodule update --init <names>`.
- **`--recurse-submodules` aborts on `gcc` regardless** — see below.

Initialized here: `binutils`, `gdb`, `newlib`, `mds`, `processor`, `lao`, `architecture`.
The rest (`iss`, `iss_core`, `kEnv`, `libdwarf`, `libffi`, `libmetal`, `openamp`, `simde`,
`sleef`, `elftoolchain-code`) resolve but are left uninitialized; init what you need.

When porting a feature from KVX to LVX, consult the corresponding file in:
- `<kvx-csw>/binutils/` — KVX Binutils
- `<kvx-csw>/newlib/` — KVX Newlib (libc)
- `<kvx-csw>/gdb/` — KVX GDB
- `<kvx-csw>/mds/MDS/` — KVX's own MDS, the generator this repo's `lvx-mds/MDS/` came from
- `<kvx-csw>/processor/kvx-family/` — the KVX ISA description and its `BE/` reference outputs
- `<kvx-csw>/lao/LAO/CDT/BSL/Int256.c` — Kalray's real `Int256_`, the oracle `lvx-mds`'s `BE/LAO/TEST` builds against

**There is no KVX GCC.** `.gitmodules` points `gcc` at `git@github.com:bddinechin/kvx-gcc.git`, which does not exist — `git submodule update --init gcc` fails with *repository not found*, leaving an empty `gcc/` directory. Every other submodule resolves. So for GCC work the KVX reference is simply unavailable, and `lvx-gcc/` is on its own.

## ABI

The LVX ABI is identical to the KVX kv4-v1 ABI. The specification's source is:
`<kvx-csw>/processor/VLIWCore/kvx/kv4-v1-VLIWCoreABI.tex`

Read the `.tex`. The PDF this used to name
(`processor/VLIWCore/build/kvx/kv4-v1-VLIWCoreABI.pdf`) is **not in git** — it is a build
artifact of `VLIWCore/Makefile`, so it exists only after a LaTeX build, and pointing at it
sent you looking for a file no checkout has.

## Machine Description System (MDS)

A large part of the target-specific source files in binutils and GDB are **generated** from a Machine Description System rather than written by hand. **The LVX MDS is real and in active use**: it's the sibling `lvx-mds` repo (see `lvx-mds/CLAUDE.md` for the full pipeline), built from `MDS/` (a family-agnostic generator, comparable to KVX's own MDS at `<kvx-csw>/mds/MDS/`) plus `lvx-family/` (the LVX-specific ISA description). Pipeline:

```
ISA description (.table files)
  → MDE (per-core extraction)
  → MDF (family merge)
  → BE generators (per-tool back-ends)
  → generated source files
```

From `lvx-csw/` (this directory), `make config && make all` configures and builds `lvx-mds`; `make config` already wires up `--with-binutils-prefix`/`--with-gdb-prefix`/`--with-gcc-prefix`/`--with-newlib-prefix` to point at this directory's `lvx-binutils`/`lvx-gdb`/`lvx-gcc`/`lvx-newlib` checkouts, so `make -C lvx-mds/build_lvx/BE/GBU install` (or `BE/LIBC`) delivers generated files straight into them.

**The `GBU` (binutils) and `LIBC` back-ends are actually installed somewhere so far.** `GBU`'s output goes into both `lvx-binutils` and `lvx-gdb`. **Do not hand-edit these files** — changes will be overwritten by the next `BE/GBU install`:

| File | Notes |
|------|-------|
| `opcodes/lvx-opc.c` | Opcode table, generated wholesale |
| `gas/config/lvx-parse.h` | Assembler parser tables, generated wholesale |
| `bfd/elfxx-lvx-relocs.h` | Relocation HOWTO table, generated wholesale |
| `include/opcode/lvx.h` | Opcode data structures, generated wholesale |
| `include/opcode/lvx-insn-macros.h` | Instruction macros, generated wholesale |
| `include/elf/lvx_elfids.h` | ELF ID constants; copied verbatim from `lvx-family/BE/GBU/lvx_elfids.h` in `lvx-mds`, which is itself hand-maintained, not MDS-generated |
| `bfd/reloc.c` | **Patched in place**, not overwritten — `BE/GBU`'s `patch_reloc_c.sh` replaces only the block between the `BFD_RELOC_LVX_RELOC_START`/`END` markers |
| `include/elf/lvx.h` | **Patched in place** the same way, via `patch_elf_target_h.sh` and the `START_RELOC_NUMBERS`/`END` markers |

Paths above are relative to each of `lvx-binutils/` and `lvx-gdb/` (both receive the same files).

`BE/LIBC` generates and installs `registers.h` (full SFR set, from `Register.table`/`RegField.table`) and `jmpbuf.h` (the `setjmp`/`longjmp` register-save layout, from `Convention-lvx-regular`) — see `lvx-mds/CLAUDE.md` for the full breakdown. Unlike `GBU`'s single binutils/gdb pairing, `BE/LIBC` has two different consumers with two different files each:

| File | Installed to |
|------|---------------|
| `registers.h` | `lvx-newlib/newlib/libc/sys/mbr/include/mbr/lvx/registers.h` |
| `jmpbuf.h` | `lvx-newlib/newlib/libc/machine/lvx/jmpbuf.h` **and** `lvx-gdb/gdb/lvx-jmpbuf.h` (same file, both places) |

`lvx-newlib`'s `setjmp.S` and `lvx-gdb`'s `lvx-common-tdep.c` (`lvx_get_longjmp_target`) both `#include` the generated `jmpbuf.h`/`lvx-jmpbuf.h` rather than hardcoding the RA offset — this used to be two hand-encoded copies of the same layout, cross-referenced only by a source comment on each side.

`BE/GDB` and `BE/GCC` back-ends exist in `lvx-mds` and `make config` already points `--with-gdb-prefix`/`--with-gcc-prefix` at the right places, but neither has actually been run against its target repo yet. `lvx-gdb/gdb/lvx-mds-tdep.c` is a hand-written "Tier-1" port from KVX instead of `BE/GDB`'s output (see `lvx-gdb/CLAUDE.md`); the `lvx-gcc/gcc/config/lvx/` files below are likewise still hand-adapted from KVX and untouched by any MDS regeneration so far:

| File | KVX equivalent (MDS-generated reference) |
|------|------------------------------------------|
| `lvx-gcc/gcc/config/lvx/lvx_builtins.h` | `BE/GCC/kvx/kvx_builtins.h` |
| `lvx-gcc/gcc/config/lvx/lvx_macros.h` | `BE/GCC/kvx/kvx_macros.h` |
| `lvx-gcc/gcc/config/lvx/lvx-registers.h` | `BE/GCC/kvx/kvx-registers.h` |
| `lvx-gcc/gcc/config/lvx/lvx-registers.md` | `BE/GCC/kvx/kvx-registers.md` |

Paths above under `BE/` are relative to `<kvx-csw>/processor/kvx-family/`.

## Repository Layout

```
Makefile             # Convenience wrapper for lvx-mds's build (see "Machine Description System" above)
lvx-mds/             # Machine Description System: generates target-specific source for the repos below
lvx-binutils/        # GNU Binutils source with LVX target support
lvx-binutils-build/  # Out-of-tree build directory for Binutils
lvx-gcc/             # GCC source with LVX backend
lvx-gcc-build/       # Out-of-tree build directory for GCC (not created yet -- lvx-gcc hasn't been built this way)
lvx-gdb/             # GDB source with a Tier-1 LVX target port (its own out-of-tree build dir lives inside it, lvx_build_gdb_x86/)
lvx-newlib/          # Newlib/libgloss C library, partially ported to lvx-mbr
lvx-toolchain/       # Installed cross-toolchain (bin/, lib/, include/, lvx-mbr/)
```

All builds use out-of-tree build directories (except `lvx-gdb`'s, which lives inside that repo rather than as a sibling here). The installed toolchain lives in `lvx-toolchain/` with binaries prefixed `lvx-mbr-` (e.g., `lvx-mbr-gcc`, `lvx-mbr-as`, `lvx-mbr-ld`).

> **Note:** This directory was renamed from `LVX/` to `lvx-csw/`; all absolute paths in this file and the sibling repos' `CLAUDE.md`s were updated to match, and every build directory listed above was wiped and reconfigured from scratch afterward (rather than trying to patch the stale absolute paths baked into their generated `Makefile`s/`config.status`). If you ever rename this directory again, the same applies.

## Building

### Binutils (must be built before GCC)

```bash
cd lvx-binutils-build
make -j$(nproc)
make install
```

To reconfigure from scratch:
```bash
mkdir lvx-binutils-build && cd lvx-binutils-build
../lvx-binutils/configure \
  --target=lvx-mbr \
  --prefix=/home/bd3/lvx-csw/lvx-toolchain \
  --enable-64-bit-bfd
make -j$(nproc) && make install
```

### GCC

```bash
cd lvx-gcc-build
make -j$(nproc)
make install
```

To reconfigure from scratch (requires binutils already installed):
```bash
mkdir lvx-gcc-build && cd lvx-gcc-build
../lvx-gcc/configure \
  --target=lvx-mbr \
  --prefix=/home/bd3/lvx-csw/lvx-toolchain \
  --disable-werror \
  --enable-languages=c,c++ \
  --without-headers \
  --disable-nls \
  --disable-shared \
  --disable-threads \
  --disable-libssp --disable-libgomp --disable-libquadmath \
  --enable-64-bit-bfd \
  --with-as=/home/bd3/lvx-csw/lvx-toolchain/bin/lvx-mbr-as \
  --with-ld=/home/bd3/lvx-csw/lvx-toolchain/bin/lvx-mbr-ld
make -j$(nproc) && make install
```

## Running Tests

Tests run from the build directory using DejaGnu. They require the target to be `lvx-*-*`.

```bash
# Binutils tests (in lvx-binutils-build/)
make check-gas      # GAS assembler tests
make check-ld       # Linker tests
make check-binutils # Binutils utility tests

# GCC tests (in lvx-gcc-build/)
make check-gcc
```

LVX-specific test suites:
- `lvx-binutils/gas/testsuite/gas/lvx/` — assembler tests
- `lvx-binutils/ld/testsuite/ld-lvx/` — linker tests
- `lvx-binutils/binutils/testsuite/binutils-all/lvx/` — objdump/readelf tests

## LVX Architecture Overview

The LVX ISA is a **VLIW** architecture. Key characteristics:

- **Bundles**: Up to 3 syllables per bundle (4 bytes each). The MSB of each 32-bit syllable is the parallel bit: 1 = more syllables follow in this bundle, 0 = last syllable in bundle.
- **Execution units**: BCU (Branch/Control), ALU ×2, LSU (Load/Store) ×2, EXT (extension units). A bundle can issue up to one instruction per unit.
- **Registers**: 512 total — r0–r63 (GPRs), SFR64–SFR255 (Special Function Registers), XCR256–XCR511 (Extended Control Registers). SFR240–SFR255 alias as extra GPRs.
- **Word size**: LP64 only (64-bit pointers and `long`).
- **Endianness**: Little-endian.
- **ABI**: `lvx-mbr` targets the Newlib bare runtime; `lvx-linux` targets glibc.

`LVX_NUMCORES 2` in the opcode header refers to the two architecture variants (lvx-1 and lvx-2), not physical cores.

## LVX-Specific Source Files

### GCC backend (`lvx-gcc/gcc/config/lvx/`)

| File | Purpose |
|------|---------|
| `lvx.h` | Target macros (compiler driver specs, ABI, storage layout) |
| `lvx-mbr.h` | MBR (bare runtime) OS-specific overrides |
| `lvx-linux.h` | Linux OS-specific overrides |
| `lvx-cos.h` / `lvx-cos.opt` | COS (ClusterOS) variant |
| `lvx.cc` | Core target hooks (~10K lines): scheduling, prologue/epilogue, cost model, constraints, RTL expanders |
| `lvx-builtins.cc` / `lvx-builtins.def` | Target-specific builtin functions (SIMD/vector intrinsics) |
| `lvx-shaker.c` | Post-reload pass that randomizes instruction scheduling (for validation/testing) |
| `lvx-prologue-stack-limit.cc` | Stack limit checking pass |
| `lvx-passes.def` | Inserts `pass_prologue_stack_limit` and `pass_lvx_shaker` into the pass pipeline |
| `lvx.md` | Top-level machine description (includes all sub-`.md` files) |
| `lvx-modes.def` | Mode definitions: OI (256-bit int), plus extensive SIMD vector modes up to V8OI (8×256-bit) |
| `lvx-registers.h` | Register class definitions and names |
| `lvx.opt` | Target-specific GCC options (`-march=`, `-mfarcall`, `-fhwloop`, `-fdual-bcu`, etc.) |
| `mkoffload.cc` | Offload compiler driver for GPU/accelerator targets |

Machine description sub-files in `lvx-gcc/gcc/config/lvx/`:
- `scalar.md`, `vector.md` — scalar and SIMD instruction patterns
- `builtin.md` — builtin instruction patterns (~9K lines)
- `control.md` — branches, calls, conditional execution
- `extension.md` — sign/zero extension patterns
- `scheduling.md` — DFA scheduler automaton
- `iterators.md`, `types.md`, `unspec.md` — shared attributes

### Binutils (`lvx-binutils/`)

| File | Purpose |
|------|---------|
| `opcodes/lvx-opc.c` | Opcode table (~60K lines) — the complete LVX instruction encoding table |
| `opcodes/lvx-dis.c` / `lvx-dis.h` | Disassembler |
| `gas/config/tc-lvx.c` | GAS assembler back-end (bundle packing, instruction encoding) |
| `gas/config/lvx-parse.c` / `lvx-parse.h` | Operand parser for LVX assembly syntax |
| `bfd/elfxx-lvx.c` / `elfxx-lvx.h` | ELF shared support (relocations, ABI flags) |
| `bfd/elfnn-lvx.c` | ELF target, instantiated for 64-bit via `ARCH_SIZE` |
| `bfd/cpu-lvx.c` | BFD CPU descriptor |
| `include/opcode/lvx.h` | Shared opcode data structures (bundles, syllables, operands, relocations) |
| `include/elf/lvx.h` | ELF machine number and flags |
| `ld/emulparams/elf64lvx.sh` | Linker emulation for 64-bit LVX ELF |
| `ld/emultempl/lvxelf.em` | Linker emulation template |

See `lvx-binutils/CLAUDE.md` for binutils-specific implementation gotchas (stale generated headers, hardcoded relocation literals in `readelf.c`, etc.).

## GCC Machine Description Debugging

To see the **fully expanded** RTL patterns (all iterators resolved, conditions visible) for the current build:

```bash
make -C /home/bd3/lvx-csw/lvx-gcc-build/gcc mddump
# Output: /home/bd3/lvx-csw/lvx-gcc-build/gcc/tmp-mddump.md
```

This is the authoritative source for understanding which patterns are active and how they expand. Use it when debugging mismatches between `.md` source and generated assembly.

To build only libgcc (useful for testing the compiler without a full toolchain):

```bash
make -C /home/bd3/lvx-csw/lvx-gcc-build all-target-libgcc 2>&1 | grep -E 'Error:|error:|internal compiler'
```

## LVX Bundling and Register Constraints

LVX instructions have three bundling classes that affect both scheduling and register allocation:

- **TINY**: Can pack into any ALU/LSU slot, unrestricted `registerw`/`registerz`/`registery` operands (`"r"` constraint in GCC patterns).
- **LITE**: Takes a full ALU slot (max 2 per bundle). **W and Z register operands must have the same parity** — both even (`worddRegE`, class 80) or both odd (`worddRegO`, class 81). GCC must use the `"R"` constraint (EGR_REGS, even GPRs) to satisfy this.
- **FULL**: One per bundle, full ALU slot.

**Critical difference from KVX**: In KVX, 64-bit SIMD operations (`addwp`, `addhq`, `addbo`, etc.) are TINY (unrestricted registers). In LVX they are LITE (parity-constrained). GCC patterns inherited from KVX that use `"r"` constraints and `alu_tiny` type for these operations are **wrong for LVX** and will produce assembler errors like:

```
Error: Instruction `addwp' expected one of [RegClass_lvx_v1_worddRegE]
```

The fix requires adding an `EGR_REGS` register class and `"R"` constraint letter to `lvx-registers.h` and `constraints.md`, then updating the patterns.

To check the bundling class of any instruction:
```bash
grep -A15 '"<insn_name>"' lvx-binutils/opcodes/lvx-opc.c | grep bundling
```

## Key GCC Options for LVX

- `-march=lvx-1` — select architecture variant (default; `lvx-2` is planned but not yet implemented)
- `-fhwloop` / `-fno-hwloop` — hardware loop generation (on by default)
- `-fdual-bcu` — dual BCU scheduling (on by default)
- `-fdual-lsu` — dual LSU scheduling (on by default)
- `-mfarcall` — remove range limits on call instructions
- `-mhal` — MPPA hardware abstraction layer mode
- `-fshaker-seed=N` — enable the instruction shaker pass with seed N

