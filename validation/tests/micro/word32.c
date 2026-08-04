/* 32-bit arithmetic in 64-bit registers.  Expected result: 47.
 *
 * LVX computes these in the full register and keeps the low half, with a
 * `signextw` modifier saying whether the kept half is sign- or zero-extended
 * back into the register:
 *
 *   addw     $r0 = $r1, $r0     zero-extend the 32-bit result
 *   addw.sx  $r0 = $r1, $r0     sign-extend it
 *
 * Until these patterns existed, LLVM emitted the pair -- an addd followed by
 * an extfs or an andd -- so this file is also the first time the single-
 * instruction forms run at all.
 *
 * Every value below has BIT 31 SET in its 32-bit result, which is the whole
 * point: that is the only case where the two extensions disagree. A result
 * that fits in 31 bits is identical either way, so a swapped modifier is
 * invisible to any test whose intermediate values stay small -- and the
 * assembly stays plausible, since both spellings exist and both assemble.
 *
 * Signed cases read the result back as `long` (so the sign-extending form is
 * required) and unsigned ones as `unsigned long` (the zero-extending form).
 * The harness builds with -fwrapv, so the signed overflow here is defined.
 */
#include "harness.h"

int test_main(void)
{
    int r = 0;

    /* --- signed: the result must sign-extend ---
     *
     * Each goes through a volatile long rather than being compared directly.
     * A comparison against a 32-bit-representable constant can be done in 32
     * bits, so LLVM drops the extension entirely and the sign-extending
     * instruction never runs -- which it did here, leaving this half of the
     * test measuring nothing. Widening into a 64-bit store makes the
     * extension load-bearing. */
    volatile long out;

    volatile int a = 0x7FFFFFFF, b = 1;
    out = a + b;                                      /* wraps to INT_MIN */
    if (out == -2147483648L)                r += 6;

    volatile int c = (-2147483647 - 1), d = 1;
    out = c - d;                                      /* wraps to INT_MAX */
    if (out == 2147483647L)                 r += 6;

    volatile int e = (int)0xF0000000, f = -1;
    out = e & f;
    if (out == -268435456L)                 r += 5;

    /* --- unsigned: the result must zero-extend --- */
    volatile unsigned ua = 0x80000000u, ub = 0u;
    if ((unsigned long)(ua + ub) == 2147483648UL)  r += 6;

    volatile unsigned uc = 0xFFFFFFFFu, ud = 0x7FFFFFFFu;
    if ((unsigned long)(uc ^ ud) == 2147483648UL)  r += 6;

    volatile unsigned ue = 0x80000000u, uf = 1u;
    if ((unsigned long)(ue | uf) == 2147483649UL)  r += 6;

    volatile unsigned ug = 0xFFFFFFFFu, uh = 0x80000000u;
    if ((unsigned long)(ug & uh) == 2147483648UL)  r += 6;

    volatile unsigned ui = 0u, uj = 1u;
    if ((unsigned long)(ui - uj) == 4294967295UL)  r += 6;

    return r;                    /* 6+6+5+6+6+6+6+6 = 47 */
}
