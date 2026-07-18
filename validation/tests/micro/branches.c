/* Control flow: if/else, switch, conditional select.  Expected result: 42. */
#include "harness.h"

static int classify(int x)
{
    if (x < 0) return -1;
    switch (x % 3) {
    case 0:  return x * 2;
    case 1:  return x + 100;
    default: return x - 1;
    }
}

int test_main(void)
{
    int r = 0;
    for (int i = 0; i < 6; i++)
        r += classify(i) > 50 ? 1 : classify(i) & 7;
    /* i: 0->0, 1->+1(101>50), 2->1(1), 3->+1(6>50? no ->6&7=6)... compute at runtime */
    return r + 20;
}
