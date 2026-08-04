/* Floating-point minimum and maximum.  Expected result: 47.
 *
 * LVX has two min/max families, and the difference between them is only ever
 * visible on a NaN or a signed zero:
 *
 *   fminn  IEEE 754-2008 minNum   -- returns the non-NaN operand
 *   fmin   IEEE 754-2019 minimum  -- propagates the NaN
 *
 * C's fmin/fmax are the -2008 ones, so __builtin_fmin selects fminn, and that
 * is the pair this file can check against the native x86 reference. The
 * -2019 pair has no portable C spelling before C23, so which instruction each
 * LLVM node picks is pinned in llvm/test/CodeGen/LVX/fp-minmax-rint.ll
 * instead; what this file adds is that the instruction the ISS executes
 * actually computes what x86 computes.
 *
 * That matters here more than for most arithmetic: min/max were expanded into
 * a compare-and-select chain until now, so this is the first time the
 * hardware instructions run at all.
 *
 * KNOWN FAILURE under FRONTEND=gcc, and it is a real lvx-gcc bug rather than
 * a defect in this test: lvx-gcc compiles fmin to `fmind`, the -2019
 * NaN-PROPAGATING instruction, where C requires the -2008 one, `fminnd`.
 *
 *     double f(double a, double b) { return __builtin_fmin(a, b); }
 *     lvx-mbr-gcc -O2  ->  fmind $r0 = $r0, $r1        <-- wrong
 *     llc -mtriple=lvx ->  fminnd $r0 = $r0, $r1       <-- right
 *
 * so it scores 30 instead of 47, losing exactly the three NaN checks. The
 * description names the two helpers apart -- f64_min against f64_minNum -- and
 * the LLVM patterns are generated from those names, which is why this side
 * gets it right. The non-NaN cases agree on both compilers, which is why the
 * pairing could stay wrong this long.
 *
 * `volatile` keeps every operand away from the constant folder; without it
 * the whole file folds and nothing executes.
 */
#include "harness.h"

int test_main(void)
{
    int r = 0;

    volatile double a = 3.5, b = -2.25;
    if (__builtin_fmin(a, b) == -2.25) r += 5;
    if (__builtin_fmax(a, b) == 3.5)   r += 5;

    /* Equal magnitudes of opposite sign, so a comparison that got the
     * direction backwards still has to pick the right one. */
    volatile double c = 7.0, d = -7.0;
    if (__builtin_fmin(c, d) == -7.0)  r += 5;
    if (__builtin_fmax(c, d) == 7.0)   r += 5;

    /* NaN in one operand: minNum returns the OTHER one rather than
     * propagating, which is exactly what separates it from -2019 minimum.
     * A wrong pairing here returns a NaN and fails the comparison. */
    volatile double n = __builtin_nan("");
    volatile double e = 1.5;
    if (__builtin_fmin(n, e) == 1.5)   r += 6;
    if (__builtin_fmax(n, e) == 1.5)   r += 6;
    if (__builtin_fmin(e, n) == 1.5)   r += 5;

    /* float, so the 32-bit instructions are exercised too and not just the
     * 64-bit ones -- they are separate encodings. */
    volatile float f = -0.5f, g = 4.0f;
    if (__builtin_fminf(f, g) == -0.5f) r += 5;
    if (__builtin_fmaxf(f, g) == 4.0f)  r += 5;

    return r;                    /* 5*4 + 6*2 + 5 + 5*2 = 47 */
}
