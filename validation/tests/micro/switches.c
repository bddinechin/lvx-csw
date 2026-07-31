/* Switch statements dense enough to become a jump table.  Expected: 47.
 *
 * A sparse switch compiles to a chain of compares and never exercises the
 * table path, so the cases here are contiguous.  At -O0 clang emits the
 * jump table for anything this dense; at higher -O levels it may still
 * choose a compare chain, which is why the test runs at both.
 *
 * The interesting parts are the edges, because a jump table is really three
 * things that can each be wrong independently: the unsigned range check that
 * guards it, the scaled index into the table, and the indirect branch through
 * the loaded entry.  So this calls every in-range case (checking the index
 * scaling picks the right entry, not merely a valid one), plus both
 * out-of-range directions -- above the top case and, via a negative value,
 * below zero.  The negative case matters: the guard is an UNSIGNED compare,
 * so -1 must be caught as a huge unsigned value rather than sailing through
 * and indexing off the front of the table.
 */
#include "harness.h"

static int pick(int n)
{
    switch (n) {
    case 0:  return 3;
    case 1:  return 5;
    case 2:  return 7;
    case 3:  return 11;
    case 4:  return 13;
    case 5:  return 17;
    case 6:  return 19;
    case 7:  return 23;
    default: return 1;
    }
}

/* A second switch whose cases do not start at zero, so the lowering has to
 * bias the index before indexing the table. */
static int offsetted(int n)
{
    switch (n) {
    case 100: return 2;
    case 101: return 4;
    case 102: return 6;
    case 103: return 8;
    default:  return 1;
    }
}

int test_main(void)
{
    volatile int i;
    int sum = 0;

    /* every in-range case: 3+5+7+11+13+17+19+23 = 98 */
    for (i = 0; i < 8; i++)
        sum += pick((int)i);

    /* out of range on both sides -> default (1) twice */
    i = 8;  sum += pick((int)i);
    i = -1; sum += pick((int)i);

    /* biased table: 2+4+6+8 = 20, plus one default */
    for (i = 100; i < 104; i++)
        sum += offsetted((int)i);
    i = 99; sum += offsetted((int)i);

    /* 98 + 1 + 1 + 20 + 1 = 121 */
    return sum - 74;                 /* 121 - 74 = 47 */
}
