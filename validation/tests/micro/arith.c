/* Integer arithmetic: +, -, *, /, %.  Expected result: 47. */
#include "harness.h"

int test_main(void)
{
    volatile int a = 20, b = 6, c = 3;
    int r = a + b;      /* 26 */
    r = r - c;          /* 23 */
    r = r * 2;          /* 46 */
    r = r + a / b;      /* 46 + 3 = 49 */
    r = r - a % b;      /* 49 - 2 = 47 */
    return r;
}
