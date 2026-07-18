# LVX project roadmap and validation strategy

Strategic record for the LVX toolchain effort. Captures the overall goal, the
source-of-truth architecture that constrains how validation can work, and the
sequencing of work across near/medium/long horizons. Written 2026-07-18.

## Overall goal

Build the LVX toolchain and, eventually, an LVX CPU implementation.

**Near-term priority (now):** a working **LVX ISS** — the gem5 port (`lvx-gem5`) —
so the LVX compiler back-ends (**GCC**, **LLVM**, and an **MLIR-to-machine-code**
path, all started in separate sessions) can be tested against something that runs
their output. The ISS is the shared validation substrate for all three compilers.

**Long-term:** an LVX silicon implementation. The ISA semantics feed the standard
modern flow (formal reference model → test generation → RTL verification).

## The constraint that shapes everything: source of truth

`Behavior` (the S-expression IR in `lvx-mds`, see `lvx-mds/MDS/DOC/Behavior.md`) is
the **single source of truth** for LVX instruction semantics, and drives every MDS
back-end (GAS encoding, scheduler, GCC/GDB models, TeX, and the ISS).

The gem5 ISS **is Behavior compiled** — it reuses `BE/LAO`'s `Behavior.tuple` +
`Decode.c` verbatim as C over a hand-written shim (see
`lvx-gem5/PHASE0-FINDINGS.md`). Therefore **any model derived from Behavior shares
its source with gem5**, and a differential test between two Behavior-derived
artifacts can only catch *translation/runtime* divergence — never a *specification*
bug (a wrong `behavior:` is wrong identically in both).

**Consequence for validation:** to validate the compiler+ISS pair while both are
under test, the oracle must be **independent of Behavior**. The primary independent
oracle is **native-x86 differential execution** (compile the same C to x86 and to
LVX, run both, diff stdout/exit). This is the keystone of near-term work because all
three compilers share it.

Corollary: **Behavior → Sail is NOT a gem5 oracle** (shared source; and Sail cannot
model the VLIW bundle front-end, the riskiest hand-written layer). It is worth
building for its *other* payoffs (below), not for validating the ISS.

## Sequencing

| Horizon | Work | Serves |
|---|---|---|
| **Now** | Finish gem5 ISS coverage (driven by what GCC/LLVM/MLIR emit) + **native-x86 differential harness** + `lvx-newlib` runtime; fix the blocking `lvx-gcc` codegen bugs | GCC/LLVM/MLIR validation |
| **Then** | KVX-ISS / SoftFloat **helper-level oracle** for the opaque FP/SIMD `APPLY` bodies, as FP coverage arrives | ISS correctness on helper bodies |
| **Medium** | **Behavior → Sail** emitter: publishable formal spec, Isla symbolic execution / test generation, Sail typecheck as a CI pass complementing `Width.pm` | verification maturity |
| **Long** | **Sail → SystemVerilog** as a formal per-instruction reference model for RTL verification | LVX silicon bring-up |
| **Orthogonal / deferrable** | **Execution → Behavior** single-source authoring (compile the doc-only `execution:` view to the ground-truth `behavior:`) | maintainability — *not on the ISS critical path*, since the ISS consumes Behavior directly |

## Notes on the far-term Sail track (so it doesn't misdirect the design)

- Sail's SystemVerilog backend produces a **formal reference model for bounded model
  checking** — a golden per-instruction functional spec to check hand-written RTL
  against — **not** a synthesizable, pipelined CPU.
- Sail is sequential: the Behavior → Sail step **flattens away the stage/bundle
  structure**. The resulting SV is a *functional, single-instruction* reference;
  pipelining and VLIW bundling remain the RTL's job, verified per-instruction against
  that reference.
- LVX is RISC-V-flavored where it counts (FP is RISC-V FP, rounding modes, kv4-v1
  ABI), so the Sail RISC-V model and its tooling are natural to crib from.
