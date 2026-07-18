/* Shared test harness — one source, two targets (native x86 and lvx-mbr).
 *
 * A test file #includes this and defines `int test_main(void)` returning an
 * int result.  The harness reports that result on BOTH targets identically:
 *   - as a framed line on stdout:  "__LVXR__ <decimal>\n"
 *   - and as the process exit code (result & 0xff).
 *
 * The stdout marker is the primary oracle (full-width, survives gem5's own
 * chatter); the exit code is the secondary channel.  On lvx the write/exit go
 * through the freestanding syscall stubs in crt.S (scall #17/#1); on x86 they
 * go through libc.  No full newlib is required on either side.
 */
#ifndef LVX_VALIDATION_HARNESS_H
#define LVX_VALIDATION_HARNESS_H

int test_main(void);

#if defined(__lvx__)
/* Provided by crt.S: scall-based write(2)/exit(2), kv4-v1 ABI. */
extern long sys_write(int fd, const void *buf, unsigned long n);
static long harness_write(const char *b, unsigned long n) { return sys_write(1, b, n); }
#else
#include <unistd.h>
static long harness_write(const char *b, unsigned long n) { return write(1, b, n); }
#endif

static void harness_report(long v)
{
    char buf[32];
    unsigned i = sizeof buf;
    int neg = v < 0;
    /* -(v) without UB on INT/LONG_MIN */
    unsigned long u = neg ? (unsigned long)(-(v + 1)) + 1UL : (unsigned long)v;
    buf[--i] = '\n';
    if (!u) buf[--i] = '0';
    while (u) { buf[--i] = (char)('0' + u % 10); u /= 10; }
    if (neg) buf[--i] = '-';
    {
        static const char mark[] = "__LVXR__ ";
        harness_write(mark, sizeof mark - 1);
    }
    harness_write(&buf[i], sizeof buf - i);
}

int main(void)
{
    long r = test_main();
    harness_report(r);
    return (int)(r & 0xff);
}

#endif /* LVX_VALIDATION_HARNESS_H */
