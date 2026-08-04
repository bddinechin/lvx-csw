#!/usr/bin/env bash
# Lower examples/mymma.mlir to real LVX machine code, link it against a C test
# harness built with lvx-gcc, and run the result on gem5 against an x86 oracle.
#
# Usage:
#   ./build-mymma.sh                 # default 8x16x8, lowers + runs on gem5
#   ./build-mymma.sh 256 512 256     # the shipped dimensions (see NOTE below)
#
# NOTE on size: mymma.mlir as written is 256x512x256 = 33.5M multiply-adds.
# That lowers, assembles and links fine, but running it under gem5 takes hours.
# The default dimensions are small so the numeric check actually completes; the
# pipeline is identical either way.
set -eu

M=${1:-8}; K=${2:-16}; N=${3:-8}

HERE=$(cd "$(dirname "$0")" && pwd)
CSW=$(cd "$HERE/../.." && pwd)
MLIR_OPT=$CSW/lvx-mlir/llvm-project/build/bin/mlir-opt
LVX=$CSW/lvx-toolchain/bin
VLIB=$CSW/validation/lib
GEM5=$CSW/lvx-gem5/build/gem5-lvx1.opt
GEM5_CFG=$CSW/lvx-gem5/tests/lvx/run_lvx.py

OUT=$HERE/build
mkdir -p "$OUT"

echo "== 0. dimensions: ${M}x${K}x${N}"
# Derive the .mlir from the hand-written one, so only the shapes differ.
sed -e "s/256x512xf32/${M}x${K}xf32/" \
    -e "s/512x256xf32/${K}x${N}xf32/" \
    -e "s/256x256xf32/${M}x${N}xf32/" \
    "$HERE/mymma.mlir" > "$OUT/mymma_dims.mlir"

# --- The lowering, in three stages so a failure buckets cleanly. -------------

echo "== 1. linalg -> scf/memref/arith  (upstream pass; convert-to-lvx does not take linalg)"
"$MLIR_OPT" "$OUT/mymma_dims.mlir" -convert-linalg-to-loops -o "$OUT/mymma.loops.mlir"

echo "== 2. scf/memref/arith/func -> the LVX dialects"
"$MLIR_OPT" "$OUT/mymma.loops.mlir" -convert-to-lvx -o "$OUT/mymma.lvx.mlir"

# Peephole before CSE: folding muld+addd into addx exposes new common
# subexpressions, so this order is worth more than the reverse. Neither runs
# before -convert-to-lvx, because the redundancy does not exist at the
# scf/memref level -- -convert-to-lvx creates it, expanding every
# memref.load/store into its own address computation.
#
# On this kernel, cumulatively: 54 bundles raw, 43 with CSE alone, 37 with
# combine alone, 35 with both.
echo "== 2b. peephole combine (muld+addd -> addx<N>)"
"$MLIR_OPT" "$OUT/mymma.lvx.mlir" --pass-pipeline='builtin.module(any(lvx-combine))' \
  -o "$OUT/mymma.combine.mlir"

echo "== 2c. CSE (address arithmetic is duplicated per load/store)"
"$MLIR_OPT" "$OUT/mymma.combine.mlir" -cse -o "$OUT/mymma.cse.mlir"

# Run the four back-end passes one at a time rather than as a single
# pipeline, so every stage leaves an inspectable file. The result is
# identical -- these passes only ever run in this order (see
# lvx-mlir/docs/Architecture.md, "Pass ordering is load-bearing").
echo "== 3a. register allocation      (virtual -> physical !lvx.reg<rN>)"
"$MLIR_OPT" "$OUT/mymma.cse.mlir" -o "$OUT/mymma.alloc.mlir" \
  --pass-pipeline='builtin.module(any(lvx-allocate-registers))'

echo "== 3b. divmod fixup             (pin the registerM result pair)"
"$MLIR_OPT" "$OUT/mymma.alloc.mlir" -o "$OUT/mymma.divmod.mlir" \
  --pass-pipeline='builtin.module(any(lvx-rewrite-divmod))'

echo "== 3c. structured -> branches   (lvx_scf.for -> lvx_cf / LOOPDO)"
"$MLIR_OPT" "$OUT/mymma.divmod.mlir" -o "$OUT/mymma.cf.mlir" \
  --pass-pipeline='builtin.module(any(lvx-scf-to-cf))'

echo "== 3d. assembly emission"
"$MLIR_OPT" "$OUT/mymma.cf.mlir" -o /dev/null \
  --pass-pipeline='builtin.module(lvx-emit-asm)' > "$OUT/mymma.s"

echo "== 4. assemble the emitted LVX assembly with the real assembler"
"$LVX/lvx-mbr-as" "$OUT/mymma.s" -o "$OUT/mymma.o"

echo "== 5. compile the C harness with lvx-gcc, and the freestanding crt"
"$LVX/lvx-mbr-gcc" -O2 -march=lvx-1 -ffreestanding -fno-strict-aliasing -fwrapv \
  -DMYMMA_M=$M -DMYMMA_K=$K -DMYMMA_N=$N \
  -I"$VLIB" -c "$HERE/mymma_harness.c" -o "$OUT/harness.o"
"$LVX/lvx-mbr-as" "$VLIB/crt.S" -o "$OUT/crt.o"

echo "== 6. link"
"$LVX/lvx-mbr-ld" -e _start -Ttext=0x10000 -nostdlib \
  "$OUT/crt.o" "$OUT/harness.o" "$OUT/mymma.o" -o "$OUT/mymma.elf"
echo "   -> $OUT/mymma.elf"

# --- Oracle + execution ------------------------------------------------------

echo "== 7. x86 reference (same harness, plain C kernel)"
cc -O2 -fno-strict-aliasing -fwrapv -DMYMMA_M=$M -DMYMMA_K=$K -DMYMMA_N=$N \
  -I"$VLIB" "$HERE/mymma_harness.c" -o "$OUT/mymma.ref"
ref=$("$OUT/mymma.ref" | grep '^__LVXR__ ' | awk '{print $2}')
echo "   x86 result: $ref"

echo "== 8. run the LVX ELF on gem5"
# Reuse validation/lib/run_lvx.sh rather than reimplementing the invocation:
# it knows the config takes the ELF positionally, and it distinguishes a guest
# exit from a timeout and from gem5 itself dying on an unimplemented opcode.
run=$(GEM5="$GEM5" GEM5_CFG="$GEM5_CFG" LVX_TIMEOUT="${LVX_TIMEOUT:-120}" \
        bash "$VLIB/run_lvx.sh" "$OUT/mymma.elf")
echo "$run" | sed 's/^/   /'
got=$(echo "$run" | grep '^__LVXR__ ' | awk '{print $2}')

if [ "${got:-}" = "$ref" ]; then
	echo "PASS  (${M}x${K}x${N}: LVX == x86 == $ref)"
else
	echo "FAIL  (x86=$ref gem5=${got:-<none>})"; exit 1
fi
