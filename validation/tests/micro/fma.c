/* Fused multiply-add.  Expected result: 47.
 *
 * FFMAD/FFMAW accumulate into their own destination register, so the addend
 * is a tied operand and the destination is read as well as written.  These
 * checks are about that: that the right value ends up in the accumulator and
 * that the multiplicands are not swapped with it.
 *
 * Every operand here is chosen so the exactly-rounded fused result and the
 * round-twice unfused result are IDENTICAL.  That is deliberate, and it is
 * what makes this a valid differential test: LVX fuses "a*b + c" into one
 * instruction, while the x86 reference (base x86-64, no FMA) does not, and C
 * explicitly permits both.  A case where the two differ would therefore
 * disagree across the two targets by design rather than because of a bug --
 * so the fusion itself is checked in llvm/test/CodeGen/LVX/fp.ll instead,
 * where the emitted instruction can be inspected directly.
 *
 * __builtin_fma is avoided on purpose: clang lowers it to a libm call on this
 * target regardless of flags, so it would exercise newlib's libm rather than
 * the FFMAD instruction.
 */
#include "harness.h"

int test_main(void)
{
    int score = 0;

    /* --- double: small integers, all products and sums exact --- */
    volatile double a = 3.0, b = 4.0, c = 5.0;
    if (a * b + c == 17.0)          score += 6;
    if (a * b - c == 7.0)           score += 6;
    if (-a * b + c == -7.0)         score += 6;

    /* The accumulator is read afterwards, so it cannot simply be clobbered
     * in place by the tied destination. */
    volatile double acc = 1.0;
    double t = a * b + acc;                     /* 13.0 */
    if (t == 13.0 && acc == 1.0)    score += 6;

    /* Chained accumulation: each step feeds the next one's addend, which is
     * the shape the tied operand exists for. */
    volatile double x = 2.0;
    double s = 0.0;
    for (int i = 0; i < 4; i++)
        s = x * x + s;                          /* 4 * 4 = 16 */
    if (s == 16.0)                  score += 7;

    /* --- float --- */
    volatile float fa = 1.5f, fb = 2.0f, fc = 0.25f;
    if (fa * fb + fc == 3.25f)      score += 8;
    if (fa * fb - fc == 2.75f)      score += 8;

    return score;                   /* 6*4 + 7 + 8 + 8 = 47 */
}
