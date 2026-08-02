# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This project builds a minimal GCC + GNU Binutils cross-toolchain for the **LVX** architecture, a VLIW ISA. The target triple is `lvx-mbr` (LVX bare/MBR runtime). The toolchain cross-compiles from x86_64-linux-gnu.

Sibling components (all submodules of `lvx-csw`): `lvx-newlib` (libc), `lvx-gdb` (debugger), and `lvx-gem5` — the gem5-based ISS. Its `arch/lvx` SE-mode port runs scalar integer **and** floating-point programs; the full scalar f16/f32/f64 FP surface is implemented in the runtime shim over Berkeley SoftFloat (RISC-V-conformant — see `lvx-gem5/STATUS.md` and the `lvx-fp-matches-riscv` project memory).

## LVX Variants

LVX has two variants:
- `lvx-1` (LVX_1) — current.
- `lvx-2` (LVX_2) — not yet specified; planned extension of `lvx-1` with 512-bit SIMD instructions.

**LVX is LP64 only.** There is no 32-bit mode. The `-m32` option and the `TARGET_32` guards are already gone from the LVX-specific sources (remaining hits are upstream GCC ChangeLogs).

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

`BE/GDB` and `BE/GCC` back-ends exist in `lvx-mds` and `make config` already points `--with-gdb-prefix`/`--with-gcc-prefix` at the right places. `BE/GDB` has not been run against its target repo: `lvx-gdb/gdb/lvx-mds-tdep.c` is a hand-written "Tier-1" tdep instead of its output (see `lvx-gdb/CLAUDE.md`).

`BE/GCC` is a mixed case. `lvx-gcc/gcc/gcc/config/lvx/lvx-registers.h` and `lvx-registers.md` **are** its output and are byte-identical to `lvx-mds/lvx-refs/BE/GCC/lvx/` — treat them as generated and don't hand-edit them. They had previously drifted (an `EGR_REGS` class added by hand, a stale `rvc` register name, a different `LVX_FRAME_POINTER_VIRT_REGNO`), which is exactly the failure mode to avoid. Note `lvx-family/BE/GCC` does not exist yet — only the family-agnostic `MDS/BE/GCC` — so there is no LVX-specific half of that back-end. `lvx_builtins.h` and `lvx_macros.h` remain hand-written and untouched by any regeneration.

## Build Directories and Layout

`lvx-gcc/` follows the same shape as `lvx-llvm/`: a plain directory in this
repo holding a submodule that is a genuine GitHub fork of the upstream project.
The fork of `gcc-mirror/gcc` lives at `lvx-gcc/gcc` on branch `lvx-gcc`, so the
backend sources are at `lvx-gcc/gcc/gcc/config/lvx/` — one level deeper than
before, exactly as `lvx-mlir/llvm-project/mlir/...` is.

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
- **LITE**: Takes a full ALU slot (max 2 per bundle).
- **FULL**: One per bundle, full ALU slot.

**There is no register-parity constraint any more.** LITE instructions used to require their W and Z operands to share a parity — both even (`worddRegE`) or both odd (`worddRegO`) — which GCC satisfied with an `EGR_REGS` class and a `"R"` constraint letter hand-added to `lvx-registers.h` and `constraints.md`. The ISA refactoring removed every Format that relied on those classes: `lvx-binutils/include/opcode/lvx.h` now has `singleReg`, `pairedReg` and `quadReg` for the general registers with no parity variant at all (the only surviving `RegE`/`RegO` pair, `xwordqRegE`/`xwordqRegO`, is on the XVR extended-vector file, not the GPRs). `EGR_REGS`, `OGR_REGS` and the `"R"`/`"Q"` constraints are gone; those operands take plain `"r"`.

The 64-bit SIMD family that motivated the parity rule is gone too: the ISA has no `bo`/`hq`/`wp` integer arithmetic (`addwp`, `addhq`, `addbo`, …), so `lvx-gcc` no longer has 64-bit vector patterns or builtins. The six 64-bit vector *modes* are still declared, because `CHUNK`/`HALF` use them to name the 64-bit piece of a wider vector — LVX registers are 64-bit, so a 128-bit value lives in a register pair and every wide move splits into halves.

**Still outstanding in `lvx-gcc`**: 128-bit SIMD is largely emitted as *pairs* of 64-bit instructions on `%x`/`%y` register halves (`addhq` where the ISA has `addho`, `compnd` where it has `compndp`). Those mnemonics exist on neither core; `make -C lvx-gcc-build/gcc mddump` plus a check against `lvx-opc.c` lists them. This is what stops `libgcc` building (`divmod{si,vxdi,vxsi}`).

To check the bundling class of any instruction:
```bash
grep -A15 '"<insn_name>"' lvx-binutils/opcodes/lvx-opc.c | grep bundling
```

