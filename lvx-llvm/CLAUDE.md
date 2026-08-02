# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`lvx-llvm/` holds `llvm-project`, a fork of upstream LLVM carrying the **LVX** back end at `llvm-project/llvm/lib/Target/LVX/`. Same shape as `lvx-gcc/`: a plain directory in `lvx-csw` holding a submodule that is a genuine fork.

Build directory: `llvm-project/build/` (Ninja, `CMAKE_BUILD_TYPE=Debug`, `LLVM_TARGETS_TO_BUILD=X86;LVX`). `ninja llc` from there is the usual edit-test loop; `EXPORT_PATH` puts `build/bin` on `PATH`.

The target is LP64, little-endian, triple `lvx-mbr` — see `lvx-csw/CLAUDE.md` for the ISA overview and `lvx-mds/CLAUDE.md` for the machine description that most of this back end is generated from.

## Most of the target description is GENERATED — do not hand-edit it

Four files under `llvm/lib/Target/LVX/` come from **`MDS/BE/LLVM`** in the sibling `lvx-mds` repo and are overwritten by the next install:

| File | Contents |
|---|---|
| `LVXInstrEncodings.td` | Every instruction format class and every instruction def, with complete `Inst` bit assignments |
| `LVXInstrFormats.td` | Every operand type: the modifier operands and the immediate operands (`simm10`, `wimm32`, `brtarget17s2`, …) with their `ImmLeaf` predicates |
| `LVXModifiers.h` | The assembly-suffix tables, plus the `LVX_FOR_EACH_MODIFIER` X-macro `LVXInstPrinter` expands into one print method per modifier |
| `LVXImmediateExtensions.inc` | The widened-immediate chains (`LVX_IMMEDIATE_FORM` rows) and the widened-branch pairs (`LVX_BRANCH_FORM` rows) |

To change any of them, change the ISA description in `lvx-mds/lvx-family/FE/YAML/lvx/*.yml` or the generator in `lvx-mds/MDS/BE/LLVM/BIN/`, then from `lvx-csw/`:

```sh
make all                                            # rebuild lvx-mds
make -C lvx-mds/build_lvx/BE/LLVM install LLVM_CORE=lvx_v1
cd lvx-llvm/llvm-project/build && ninja llc
```

`make config` already points `--with-llvm-prefix` at this checkout. `LLVM_CORE` selects which variant's description is installed (`lvx_v1` or `lvx_v2`); `lib/Target/LVX` holds one at a time.

The hand-written half is `LVXInstrInfo.td`: SelectionDAG nodes, the call-frame pseudos, the processor model, the `COPYD` synthetic, and **all** instruction-selection patterns. Generated defs carry no patterns, so a new pattern is a standalone `def : Pat<…>` there. Instruction *flags* (`isCall`, `isReturn`, `isBranch`, implicit `$ra`) cannot be added there — TableGen cannot set a field on an existing def — and live in `lvx-mds/lvx-family/BE/LLVM/instr-flags`, keyed by generated def name.

## Instruction naming

Generated defs are `<INSTRUCTION>_<format with its execution unit stripped>`:

```
ADDD_DWRR0     addd $rW = $rZ, $rY      ALU_DWRR0,   32 bits
ADDD_DWRI      addd $rW = $rZ, imm10    ALU_DWRI,    32 bits
ADDD_DWRI_X    addd $rW = $rZ, imm37    ALU_DWRI.X,  64 bits
ADDD_DWRI_Y    addd $rW = $rZ, imm64    ALU_DWRI.Y,  96 bits
ADDD_DWRR0_M   addd $rW = $rZ, imm32    ALU_DWRR0.M, 64 bits, plus the ".@" splat
```

The format is part of the name because the format is what distinguishes them: one mnemonic has up to five encodings, and the assembler picks between them by immediate magnitude, not by spelling.

## Immediate extensions

LVX widens an immediate by spending extra 32-bit syllables on it. That is why a large constant or a large frame offset does **not** need a scratch register here:

- **Selection**: `LVXInstrInfo.td`'s `BinOpImm` multiclass lists the 10-, 37- and 64-bit forms of each ALU operation narrowest-first, so LLVM picks the shortest encoding whose `ImmLeaf` accepts the constant.
- **Frame code**: `LVXFrameLowering`'s `emitAddImm`/`frameAccessOpcode` and `LVXRegisterInfo::eliminateFrameIndex` call `LVXInstrInfo::getFormForImmediate(NarrowOpc, Imm)`, which walks the generated chains and returns the narrowest encoding that holds `Imm`. An out-of-range frame access is fixed by `MI.setDesc()` to a longer encoding of the *same* instruction, in place — not by scavenging a register and emitting `maked` + `addd` ahead of it.

- **Load/store displacements**: `selectAddr` accepts any displacement for a genuine register base and `selectLoadStoreOpcode` picks the encoding, so `p[100000]` is one `ld` rather than an `addd` plus a narrow one. A FrameIndex deliberately keeps the narrow form — its real displacement is not known until PEI, which widens it then.

`getFormForImmediate` returns 0 when no encoding of the instruction can hold the value — including when it has no widened forms at all — so a caller can use the result as "this instruction can take it directly" with no separate range check. It accepts any form of an instruction, not just the narrow one, so a caller re-deciding a width need not know which form it is looking at.

## Branches

Conditional branches are selected directly in `LVXISelDAGToDAG`, not routed through SETCC, because LVX branches on the comparison itself:

```
cb.<bcucond>  $rZ ? T        one register against zero,  17-bit word offset
ccb.<ccbcomp> $rZ, $rY ? T   two registers,              11-bit word offset
```

Both compare in printed order (`ccb.dlt $rZ, $rY` branches when `rZ < rY`), confirmed against the machine description's helper semantics. `ccbcomp`'s 64-bit half has no `le`/`gt`, so those relations swap the operands. A comparison against zero also absorbs DAGCombine's canonicalisation — `x > 0` arrives as `x < 1`, `x < 0` as `x > -1` — which keeps the two most common sign tests on `cb` instead of materializing a constant for a `ccb`.

`reverseBranchCondition` is a single XOR: both `bcucond` and `ccbcomp` pair every relation with its negation in adjacent codes, all the way through the word-width variants.

**Relaxation** (`LVXBranchRelaxation.cpp`) widens a branch whose target is out of reach to the long form of the same branch — `ccb`→`ccbx`, `cb`→`cbx`, `goto`→`gotox`, `call`→`callx` — a substitution in place, not the block splitting the generic `BranchRelaxation` pass does on targets without long branches. It runs in `addPreEmitPass`, after the frame code has settled every instruction's width, and iterates to a fixed point since widening one branch can push another out of range. The pairs come from the generated `LVX_BRANCH_FORM` rows.

## Calling-convention promotion

The convention promotes every integer narrower than a slot to i64, so a value's type on the wire is not the type the IR gave it. `extendToSlot`/`truncateFromSlot` in `LVXISelLowering.cpp` move values into and out of their slots, honouring the `signext`/`zeroext` flags. `extendToSlot` takes the location type from the `CCValAssign` rather than assuming i64 — an i128 return goes in a `GPR128` pair, where the location is already i128 and nothing needs doing.

## Operand order follows the assembly syntax

The generated formats order operands the way the machine description writes them, which is the way the assembler prints them — **not** the order the earlier hand-written description used. This matters at every `BuildMI` and `getMachineNode` call site:

```
SD_SSBO   (outs),           (ins simm10:$off, GPR:$rZ, GPR:$rT)      sd off[$rZ] = $rT
LD_LSBO   (outs GPR:$rW),   (ins simm10:$off, GPR:$rZ, variant:$var) ld $rW = off[$rZ]
ADDD_DWRI (outs GPR:$rW),   (ins GPR:$rZ, simm10:$imm)               addd $rW = $rZ, imm
CATDQ     (outs GPR128:$rM),(ins GPR:$rZ, GPR:$rY)                   catdq $rM = $rZ, $rY
```

The offset always immediately precedes the base register, which is what `eliminateFrameIndex` relies on to find the offset operand (`FIOperandNum - 1`).

The conditional moves are the other place this matters: because their write is
conditional, `CMOVED`'s destination is a tied read-modify-write operand, which
is what makes `select` selectable at all.

**`catdq`'s first source is the pair's LOW half** (`result = ZX64(argument2) | (argument3 << 64)`, confirmed against `opcodes/lvx-opc.c`). The hand-written description this replaced had the two sources in the opposite order while giving them the same encoding fields, so it built every 128-bit pair with its halves swapped; generating the format fixed it. Likewise `sbmm8d`/`sbmmt8d`/`sbmm8eord`/`sbmmt8eord` used to be given `ALU_DWRR0`'s subop field (`000`) instead of `ALU_DBMWRR`'s (`001`), which encoded them identically to `andnd`/`iornd`/`eord`/`neord`.

## Verifying an encoding

`lvx-binutils/opcodes/lvx-opc.c` is the cross-check: it is generated from the same MDD `encoded` strings, so agreement does not re-verify the ISA, but it does catch a misread of bit numbering or syllable order. The one deliberate difference is the final syllable's parallel bit, forced to 0 here (no bundling yet) and left free there.

There is no `MCCodeEmitter` or disassembler yet, so `EncoderMethod`/`DecoderMethod` on the operand types are inert strings and `Inst` is not exercised by any test — check it by reading, or against `lvx-opc.c`.

## Tests

`llvm/test/CodeGen/LVX/` holds the lit tests; run them with `build/bin/llvm-lit llvm/test/CodeGen/LVX`. The build tree is minimal, so lit needs `ninja llvm-config count not FileCheck llc` first.

`branch-relaxation.mir` gets its distance from a block *alignment* rather than thousands of instructions — an aligned block starts further along, which is exactly what the range check sees, and it keeps the test a page instead of a megabyte.

The loose `test_*.ll` at the root of `llvm-project/` are ad-hoc scratch files from the bring-up, not a suite.
