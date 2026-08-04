/* Test harness for the MLIR-produced `mymma_32` kernel.
 *
 * Plugs into the existing differential harness (validation/lib/harness.h):
 * `test_main` returns an int, reported identically on both targets as a
 * "__LVXR__ <decimal>" line plus the exit code.  validation/run.sh builds this
 * same file twice -- natively with cc (the oracle) and for lvx-mbr with
 * lvx-mbr-gcc -- and compares the two markers.
 *
 * The two sides differ in exactly one place: on lvx, `mymma_32` is the real
 * kernel emitted by mlir-opt from examples/mymma.mlir and assembled by
 * lvx-mbr-as; natively it is the plain C reference below.  So a PASS means the
 * MLIR-generated LVX machine code agrees with straightforward C.
 *
 * ABI note: -convert-to-lvx maps a `memref` to a single `!lvx.reg` -- a bare
 * base pointer, with no descriptor struct and no shape/stride operands.  The
 * three memref arguments are therefore just three pointers in $r0/$r1/$r2.
 *
 * Dimensions must match the .mlir being linked in; build-mymma.sh derives the
 * .mlir from the same -D values it passes here, so the two cannot drift.
 */
#include "harness.h"

#ifndef MYMMA_M
#define MYMMA_M 8
#endif
#ifndef MYMMA_K
#define MYMMA_K 16
#endif
#ifndef MYMMA_N
#define MYMMA_N 8
#endif

static float A[MYMMA_M * MYMMA_K];
static float B[MYMMA_K * MYMMA_N];
static float C[MYMMA_M * MYMMA_N];

#if defined(__lvx__)
/* Emitted by mlir-opt from examples/mymma.mlir, assembled by lvx-mbr-as. */
extern void mymma_32(const float *a, const float *b, float *c);
#else
/* Native oracle: the same contraction, written plainly.  Accumulation order
 * matches linalg.generic's reduction (innermost over d2/k), which matters only
 * if the values were inexact -- they are not, see below. */
static void mymma_32(const float *a, const float *b, float *c)
{
    for (int i = 0; i < MYMMA_M; i++)
        for (int j = 0; j < MYMMA_N; j++) {
            float acc = c[i * MYMMA_N + j];
            for (int k = 0; k < MYMMA_K; k++)
                acc += a[i * MYMMA_K + k] * b[k * MYMMA_N + j];
            c[i * MYMMA_N + j] = acc;
        }
}
#endif

int test_main(void)
{
    /* Small integer inputs, so every product and partial sum is exactly
     * representable in f32 (well inside 2^24).  The comparison against the
     * x86 oracle is then bit-exact, and a mismatch means a real codegen bug
     * rather than a rounding-order difference. */
    for (int i = 0; i < MYMMA_M; i++)
        for (int k = 0; k < MYMMA_K; k++)
            A[i * MYMMA_K + k] = (float)((i + k) % 7 - 3);
    for (int k = 0; k < MYMMA_K; k++)
        for (int j = 0; j < MYMMA_N; j++)
            B[k * MYMMA_N + j] = (float)((k * 3 + j) % 5 - 2);
    /* C is .bss, hence already zero -- linalg.generic accumulates into it. */

    mymma_32(A, B, C);

    long acc = 0;
    for (int i = 0; i < MYMMA_M * MYMMA_N; i++)
        acc = ((acc * 131 + (long)C[i]) % 1000000007L + 1000000007L) % 1000000007L;
    return (int)acc;
}
