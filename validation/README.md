# LVX compiler-validation harness (native-x86 differential)

Validates the **compiler + ISS pair** against an oracle independent of the LVX
`Behavior` source of truth: the *same C source* compiled and run natively on x86,
diffed against the LVX ELF run under the gem5 ISS. A divergence means something in
`{compiler, runtime, ISS}` is wrong. See `../ROADMAP.md` for why this is the
near-term keystone and how it serves all three compiler back-ends (GCC, LLVM,
MLIR-to-machine-code) through one shared spine.

## Quick start

```bash
cd validation
make check                 # GCC front-end, -O2, micro-tests
make check FRONTEND=llvm   # the same tests through clang + llc instead
make check OPT=0           # bisect optimizer bugs vs codegen/ISS bugs
make check TESTS='tests/micro/arith.c'
./run-ir.sh                # the LLVM IR tests (no x86 reference; see below)
```

Output is TAP plus a bucketed summary.

## How it works

```
 test.c ─┬─ cc -O? ───────────────────► run native ──┐
         │                                            ├─► compare markers ─► PASS/bucket
         └─ frontends/<fe>.sh → a.out ─► gem5 SE run ─┘
```

- Each test `#include`s `lib/harness.h` and defines `int test_main(void)`.
- The harness reports the result identically on both targets: a framed stdout line
  `__LVXR__ <n>` (primary oracle) and the exit code `n & 0xff` (secondary).
- On LVX there is **no full newlib**; `lib/crt.S` supplies a freestanding `_start`
  plus `write`/`exit` via `scall` (the LVX syscall ABI, #17/#1 — the only two this
  harness needs; the gem5 shim implements a good deal more, see
  `Behavior_syscall` in `lvx-gem5/src/arch/lvx/shim.cc`).
- The LVX run reuses lvx-gem5's own verified config,
  `lvx-gem5/tests/lvx/run_lvx.py`.

## Outcome buckets (why this matters right now)

The LVX GCC port is **unfinished**, and LVX is missing some instructions GCC emits, so
early on most signal is "does it build." The harness therefore separates:

| Bucket | Stage | Likely cause |
|---|---|---|
| `PASS` | — | x86 and LVX results match |
| `MISMATCH` | run | codegen / semantics / ISS bug — the real correctness signal |
| `COMPILE_ICE` | C→asm | GCC internal error (see lvx-newlib CLAUDE.md bug clusters) |
| `COMPILE_FAIL` | C→asm | other GCC frontend/codegen failure |
| `ASSEMBLE_MISSING_INSN` | asm→obj | **the ISA lacks an instruction GCC emitted** (the missing-instruction gap) |
| `ASSEMBLE_FAIL` | asm→obj | other assembler error |
| `LINK_FAIL` | link | unresolved symbol / layout |
| `RUN_CRASH` | gem5 | the ISS itself died on a signal (panic stub / unimplemented opcode = SIGILL) — an ISS coverage gap |
| `RUN_TIMEOUT` / `RUN_NOEXIT` / `RUN_NO_OUTPUT` | gem5 | ISS did not run the program to a clean exit |
| `SKIP` | — | the x86 reference itself failed to build (bad/UB test) |

`ASSEMBLE_MISSING_INSN` in particular is a coverage report on the ISA-vs-compiler
gap: it tells you exactly which instructions GCC needs that LVX does not yet have.

## Current findings

As of 2026-08-04, **everything passes on both front ends**: 12/12 micro-tests
under `FRONTEND=gcc` and under `FRONTEND=llvm`, and 8/8 under `run-ir.sh`. The
snapshot below is kept because the two failures it records were real and their
causes are worth knowing, not because it is current.

```
# 2026-07-31, GCC front-end, -O2 -- SUPERSEDED
ok - branches (=33)   ok - loops (=285)   ok - shifts (=100)     # match native x86
not ok - arith        not ok - calls      # ASSEMBLE_MISSING_INSN
```

**The ISS now runs compiled C** — `branches`/`loops`/`shifts` pass against the
native-x86 oracle. Getting there fixed two gem5 bugs the harness surfaced (both
in `lvx-gem5`, see the `gem5-callret-blocker` memory):

1. **Panic-stub cascade** — `call`/`ret`/branches/`get $ra`/compares called
   Behavior helpers that were `__builtin_trap()` stubs (SIGILL). Implemented
   `srhpc_update`, `bcucond`, `intcomp_32/64`, `get`, and the `*_check_access`
   family in `src/arch/lvx/shim.cc` (+ the `BE/GEM5` manifest).
2. **`onlysetReg` operand decode** — `set $ra` wrote the wrong SFR (misc reg 4
   not 3), looping the function epilogue until the stack walked off. The Layer-C
   decoder indexed the register-class list compactly instead of by file
   position; fixed in `src/arch/lvx/operands.c` (`filebase + raw`).

Those two failures were **not** ISS bugs: GCC lowered integer `/` and `%` to an
FP-reciprocal sequence emitting `frecw.rn`/`fwidenlwd`, mnemonics the assembler
rejects (`FRECW` was removed from the ISA). Since fixed — `scalar.md` now has
real `divmod{si,di}4`/`udivmod{si,di}4` expanders over the hardware divide, and
both tests pass.

## Localizing a MISMATCH

1. **`OPT=0` vs `OPT=2`** — passes at `-O0`, fails at `-O2` ⇒ optimizer; fails at
   both ⇒ codegen / runtime / ISS.
2. **Cross front-end** — `FRONTEND=gcc` against `FRONTEND=llvm` on the same ISS.
   A test failing under one and passing under the other localizes to that
   compiler; failing under both localizes to the ISS. This is how the `fmin`
   pairing bug was caught: `minmax.c` scored 47 under LLVM and 30 under GCC,
   losing exactly the NaN checks, so the ISS was exonerated immediately.
3. **Per-opcode** — drop to `lvx-mds/MDS/BE/GEM5/TEST/` to isolate a single
   opcode's semantics from the gem5 shim / bundle front-end.

## Layout

```
run.sh              spine: build+run x86 ref, build+run LVX, compare, report
run-ir.sh           the same, for LLVM IR: no C, no x86 reference, each .ll
                    carries "; EXPECT: <n>" and needs only llc + the assembler
Makefile            `make check`
frontends/gcc.sh    C -> lvx-mbr ELF, staged so failures bucket cleanly
frontends/llvm.sh   C -> IR (clang, riscv64 triple) -> llc -mtriple=lvx -> ELF;
                    there is no clang driver for LVX, so the IR is retargeted
lib/harness.h       shared test harness (x86 + lvx via #ifdef __lvx__)
lib/crt.S           freestanding lvx runtime (_start, sys_write, sys_exit)
lib/run_lvx.sh      gem5 wrapper: run ELF, emit result marker + exit status
tests/micro/*.c     hand-written one-construct-each smoke/coverage tests
tests/ir/*.ll       the same at IR level, for shapes C cannot spell
```

Every test scores **47** when correct (285 and 100 and 33 for the three oldest),
so a partial score localizes the failure to a checked property rather than just
saying "wrong".

`tests/micro/`: `arith branches calls floats fma immediates loops minmax mul
shifts switches word32`
`tests/ir/`: `arith callclobber divmod divmod32 frame minmax-nan mul stackargs`

Two of these exist because a *lit* test could not reach the property:
`minmax-nan.ll` decides which min/max instruction is which by running both on
the ISS with a NaN, and `word32.c` checks that the 32-bit forms extend the right
way — every value in it has bit 31 set, the only case where the two extensions
disagree.

## Adding a front-end (LLVM / MLIR)

Drop a `frontends/<name>.sh` with the same contract as `gcc.sh`:
`<name>.sh <test.c> <workdir> <opt>` → print the ELF path (exit 0) or a bucket
keyword (exit 1). Everything else is shared. Then `make check FRONTEND=<name>`.

## Adding tests

New `tests/micro/foo.c`: `#include "harness.h"`, define `int test_main(void)`
returning an int. Keep it freestanding (no libc calls) and deterministic (no UB,
no addresses/time in the result). Next: the GCC `gcc.c-torture/execute` suite,
which is self-checking and a large ready-made corpus (a second TESTS glob).
