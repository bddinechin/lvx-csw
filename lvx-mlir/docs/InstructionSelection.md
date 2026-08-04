# Instruction selection: peepholing the naive lowering

Status: **prototyped and measured** (2026-08-04). `-lvx-combine` exists and
folds the `addx` family; base+index addressing does not. Original status:
design, not implemented. `-convert-to-lvx` today is a faithful but
naive one-instruction-at-a-time translation, and two whole families of LVX
instruction are consequently unreachable from any input. This records why,
what MLIR offers to fix it, and what the fix would cost.

**Measured results** (`mymma` at 8x16x8, cumulative):

| pipeline | bundles | `addx` | `muld` |
|---|---|---|---|
| raw lowering | 54 | 0 | 8 |
| `-cse` | 43 | 0 | 5 |
| `-lvx-combine` | 37 | 8 | 0 |
| `-lvx-combine -cse` | **35** | 6 | 0 |

Every multiply is folded, and the predicted inner-loop shape is what comes
out:

```
	addx32d $r15 = $r7, $r1      ; C + (i << 5)
	addx4d  $r16 = $r8, $r15     ;   + (j << 2)
	lwz     $r15 = 0[$r16]
```

Verified on real gem5 against the x86 oracle: identical result, so the fold
is not merely smaller but correct. Hardware-loop formation survives --
`LOOPDO` still appears, which was the open risk.

Two deviations from what this document originally proposed, both noted where
they matter: the patterns are hand-written C++ rather than DRR, and the
`w`-width forms exist but are unexercised by this kernel.

## The gap

`examples/mymma.mlir` is a plain `linalg.generic` matmul over
`memref<...xf32>`. Its innermost loop, after `-convert-to-lvx` and `-cse`,
computes one address like this:

```
	maked $r15 = 4
	muld  $r17 = $r8, $r15
	addd  $r16 = $r15, $r17
	lwz   $r15 = 0[$r16]
```

Four instructions to load `A[i][k]`, of which three are address arithmetic.
Across a 2-D access with a row stride the cost doubles, because each
dimension is materialized independently: a constant into a register, a
multiply, an add.

Two things the hardware provides are never used:

| Available | Used today |
|---|---|
| `addx{2,4,8,16,32,64}{d,w}` | no |
| `ld.<variant> $rW = $rY[$rZ]` (base + index) | no -- always `0[$rbase]` |
| `sd $rT[$rZ] = $rY` | no |

## What the instructions actually do

From `lvx-mds/lvx-refs`, not inferred:

**`addx<N>{d,w}`** -- `Description.yml`, ADDX2D: *"The %2 is shifted left by
one bit and added to the %3"*, `new result1 = argument3 + (argument2 << 1)`.
So `addx2d $rW = $rZ, $rY` is `rY + (rZ << 1)`, and the family covers shifts
of 1 through 6 (scales 2, 4, 8, 16, 32, 64). That is exactly a
`multiply-by-power-of-two-and-add`, which is what every affine array index
is.

**Base + index addressing** -- format `LSU_LSBI`, *"LSU Load Scalar Base +
Index"*, spelled `lwz.s $r33 = $r32[$r34]`. Its address computation is:

```
new base    = %3;                              ; registerZ, in brackets
new index   = %2;                              ; registerY
new scaling = doscale ? %0.MemorySize : 1;
new address = base + (index * scaling);
```

**`doscale` is dead, ISA-wide.** It is written `0` in all eleven execution
blocks that mention it, so `scaling` is unconditionally 1 and the
`index * scaling` multiply never happens. It is not in `LSU_LSBI`'s
`operands:` list either, so it has no assembly spelling: today it is an
encoding bit in eight LSU formats with no operand, no syntax and no effect
-- a KVX leftover. It is a candidate for removal (it would otherwise cost
load latency in hardware), and removing it changes no instruction's
behaviour, because nothing can set it.

Either way the consequence for us is the same: **base+index does not fold
the element-size multiply**, it only saves the final add. So it is worth
less than it first appears, and `addx` is the bigger win of the two --
`addx` subsumes most of what a scaled base+index would have bought:

```
; A[i][k], row stride 64, element size 4:  addr = A + i*64 + k*4
	addx64d $r16 = $r7, $r1      ; A + (i << 6)
	addx4d  $r16 = $r9, $r16     ; + (k << 2)
	lwz     $r15 = 0[$r16]
```

Three instructions where the current lowering emits seven.

## Why the current pass cannot do this

`ConvertToLVX.cpp` uses the **dialect conversion** framework
(`applyFullConversion`). That is a *legalization* driver: it visits each
illegal operation once and asks a pattern what to replace it with. It is the
right tool for the job it does -- translating whole dialects with a type
converter, which is genuinely hard to do by hand -- but it structurally
cannot peephole:

- **Patterns see one source op.** `MemRefLoadToLVX` matches a
  `memref.load` and emits the whole address sequence itself. There is no
  point at which a pattern sees `addd(muld(x, 4), b)` as an existing
  `lvx` expression, because the conversion creates it and then finishes.
- **No re-examination.** Conversion does not revisit an operation after its
  operands change. Peepholing is inherently a fixed-point process: folding
  one `muld` into an `addx` exposes the next one.
- **Correctness and quality are entangled.** Adding selection smarts to the
  legalizer means every future optimization risks the thing that must never
  break -- that the output is *legal*.

## What MLIR provides

Three mechanisms, and the distinction between them is the useful part:

**DRR** (Declarative Rewrite Rules) -- source-to-target patterns written in
TableGen, generated into C++ `RewritePattern`s. Closest analogue to LLVM's
`.td` `Pat<>`, which is what the sibling `lvx-llvm` backend uses:

```tablegen
def : Pat<(LVX_AdddOp (LVX_MuldOp $x, (LVX_LiOp ConstantAttr<4>)), $b),
          (LVX_Addx4dOp $x, $b)>;
```

Good fit for this problem: the patterns are small, local, and mostly
one-to-one.

**PDL / PDLL** -- the newer rewrite-pattern IR, compiled to a bytecode
matcher and interpretable at runtime. More capable than DRR (multi-result
matching, native constraints and rewrites, dynamic loading) at the cost of
more machinery. Worth it if selection ever needs to be table-driven from
`lvx-mds` output rather than hand-written; not worth it for a first pass.

**The greedy pattern rewrite driver** (`applyPatternsGreedily`) -- the
fixed-point loop that runs either of the above until nothing changes,
re-examining operations whose operands were rewritten. **This is the missing
piece**, more than the pattern language is: it is what makes chained folds
work.

## Proposal

Add a distinct pass, `-lvx-combine`, that runs the greedy driver over DRR
patterns on the `lvx` dialect. Keep `-convert-to-lvx` naive and
always-correct.

The contract is what makes this worth doing: `-lvx-combine` only ever
rewrites `lvx` to `lvx`, so it cannot produce illegal IR, and it is
optional -- if it is buggy or disabled the pipeline still works, just
slower. Correctness lives in the legalizer; quality lives here.

Pipeline position, all three constraints load-bearing:

```
  -convert-to-lvx        must precede it: the patterns match lvx ops
  -lvx-combine           <-- new
  -cse                   must follow: addx folding creates new common
                             subexpressions (and CSE already runs here)
  -lvx-allocate-registers must follow: combining changes what is live
```

### First patterns, in order of value

1. `addd(muld(x, 2^n), b)` -> `addx<2^n>d(x, b)`, and the `w` forms.
   Directly targets the address arithmetic above. Needs `n` in 1..6.
2. `muld(x, 2^n)` -> `slld(x, n)` where no add follows. Strictly better
   than materializing the constant.
3. Constant folding of `li`-fed arithmetic, if `-canonicalize` does not
   already cover it once the ops are `Pure`.

### Base + index addressing is a bigger change

Not a pattern -- a dialect change. `lvx.lwz`/`lvx.sd` today carry an integer
offset *attribute*. A base+index form needs either an optional second
register operand or a distinct op, plus emitter support for the
`$rY[$rZ]` syntax and allocator awareness of the extra operand. Given that
`doscale` is 0 in this format -- so it saves only the final `addd`, not the
scaling multiply -- it should follow the `addx` work rather than precede it,
and be justified by measurement.

## How it would be validated

The same way everything else here has been: `examples/build-mymma.sh` runs
the whole pipeline to a real ELF, executes it on real `lvx-gem5`, and
compares against an x86 oracle. A combine pass that breaks something shows
up as a numeric mismatch, not just a FileCheck diff. Bundle count before and
after is the measure of whether it was worth it -- the baseline to beat is
43 bundles for `mymma` at 8x16x8.

Lit tests should assert the *shape* (an `addx4d` appears, the `muld` does
not), and at least one should assert a non-fold: an `addd(muld(x, 3), b)`
must stay a multiply, since 3 is not a power of two.

## Open questions

- ~~**Does combining perturb hardware-loop formation?**~~ **No** -- `LOOPDO`
  still forms on `mymma` after `-lvx-combine`.
- ~~**Does `-canonicalize` already do some of this?**~~ **Measured: no.**
  On `mymma` at 8x16x8, against a 54-bundle raw lowering: `-cse` alone gives
  43, `-canonicalize` alone gives 53, and `-canonicalize -cse` gives 43 --
  identical to `-cse` by itself. Upstream canonicalization contributes one
  bundle on its own and nothing on top of CSE, and folds none of the address
  arithmetic. The `addx` patterns would not be duplicating it.
- **Where do the patterns come from long-term?** `lvx-mds`' `BE/LLVM`
  backend now generates selection patterns for the sibling LLVM backend from
  each opcode's `Behavior`. If that generator can emit DRR as well as
  TableGen `Pat<>`, the `addx` family is a natural first customer, and the
  two backends stop being able to disagree.
- **Interaction with hardware loops.** `-lvx-scf-to-cf` runs much later, but
  combining could change the induction-variable arithmetic that
  `isHardwareLoopEligible` inspects. Verify `LOOPDO` still forms.
