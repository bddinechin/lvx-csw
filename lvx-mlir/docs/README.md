# lvx-mlir documentation

Design and validation records for **lvx-mlir**: a family of MLIR dialects
representing pre-register-allocation machine code for the LVX VLIW
architecture, plus the passes that lower ordinary MLIR into them and emit real
LVX assembly.

Start with **[Architecture.md](Architecture.md)** — the dialect family, the
pipeline end to end, and where each piece lives. Everything else here is a
record of one subsystem's design decisions, written as the work was done.

## These documents

| Document | Status | What it covers |
|---|---|---|
| [Architecture.md](Architecture.md) | current | The four dialects, the lowering pipeline, the source layout. **Read first.** |
| [RegisterAllocation.md](RegisterAllocation.md) | implemented | Linear scan (Poletto & Sarkar): live intervals, assignment, spilling, coalescing, frame layout, callee-saved save/restore, the reserved scratch pool. The longest and most load-bearing document here. |
| [AssemblyEmission.md](AssemblyEmission.md) | implemented | `-lvx-scf-to-cf`, `-lvx-rewrite-divmod`, `-lvx-emit-asm`: real mnemonic/operand syntax, verified by hand-assembling against `lvx-mbr-as` rather than inferred from tables. |
| [HardwareLoops.md](HardwareLoops.md) | implemented | `LOOPDO` zero-overhead loops: eligibility, lowering, and why the exit branch must *not* be printed. |
| [EndToEndValidation.md](EndToEndValidation.md) | done | Taking a real kernel through the whole pipeline to real `lvx-gem5`, and the four bugs that found. |
| [LinearScanComparison.md](LinearScanComparison.md) | discussion record | Our linear scan measured against the SSA-based literature (Mössenböck, Wimmer, Pereira, Hack). No code resulted; kept so the comparison isn't redone. |
| [MultiRegisterClasses.md](MultiRegisterClasses.md) | forward-looking | Graph-colouring with overlapping register classes, for the future SIMD pair/quad phase. Not implemented. |

Two of these — `LinearScanComparison.md` and `MultiRegisterClasses.md` —
describe work that was **not** done. They are reference material, not a
description of the code. Each says so in its own status line.

## Generated documentation, not checked in

The per-operation dialect reference is generated from the `.td` sources:

```
ninja -C llvm-project/build mlir-doc
-> llvm-project/build/tools/mlir/docs/Dialects/LVXOps.md      (79 ops)
                                              LVXCFOps.md    (8 ops)
                                              LVXFuncOps.md  (8 ops)
                                              LVXSCFOps.md   (7 ops)
```

That is the authoritative list of operations, their operands, results and
assembly formats. It is deliberately not committed — it would go stale the
moment a `.td` file changed.

## Why these live outside the submodule

`lvx-mlir/docs/`, not `llvm-project/docs/lvx/`. These document the LVX project
rather than the LLVM fork, and keeping them out means the fork's diff against
upstream is code only — which matters, since that fork gets rebased onto
upstream `main` periodically.

The cost is that source comments cite them by a path relative to the
superproject root (`lvx-mlir/docs/RegisterAllocation.md`), and a change to a
pass and to the document describing it now spans two repositories. Prefer
making both edits in the same session.

## Ground truth

None of this is the authority on the LVX ISA itself. That is `lvx-mds/lvx-refs/`
— see the parent `../CLAUDE.md` for the file-by-file map, and
`../../lvx-target/` for the ABI and instruction-bundling specifications
(`make -C ../../lvx-target` builds them as PDFs).
