# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

This is a fork of upstream `llvm-project` (currently on branch `lvx-mlir`, tracking upstream `main`) whose purpose is to build **`lvx-mlir`**: a family of MLIR dialects representing pre-register-allocation, pre-scheduling machine code for a custom VLIW-ish architecture called **LVX** (scalar + SIMD, unified 64-bit GPR file `$r0-$r63`). The design follows *"A Multi-level Compiler Backend for Accelerated Micro-kernels Targeting RISC-V ISA Extensions"* (CGO'25): a low-level dialect denotes real assembly instructions as operations, and once register allocation runs, physical registers are represented via MLIR's type system rather than as attributes. The end goal (not yet built) is register allocation and software pipelining directly on this IR, bypassing the classic "lower everything to the `llvm` dialect" path.

The LLVM checkout is the **`llvm-project/` submodule** of this directory (it was folded in
from a standalone sibling repo; paths below that start with `mlir/`, `llvm/` or `build/` are relative to `llvm-project/`, so `cd llvm-project` first). Everything LVX-specific
lives under `llvm-project/mlir/{include,lib,test}/**/LVX*` and
`llvm-project/mlir/{include,lib,test}/Conversion/ConvertToLVX`; the rest of the tree is
unmodified upstream LLVM/MLIR. Design/validation docs are in `lvx-mlir/docs/` (deliberately *outside* the
submodule: they document the LVX project, not the LLVM fork, and keeping them
out keeps the fork's diff against upstream to code).

### Ground truth for the LVX ISA (outside this repo)

`../lvx-mds/lvx-refs/` is the **authoritative** machine-description
database for the LVX ISA. Treat everything else as derived from it. (The directory is
`lvx-refs`, **not** `refs` — it was split out of `lvx-mds/lvx-family/` at some point, and
older docs/Makefiles in this tree may still say `lvx-mds/refs/`.) We target the `lvx_v1`
core only; the files that matter here are:

| File (under `lvx-mds/lvx-refs/`) | What it is |
|---|---|
| `FE/YAML/lvx/lvx_v1/Opcode.txt` | Per-instruction bit-field encoding diagrams, grouped by format, with the bundling class in the trailing column. |
| `FE/YAML/lvx/lvx_v1/Description.yml` | The full YAML machine description — formats, operands, modifiers, immediates, registers, conventions. |
| `MDD/lvx/lvx_v1/Opcode.table` | The extracted per-opcode records: `Opcode-lvx_v1-<MNEMONIC>_<operands>_<decoding>` ID, `mnemonic`, `encoded` mask, `format`, `patterns`, `properties`. This is the ID namespace the reference assembly below annotates with. |
| `BE/GBU/lvx/lvx_v1/LVX_OPCODE_FLAG_MODE64.s` | **The reference assembler source for every instruction** — MDS-generated, exercising (close to) every opcode/format, each line carrying its `Opcode-lvx_v1-…` ID in a trailing comment. This is the authority on how an instruction is *spelled* in assembly: operand order, modifier syntax, register-pair `.lo`/`.hi`/`.x`/`.y` suffixes, immediate forms. Grep it before hand-writing any LVX assembly or adding an emitter case. (`LVX_OPCODE_FLAG_MODE64.bin` beside it is the assembled counterpart.) |
| `MDD/lvx/lvx_v1/Convention.table` | **The ABI.** `Convention-lvx_v1-regular` is what `lvx_func` and the register allocator implement: `argument` = `$r0-$r11` (12), `result` = `$r0-$r3` (4), `return` = `$ra`, `stack` = `$r12`, `local` = `$r13`, `frame` = `$r14`, `struct` = `$r15`, `veneer` = `$r16-$r17`, `reserved` = `$r12`/`$r13`, plus the `caller`/`callee` save sets. |

Every `MDD/lvx/lvx_v1/*.table` has a merged family-level twin at `MDD/lvx/*.table` with the
same content but IDs spelled `-lvx-` instead of `-lvx_v1-` (e.g. `Convention-lvx-regular`).
Either works for reading ISA facts; prefer the `lvx_v1/` one so the core is unambiguous.

Other ground-truth pointers:

- **ISS**: `../lvx-gem5/build/gem5-lvx1.opt` is the `lvx_v1` gem5 simulator — the executable used for end-to-end validation of emitted assembly (see `lvx-mlir/docs/EndToEndValidation.md`). `gem5-lvx2.opt` beside it is the `lvx_v2` core, a cross-check only; the old single `build/LVX/gem5.opt` path no longer exists.
- **`lvx-target/bootstrap/` is gone — deleted 2026-07-31, and nothing should be resurrected from it.** It held a pruned LVX-subset view of the ISA (`lvx_Opcode.txt`, `lvx_Format.yml`, `lvx_formats.txt`, `lvx_Modifier.yml`, `lvx_Convention.yml`, `lvx_Synthetic.yml`, and the two `prune_*.pl` scripts that generated the first two) which existed **only** to bootstrap the initial port of `llvm-project` to LVX. It was never a maintained view of the ISA. The dialect sources still cite those filenames in provenance comments (`ConvertToLVX.cpp`, `RegisterAllocation.cpp`, `LVXOps.td`, …) — **those citations are historical**; the thing to consult now is the corresponding `lvx-mds/lvx-refs/` file in the table above. `../lvx-target/` itself remains, holding only the two `.tex` specs (`lvx_ApplicationBinaryInterface.tex`, `lvx_VLIWInstructionBundling.tex`).
- If the dialect needs ISA data it doesn't already have (e.g. `Scheduling`/`Resource`/`Bundle` tables for a future software-pipelining pass, or `RegFile`/`RegClass` tables for SIMD register pairs/quads), take it from `lvx-mds/lvx-refs/**/lvx_v1/` directly — never hand-derived from some other source, and don't reintroduce a pruning/extraction layer.
- `../lvx-llvm/llvm-project/llvm/lib/Target/LVX/` is a **separate, independent** SelectionDAG LLVM backend for LVX (own git repo, branch `lvx-llvm`, now a sibling directory under `lvx-csw/`). It's a useful cross-reference for mnemonic spelling and register layout but is **not** the source of truth — it was hand-written in parallel and may drift from the ground truth above.

## Build

Configure once, **from `llvm-project/`** (this checkout only needs the `mlir` project; `LLVM_TARGETS_TO_BUILD=X86` is just a placeholder native target, unrelated to the LVX work):

```
cmake -G Ninja -S llvm -B build \
  -DCMAKE_BUILD_TYPE=Debug \
  -DLLVM_ENABLE_PROJECTS=mlir \
  -DLLVM_ENABLE_ASSERTIONS=ON \
  -DLLVM_CCACHE_BUILD=ON \
  -DLLVM_TARGETS_TO_BUILD=X86 \
  -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
```

Build `mlir-opt` (the primary tool for exercising these dialects):

```
ninja -C build mlir-opt
```

Building `mlir-opt` from scratch links against essentially all of MLIR's dialects/conversions (it's the umbrella tool), so a from-scratch build is slow even with ccache; incremental rebuilds after touching only `LVX*`/`ConvertToLVX` files are fast (compile + relink only).

**Known environment quirk**: in this sandbox, the linker occasionally produces `build/bin/mlir-opt` without the executable bit (`-rw-rw-r--` instead of `-rwxrwxr-x`), and lit reports this as a generic "Permission denied" / exit 127 on every test. If that happens, `chmod +x build/bin/mlir-opt` and rerun — it is not a code problem. Also watch for a transient "Text file busy" if you invoke the binary while ninja's final link step is still writing it.

## Testing

Also from `llvm-project/`:

```
export PATH=$PWD/build/bin:$PATH
ninja -C build FileCheck count not          # one-time: lit's FileCheck dependencies
build/bin/llvm-lit mlir/test/Dialect/LVX mlir/test/Dialect/LVXCF mlir/test/Dialect/LVXSCF mlir/test/Dialect/LVXFunc mlir/test/Conversion/ConvertToLVX
```

Run a single test directly (faster iteration when debugging one file):

```
build/bin/mlir-opt mlir/test/Dialect/LVX/ops.mlir | build/bin/mlir-opt | build/bin/FileCheck mlir/test/Dialect/LVX/ops.mlir
build/bin/mlir-opt mlir/test/Conversion/ConvertToLVX/arith.mlir -convert-to-lvx | build/bin/FileCheck mlir/test/Conversion/ConvertToLVX/arith.mlir
```

Or drop `| FileCheck ...` to just eyeball the printed IR.

## Architecture

### Dialect family (mirrors the paper's `rv`/`rv_cf`/`rv_scf`/`rv_func` split)

- **`lvx`** (`mlir::lvx`, `mlir/{include,lib}/mlir/Dialect/LVX/IR/`) — the core ISA dialect. Op mnemonics match real LVX instructions verbatim in lowercase (`lvx.addd`/`lvx.addw`, `lvx.faddd`, `lvx.compd`/`lvx.fcompd`, `lvx.cmoved`, `lvx.ld`/`lvx.sd`/`lvx.lbz`/etc., `lvx.sxbd`/`lvx.zxwd`/etc., the synthetic/alias opcodes in `lvx-refs`' `MDD/lvx/lvx_v1/Synthetic.table`). Every live value has type `!lvx.reg` — unparameterized when unallocated, or `!lvx.reg<r5>` once pinned to a physical register. There is a single register type because LVX has one unified GPR file for scalar int/float (no separate FPR); instruction *width* (32- vs 64-bit) is encoded in the mnemonic, not the type. `lvx.li` (immediate) and `lvx.mv` (register copy, used for ABI bridging) are synthetic pseudo-ops, not single real opcodes.
- **`lvx_cf`** (`mlir::lvx_cf`) — unstructured control flow (`lvx_cf.br`/`lvx_cf.cond_br`), backed by `BCU_UB`/`BCU_CB`. `cond_br` takes a `!lvx.reg` operand tested against an `LVX_BcuCondAttr` (e.g. `wnez`), not a separate `i1`.
- **`lvx_scf`** (`mlir::lvx_scf`) — a single structured `for` op mirroring `scf.for`. Kept intact (not lowered to `lvx_cf` branches) so a future register-allocation and software-pipelining pass has loop structure to consume, per the paper's rationale.
- **`lvx_func`** (`mlir::lvx_func`) — ABI-constrained `func`/`call`/`return`. A function's entry-block argument/result types are *pinned* physical registers (`!lvx.reg<r0>`, ... up to the ABI's 12 args / 4 results); the body copies each into a fresh virtual register via `lvx.mv` before running on virtual registers (mirrors the paper's `rv.mv` copy-in pattern). Enforced by `LVXFuncFuncOp`/`LVXFuncCallOp` verifiers checking against the convention's register counts.

**Type-system invariant to preserve**: operands and results of arithmetic/memory ops are *not* constrained to share the same `!lvx.reg` type (no `SameOperandsAndResultType`/`AllTypesMatch`). Before allocation everything is the same unpinned `!lvx.reg`, so this is trivially satisfied, but after a future allocation pass assigns *different* physical registers to different operands/results (the normal case, e.g. `addd $r5, $r1, $r2`), such a constraint would make the IR unverifiable. Assembly formats print operand/result types independently (`functional-type(...)` or explicit `(type, type) -> type`) for exactly this reason — don't add same-type traits when adding new ops.

### Lowering pass

`mlir/lib/Conversion/ConvertToLVX/ConvertToLVX.cpp` implements the `convert-to-lvx` pass (`applyFullConversion`), lowering `arith`/`cf`/`scf`/`memref`/`func`/`index.constant` into the dialects above via an `LVXTypeConverter` (scalars and memrefs both map to `!lvx.reg`). Notable non-obvious pieces:
- Width dispatch (`i32`→`w` mnemonic, `i64`/`index`→`d` mnemonic) is done by inspecting the *original* op's operand/result types at match time (before conversion), not the adaptor's converted values.
- `arith.{div,rem}{s,u}i` both lower to the same fused `lvx.divmod{d,w}{,u}` (real hardware has no separate divide/remainder instruction) and pick the quotient or remainder result; this duplicates the divmod computation when a kernel needs both from the same operands.
- Memref load/store address linearization only supports statically-shaped memrefs with an identity/strided layout (`memref.getStridesAndOffset`); dynamic shapes are unsupported for now.
- Function conversion (`FuncFuncToLVX`) must convert *every* block's argument types in the original region, not just the entry block — `scf`/`cf` targets reachable only via branches need it too. This goes through `rewriter.convertRegionTypes(&op.getBody(), *getTypeConverter())` before moving/rewriting the region; doing it by hand (block-arg replacement without registering the remapping with the conversion framework) silently produces stray `unrealized_conversion_cast`s that fail to legalize.
- `arith.select`/`arith.trunci` have upstream algebraic folders (e.g. `select(cmpi eq a,b, a, b) -> b`, `trunc(ext(x, w), w) -> x`) that can eliminate an op *before* any conversion pattern ever sees it if you construct test IR carelessly (operands identical to the comparison's, or a truncate that exactly undoes a prior extend). Keep this in mind when writing new lit tests for arithmetic/cast lowering.

### Adding a new dialect or extending an existing one

See the `add-lvx-dialect` skill for the 5 required build-registration points a new `LVX*` dialect or conversion library needs beyond its `.td`/`.cpp` sources.

### Current phase / what's not built yet

Dialect scaffolding, register allocation, and real assembly emission are built and verified end to end — real kernels compiled through the whole pipeline, assembled/linked with the real `lvx-mbr-as`/`lvx-mbr-ld`, and executed on real `lvx-gem5`. Register allocation is a 3-step linear scan (`lvx-mlir/docs/RegisterAllocation.md`; Step 1 live intervals, Step 2 assignment-only with a hard error on pressure, Step 3 the same scan plus real spilling), with explicit coalescing for loop-carried `iter_args`, branch arguments, and tied-operand instructions (e.g. `ffma`/`ffms`, whose accumulator operand shares a register with its own result on real hardware). Hardware loops (`LOOPDO`) and a handful of real-hardware-only instruction quirks (`divmod`'s register-pair destination, `$ra` save/restore, call-site ABI register pinning) are also done — see `lvx-mlir/docs/HardwareLoops.md`, `lvx-mlir/docs/AssemblyEmission.md`, and `lvx-mlir/docs/EndToEndValidation.md` for the full design and validation history.

Still not built: software pipelining, and SIMD (`!lvx.pair`/`!lvx.quad` for 128-/256-bit values, lane/blend/guard ops) — both later phases per the original plan, needing `Scheduling`/`Resource`/`Bundle` and `RegFile`/`RegClass` (`PGR`/`QGR`) data respectively, read straight from `lvx-mds/lvx-refs/MDD/lvx/lvx_v1/`.
