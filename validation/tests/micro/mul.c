/* Integer multiplication, kept separate from arith.c so it stays free of
 * '/' and '%' (those still lower to libcalls with no libgcc to link against
 * on this freestanding target, which would bucket the whole file as a link
 * failure and hide the multiply signal).
 *
 * The point of this test is that it distinguishes the LOW half of a product
 * from the HIGH half.  LVX's MULD selects between them with the `highmult`
 * modifier, and -- unlike KVX -- the *low* (plain "muld") multiply is
 * encoding 3, not 0: Description.yml's MULD reads
 *   "if (highmult == 3) result1 = product.64[0]; else result1 = product.64[1]"
 * and Modifier.table spells highmult ".H .HU .HSU ." over values "0 1 2 3".
 * C has no way to spell mulhs/mulhu directly, so this file can only cover the
 * low multiply; the high forms (where the KVX convention actually did produce
 * the wrong instruction) are pinned by
 * llvm/test/CodeGen/LVX/mul-highmult.ll.
 *
 * So the operands below are chosen to make the two halves differ:
 * 0x0123456789ABCDEF * 0x10 has a nonzero low half AND a nonzero high half,
 * so low-vs-high is not a 0-vs-something accident.  `volatile` keeps the
 * multiplies out of the constant folder, and none of them is by a power of
 * two that strength-reduction would turn into a shift (which would bypass
 * MULD entirely -- the reason arith.c's "r * 2" never exercised this).
 *
 * Expected result: 47.
 */
#include "harness.h"

int test_main(void)
{
    volatile long a = 0x0123456789ABCDEFL;
    volatile long b = 0x10L;
    volatile long s = -3, t = 7;
    volatile int  m = 1000, n = 1000003;

    int r = 0;

    /* Low half of a 64-bit product. High half of a*b is 0x0..12345678,
     * low half is 0x9ABCDEF0 -- a high-multiply would give a different
     * number here, not merely a truncated one. */
    long lo = a * b;
    r += (lo == 0x123456789ABCDEF0L) ? 10 : 0;

    /* Signed multiply with a negative operand: low half is sign-agnostic,
     * but a high-multiply would return the sign-extension word instead. */
    r += (s * t == -21L) ? 10 : 0;

    /* A 32-bit multiply that overflows int, to check the result is the
     * wrapped low word (harness builds with -fwrapv). */
    r += ((int)(m * n) == (int)1000003000) ? 10 : 0;

    /* Multiply feeding an add, so the product is consumed rather than
     * compared directly -- catches a wrong-operand-order or wrong-modifier
     * selection that a lone comparison might still fold away. */
    long acc = 1;
    for (int i = 1; i <= 5; i++)
        acc = acc * i;          /* 5! = 120 */
    r += (acc == 120L) ? 17 : 0;

    return r;                    /* 10 + 10 + 10 + 17 = 47 */
}
