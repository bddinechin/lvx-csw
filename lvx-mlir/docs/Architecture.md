# Architecture: MLIR to LVX machine code

How ordinary MLIR becomes real LVX assembly, what the dialects are, and where
each piece lives. Companion documents cover individual subsystems in depth —
see [README.md](README.md) for the index.

## The idea

The conventional MLIR path to machine code lowers everything to the `llvm`
dialect and hands off to LLVM's backend. This project does not. It follows
*"A Multi-level Compiler Backend for Accelerated Micro-kernels Targeting
RISC-V ISA Extensions"* (CGO'25): a low-level dialect whose **operations are
real assembly instructions**, and — once registers are assigned — physical
registers represented in **MLIR's type system** rather than as attributes.

The payoff is that register allocation and (later) software pipelining run on
IR that still has loop structure and MLIR's verification, instead of on a
lower-level representation that has thrown both away.

Note this is a *sibling* to, not a replacement for, `lvx-llvm` — the
independent SelectionDAG backend for the same architecture, in its own
repository. Neither generates the other.

## The dialect family

Four dialects, mirroring the paper's `rv`/`rv_cf`/`rv_scf`/`rv_func` split.
The per-operation reference is generated (`ninja -C llvm-project/build
mlir-doc`); this is the shape and the rationale.

### `lvx` — the ISA dialect (79 ops)

Operation mnemonics match real LVX instructions verbatim, in lowercase:
`lvx.addd`/`lvx.addw`, `lvx.faddd`/`lvx.faddw`, `lvx.compd`, `lvx.ld`/`lvx.sd`,
`lvx.sxbd`, and so on. Width is in the mnemonic (`d` = 64-bit, `w` = 32-bit),
not in the type.

Every live value has type **`!lvx.reg`** — unparameterized before allocation,
`!lvx.reg<r5>` after. One register type, because LVX has one unified GPR file
for both scalar integer and floating-point values; there is no separate FPR.

A handful of ops are synthetic pseudo-instructions rather than single real
opcodes, each emitting either a real instruction sequence or nothing at all:

| Pseudo | Emits | Purpose |
|---|---|---|
| `lvx.li` | `maked` (+ refinement for wide values) | materialize a constant |
| `lvx.mv` | `copyd` | register copy, ABI bridging |
| `lvx.sp` | *nothing* | name `$r12` as an SSA value |
| `lvx.reg_live_in` | *nothing* | name a callee-saved register's incoming value so `lvx.sd` can store it |
| `lvx.getra`/`lvx.setra` | `get`/`set` | snapshot and restore `$ra` |

### `lvx_cf` — unstructured control flow (8 ops)

`lvx_cf.br`, `lvx_cf.cond_br`, `lvx_cf.loopdo`, backed by the real `BCU_UB`
and `BCU_CB` formats. `cond_br` tests an `!lvx.reg` against an
`LVX_BcuCondAttr` (e.g. `wnez`) — there is no separate `i1`, because the
hardware has no flag register to model one with.

### `lvx_scf` — structured loops (7 ops)

A single `lvx_scf.for` mirroring `scf.for`. Deliberately **not** lowered to
branches early: the register allocator needs the loop structure to coalesce
loop-carried values, and a future software pipeliner will need it too. It is
lowered only after allocation, by `-lvx-scf-to-cf`.

### `lvx_func` — ABI-constrained functions (8 ops)

`lvx_func.func`, `lvx_func.call`, `lvx_func.return`. Entry-block argument and
result types are *pinned* physical registers (`!lvx.reg<r0>`, …), and the body
copies each into a fresh virtual register with `lvx.mv` before doing any work
— the paper's copy-in pattern. Verifiers enforce the counts from
`Convention-lvx_v1-regular`: **12 argument registers** (`$r0-$r11`), **4
result registers** (`$r0-$r3`).

## The pipeline

```
  .mlir  (linalg / arith / scf / cf / memref / func)
    |
    |  upstream passes, e.g. -convert-linalg-to-loops
    v
  arith / scf / cf / memref / func / index
    |
    |  -convert-to-lvx                     (applyFullConversion)
    v
  lvx / lvx_cf / lvx_scf / lvx_func        — virtual registers
    |
    |  -lvx-allocate-registers             linear scan; assigns !lvx.reg<rN>,
    |                                      spills, builds the frame, saves
    |                                      callee-saved registers and $ra
    v
  same dialects                            — physical registers
    |
    |  -lvx-rewrite-divmod                 pin divmod's result pair
    |  -lvx-scf-to-cf                      lvx_scf.for -> branches or LOOPDO
    |  -lvx-emit-asm                       print real assembly text
    v
  .s -> lvx-mbr-as -> lvx-mbr-ld -> ELF -> lvx-gem5
```

Concretely, for a `linalg.generic` matmul (`../examples/mymma.mlir`):

```
mlir-opt mymma.mlir -convert-linalg-to-loops \
  | mlir-opt -convert-to-lvx \
  | mlir-opt --pass-pipeline='builtin.module(any(lvx-allocate-registers),
      any(lvx-rewrite-divmod),any(lvx-scf-to-cf),lvx-emit-asm)'
```

`../examples/build-mymma.sh` runs exactly this, then assembles, links against
a C harness built with `lvx-mbr-gcc`, and checks the gem5 result against an
x86 oracle.

### Pass ordering is load-bearing

Three ordering constraints are correctness requirements, not preferences:

- **`-lvx-scf-to-cf` runs *after* allocation.** The allocator needs
  `lvx_scf.for` intact to coalesce loop-carried `iter_args` into a single
  register. The two values this pass then introduces (loop-test compare,
  induction increment) are pinned to the reserved scratch pool rather than
  going through any allocation decision.
- **`-lvx-rewrite-divmod` runs after allocation** for the same reason: real
  `divmodd` writes an aligned register *pair* (`registerM`), which the
  allocator's flat single-register model cannot express.
- **`-lvx-emit-asm` runs last** and hard-errors on any value that still has an
  unallocated `!lvx.reg`.

## Two invariants worth knowing before editing

**Do not add same-type traits to arithmetic ops.** Operands and results are
deliberately *not* constrained to share a type (`SameOperandsAndResultType`,
`AllTypesMatch`). Before allocation everything is the same unpinned
`!lvx.reg`, so such a constraint looks harmless — but after allocation
`addd $r5 = $r1, $r2` has three *different* types, and the IR would stop
verifying. Assembly formats print operand and result types independently for
exactly this reason.

**The reserved scratch registers must stay caller-saved.** They are held out
of the allocation pool for post-allocation passes to pin values to
(`ScratchRegisters.h`). A callee-saved choice silently clobbers the caller's
value with no matching save — which is precisely the bug that made every
spilling function ABI-illegal until the pool moved off `R29-R31`. One of them
must also be part of an even/odd aligned pair, for `divmod`.

## Source layout

Paths relative to `llvm-project/`. Everything else in that tree is unmodified
upstream LLVM/MLIR.

| Path | Contents |
|---|---|
| `mlir/include/mlir/Dialect/LVX{,CF,SCF,Func}/IR/` | `.td` definitions: dialect, types, ops |
| `mlir/lib/Dialect/LVX{,CF,SCF,Func}/IR/` | dialect + op implementations, verifiers |
| `mlir/lib/Dialect/LVX/Analysis/LiveIntervals.cpp` | live-interval computation (Step 1) |
| `mlir/lib/Dialect/LVX/Transforms/RegisterAllocation.cpp` | linear scan, spilling, prologue/epilogue |
| `mlir/lib/Dialect/LVX/Transforms/RewriteDivmod.cpp` | divmod result-pair pinning |
| `mlir/lib/Dialect/LVX/Transforms/SCFToCF.cpp` | loop lowering, incl. `LOOPDO` |
| `mlir/lib/Dialect/LVX/Transforms/EmitAsm.cpp` | assembly text emission |
| `mlir/include/mlir/Dialect/LVX/Transforms/ScratchRegisters.h` | the reserved scratch pool, shared by the three post-allocation passes |
| `mlir/lib/Conversion/ConvertToLVX/ConvertToLVX.cpp` | `-convert-to-lvx` |
| `mlir/test/Dialect/LVX*`, `mlir/test/Conversion/ConvertToLVX` | lit tests |

Adding a new `LVX*` dialect or conversion library needs five build-registration
points beyond the sources — see the `add-lvx-dialect` skill.

## What is not built

- **Software pipelining.** The reason `lvx_scf.for` survives allocation.
  Needs the `Scheduling`/`Resource`/`Bundle` tables from `lvx-mds/lvx-refs`.
- **SIMD.** `!lvx.pair`/`!lvx.quad` for 128-/256-bit values, lane and blend
  ops. Needs `RegFile`/`RegClass` (`PGR`/`QGR`) data, and an allocator that
  handles overlapping register classes — see
  [MultiRegisterClasses.md](MultiRegisterClasses.md).
- **General `lvx_cf` block-argument merges.** Branch operands must already be
  pinned to the same register as the destination block argument; there is no
  representation for the register move a real phi-merge would need at that
  stage. Everything `-lvx-scf-to-cf` generates satisfies this by construction.
- **Dynamically-shaped memrefs.** Address linearization handles static shapes
  with an identity or strided layout only.
