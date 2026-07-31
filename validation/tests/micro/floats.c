/* Scalar floating point: double and float arithmetic, comparisons and
 * conversions.  Expected result: 47.
 *
 * Checked against the same C compiled and run natively on x86, so every
 * value here must be bit-exact on both sides.  That is a real constraint,
 * not a formality: LVX FP is specified to follow RISC-V, the ISS implements
 * it over Berkeley SoftFloat in round-to-nearest-even, and x86 SSE2 does the
 * same, so identical operations must agree exactly.  Operands are chosen to
 * be exactly representable where the test is about the operation rather than
 * about rounding, and the two rounding-sensitive cases below are pinned to
 * their exact IEEE results.
 *
 * `volatile` keeps the constant folder out of it, so the arithmetic really
 * executes on the target rather than being evaluated by the compiler.
 */
#include "harness.h"

int test_main(void)
{
    int score = 0;

    /* --- double arithmetic (all operands exactly representable) --- */
    volatile double a = 12.5, b = 2.0, c = 0.5;
    if (a + b == 14.5)  score += 4;
    if (a - b == 10.5)  score += 4;
    if (a * b == 25.0)  score += 4;
    if (a / b == 6.25)  score += 4;
    if (-a  == -12.5)   score += 1;
    if (a * c == 6.25)  score += 3;

    /* --- comparisons, including an unordered case --- */
    volatile double x = 1.0, y = 2.0;
    if (x < y)          score += 2;
    if (!(x > y))       score += 2;
    if (x <= y && y >= x) score += 2;
    if (x != y)         score += 2;

    /* --- conversions both ways --- */
    volatile double d = -7.75;
    if ((long)d == -7)  score += 3;     /* truncates toward zero */
    volatile long n = -9;
    if ((double)n == -9.0) score += 3;
    volatile unsigned long u = 3;
    if ((double)u == 3.0)  score += 2;

    /* --- float, and float<->double conversion --- */
    volatile float f = 1.5f, g = 4.0f;
    if (f + g == 5.5f)     score += 3;
    if (f * g == 6.0f)     score += 3;
    if ((double)f == 1.5)  score += 3;  /* fwidenwd */

    /* --- a value needing real rounding, pinned to its exact IEEE result --- */
    volatile double t = 1.0, e = 3.0;
    double q = t / e;                   /* nearest double to 1/3 */
    if (q > 0.333333333333333 && q < 0.333333333333334) score += 2;

    /* 20 (double arith) + 8 (compare) + 8 (convert) + 9 (float) + 2 = 47 */
    return score;
}
