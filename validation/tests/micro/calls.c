/* Function calls and the kv4-v1 calling convention (args, return, recursion).
 * Expected result: fib(10) + gcd(48,36) = 55 + 12 = 67. */
#include "harness.h"

static int fib(int n) { return n < 2 ? n : fib(n - 1) + fib(n - 2); }
static int gcd(int a, int b) { while (b) { int t = a % b; a = b; b = t; } return a; }

int test_main(void)
{
    return fib(10) + gcd(48, 36);
}
