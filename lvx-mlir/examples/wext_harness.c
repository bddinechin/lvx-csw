/* Harness for wext.mlir -- the first end-to-end exercise of LVX's 32-bit
 * integer instructions through the MLIR path.
 *
 * Until this existed the `w` mnemonics were emitted by -convert-to-lvx and
 * checked only by FileCheck: no 32-bit integer instruction had ever been
 * executed on gem5. That gap matters more than it sounds, because on a
 * 64-bit register file a `w` op's result depends on the `signextw` modifier
 * (bare = zero-extend, `.sx` = sign-extend), and getting it wrong produces a
 * wrong *number* rather than a failure -- invisible to any structural test.
 *
 * The inputs are picked so the two extensions disagree: a+b sets bit 31, so
 * sign- and zero-extension of it differ by 2^32.
 */
#include "harness.h"

#if defined(__lvx__)
/* Emitted by mlir-opt from examples/wext.mlir, assembled by lvx-mbr-as. */
extern long wext(int a, int b);
#else
/* Native oracle: the same arithmetic, written plainly. The casts are the
 * point -- (long)(int) sign-extends, (long)(unsigned) zero-extends. */
static int ref_clz32(unsigned v)
{
    int n = 0;
    for (int i = 31; i >= 0 && !((v >> i) & 1u); i--) n++;
    return n;
}

static long wext(int a, int b)
{
    int sum  = (int)((unsigned)a + (unsigned)b);   /* wrapping, like arith.addi */
    int prod = (int)((unsigned)a * (unsigned)b);
    int notv = ~a;
    int clzv = ref_clz32((unsigned)b);
    return (long)sum + (long)(unsigned)prod + (long)notv + (long)clzv;
}
#endif

int test_main(void)
{
    volatile int a = 0x7FFFFFFF;
    volatile int b = 1;
    long r = wext(a, b);
    /* -2147483648 + 2147483647 + -2147483648 + 31 == -2147483618. Each of
     * the two sign-extended terms would be off by 2^32 if its fold had
     * produced a zero-extension instead, so a wrong modifier fails here
     * rather than passing quietly. */
    return (int)(r == -2147483618L ? 42 : 0);
}
