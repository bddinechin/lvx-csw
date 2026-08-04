/* Wide immediate operands.  Expected result: 47.
 *
 * LVX can feed an ALU instruction an immediate three different ways, and the
 * choice is an ENCODING, not a value: a 10-bit field in a single syllable
 * (ADDD_DWRI), a 37-bit field spilling into a second syllable (..._X), a full
 * 64-bit one (..._Y), and separately the "magic" two-syllable form (..._M)
 * that carries a 32-bit field plus a `splat32` modifier.  Which one the
 * selector picks depends only on how wide the constant is, so a constant that
 * needs 11 bits and one that needs 33 travel completely different paths to the
 * same arithmetic.
 *
 * splat32 is what makes the _M form worth pinning: value 0 sign-extends the
 * 32-bit field to 64 bits and value 1 replicates it into both halves
 * (Modifier.table spells it ". .@" over "0 1").  Emitting the wrong one is
 * silent -- both assemble, and the .@ form only diverges once the operand
 * needs more than the low 32 bits, which is exactly the range the constants
 * below are chosen to straddle.
 *
 * `volatile` keeps every operand out of the constant folder; without it the
 * whole file folds to a return of 47 and nothing is exercised at all.
 */
#include "harness.h"

int test_main(void)
{
    int r = 0;

    /* --- constants that need more than 10 bits but fit in signed 32 --- */
    volatile long x = 1000;
    if (x + 100000L == 101000L)                 r += 5;
    if (x - 2000000000L == -1999999000L)        r += 5;

    /* Subtract FROM a wide immediate.  SBFD's immediate is the minuend, so an
     * operand-order slip here returns the negation of the right answer -- and
     * this is the shape that actually selects the _M encoding. */
    if (2000000000L - x == 1999999000L)         r += 6;

    /* Bitwise ops with a 32-bit immediate: these take the same widened field,
     * so a splat into the upper half shows up as set bits above bit 31. */
    volatile long y = 0x00000000FFFFFFFFL;
    if ((y & 0x12345678L) == 0x12345678L)       r += 5;
    if ((y | 0x7FFFFFFFL) == 0x00000000FFFFFFFFL) r += 5;
    if ((y ^ 0x0F0F0F0FL) == 0x00000000F0F0F0F0L) r += 5;

    /* A negative 32-bit immediate must sign-extend, not zero-extend: the
     * result's upper word is all ones, which a splat would not produce. */
    volatile long z = 0;
    if ((z + -2000000000L) == -2000000000L)     r += 6;
    if ((z ^ -1L) == -1L)                       r += 5;

    /* Beyond 32 bits, so the selector must reach for the 64-bit form rather
     * than truncate into the 32-bit field. */
    volatile long w = 1;
    if (w + 0x123456789ABCL == 0x123456789ABDL) r += 5;

    return r;                    /* 5+5+6+5+5+5+6+5+5 = 47 */
}
