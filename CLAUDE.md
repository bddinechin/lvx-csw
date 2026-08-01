# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This project builds a minimal GCC + GNU Binutils cross-toolchain for the **LVX** architecture, a VLIW ISA. The target triple is `lvx-mbr` (LVX bare/MBR runtime). The toolchain cross-compiles from x86_64-linux-gnu.

Sibling components (all submodules of `lvx-csw`): `lvx-newlib` (libc), `lvx-gdb` (debugger), and `lvx-gem5` — the gem5-based ISS. Its `arch/lvx` SE-mode port runs scalar integer **and** floating-point programs; the full scalar f16/f32/f64 FP surface is implemented in the runtime shim over Berkeley SoftFloat (RISC-V-conformant — see `lvx-gem5/STATUS.md` and the `lvx-fp-matches-riscv` project memory).

## LVX Variants

LVX has two variants:
- `lvx-1` (LVX_1) — current.
- `lvx-2` (LVX_2) — not yet specified; planned extension of `lvx-1` with 512-bit SIMD instructions.

**LVX is LP64 only.** There is no 32-bit mode; the `-m32` option and associated `TARGET_32` guards in the code should be removed.

## ABI

The LVX ABI is LP64. Integer/pointer arguments pass in `r0`–`r7`, with the return value in `r0`. The register conventions (argument/return/callee-saved/frame roles) are captured in `lvx-mds`'s `Convention-lvx-regular` table, which `BE/LIBC` reads to generate the `setjmp`/`longjmp` save layout (`jmpbuf.h`) — see the MDS section below.

## Machine Description System (MDS)

A large part of the target-specific source files in binutils and GDB are **generated** from a Machine Description System rather than written by hand. **The LVX MDS is real and in active use**: it's the sibling `lvx-mds` repo (see `lvx-mds/CLAUDE.md` for the full pipeline), built from `MDS/` (a family-agnostic generator) plus `lvx-family/` (the LVX-specific ISA description). Pipeline:

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

`BE/GDB` and `BE/GCC` back-ends exist in `lvx-mds` and `make config` already points `--with-gdb-prefix`/`--with-gcc-prefix` at the right places, but neither has actually been run against its target repo yet. `lvx-gdb/gdb/lvx-mds-tdep.c` is a hand-written "Tier-1" tdep instead of `BE/GDB`'s output (see `lvx-gdb/CLAUDE.md`); the `lvx-gcc/gcc/config/lvx/` files (`lvx_builtins.h`, `lvx_macros.h`, `lvx-registers.h`, `lvx-registers.md`) are likewise still hand-written and untouched by any MDS regeneration so far.

## Build Directories and Layout

All builds use out-of-tree build directories (except `lvx-gdb`'s, which lives inside that repo rather than as a sibling here, in `lvx_build_gdb_x86/`). The installed toolchain lives in `lvx-toolchain/` with binaries prefixed `lvx-mbr-` (e.g., `lvx-mbr-gcc`, `lvx-mbr-as`, `lvx-mbr-ld`). `lvx-gem5` is a submodule tracked on branch `lvx`.

For build, reconfigure, and machine-description-debugging recipes, use the `build-lvx-toolchain` skill.

> **Note:** This directory was renamed from `LVX/` to `lvx-csw/`; all absolute paths in this file and the sibling repos' `CLAUDE.md`s were updated to match, and every out-of-tree build directory (`lvx-binutils-build/`, `lvx-mds/build_lvx/`, `lvx-gdb/lvx_build_gdb_x86/`, …) was wiped and reconfigured from scratch afterward (rather than trying to patch the stale absolute paths baked into their generated `Makefile`s/`config.status`). If you ever rename this directory again, the same applies.

## Running Tests

Tests run from the build directory using DejaGnu. They require the target to be `lvx-*-*`.

## LVX Architecture Overview

The LVX ISA is a **VLIW** architecture. Key characteristics:

- **Bundles**: Up to 3 syllables per bundle (4 bytes each). The MSB of each 32-bit syllable is the parallel bit: 1 = more syllables follow in this bundle, 0 = last syllable in bundle.
- **Execution units**: BCU (Branch/Control), ALU ×2, LSU (Load/Store) ×2, EXT (extension units). A bundle can issue up to one instruction per unit.
- **Registers**: 512 total — r0–r63 (GPRs), SFR64–SFR255 (Special Function Registers), XCR256–XCR511 (Extended Control Registers). SFR240–SFR255 alias as extra GPRs.
- **Word size**: LP64 only (64-bit pointers and `long`).
- **Endianness**: Little-endian.
- **ABI**: `lvx-mbr` targets the Newlib bare runtime; `lvx-linux` targets glibc.

`LVX_NUMCORES 2` in the opcode header refers to the two architecture variants (lvx-1 and lvx-2), not physical cores.

See `lvx-binutils/CLAUDE.md` for binutils-specific implementation gotchas (stale generated headers, hardcoded relocation literals in `readelf.c`, etc.).

## LVX Bundling and Register Constraints

LVX instructions have three bundling classes that affect both scheduling and register allocation:

- **TINY**: Can pack into any ALU/LSU slot, unrestricted `registerw`/`registerz`/`registery` operands (`"r"` constraint in GCC patterns).
- **LITE**: Takes a full ALU slot (max 2 per bundle). **W and Z register operands must have the same parity** — both even (`worddRegE`, class 80) or both odd (`worddRegO`, class 81). GCC must use the `"R"` constraint (EGR_REGS, even GPRs) to satisfy this.
- **FULL**: One per bundle, full ALU slot.

**Watch the SIMD bundling class**: In LVX, 64-bit SIMD operations (`addwp`, `addhq`, `addbo`, etc.) are LITE (parity-constrained), not TINY. GCC patterns that use `"r"` constraints and `alu_tiny` type for these operations are **wrong for LVX** and will produce assembler errors like:

```
Error: Instruction `addwp' expected one of [RegClass_lvx_v1_worddRegE]
```

The fix requires adding an `EGR_REGS` register class and `"R"` constraint letter to `lvx-registers.h` and `constraints.md`, then updating the patterns.

To check the bundling class of any instruction:
```bash
grep -A15 '"<insn_name>"' lvx-binutils/opcodes/lvx-opc.c | grep bundling
```

