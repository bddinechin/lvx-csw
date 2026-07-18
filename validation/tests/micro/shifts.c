/* Shifts and bitwise ops, signed and unsigned.  Expected result: 100. */
#include "harness.h"

int test_main(void)
{
    volatile unsigned u = 0xF0u;
    volatile int s = -8;
    int r = (int)(u >> 2);      /* 60 */
    r += (u & 0x0F) | 0x03;     /* 60 + 3 = 63 */
    r += (s >> 1);              /* arithmetic: 63 + (-4) = 59 */
    r += (1 << 5) + 9;          /* 59 + 41 = 100 */
    return r;
}
