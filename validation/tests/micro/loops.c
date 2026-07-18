/* Loop + accumulation: sum of i*i for i in 0..9.  Expected result: 285. */
#include "harness.h"

int test_main(void)
{
    int s = 0;
    for (int i = 0; i < 10; i++)
        s += i * i;
    return s;
}
