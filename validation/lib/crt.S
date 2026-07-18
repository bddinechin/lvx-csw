/* Freestanding lvx-mbr runtime for the differential harness.
 *
 * gem5's SE loader sets the entry PC to _start and $r12 (SP) to the stack top,
 * so _start only has to call main() and turn its return value into an exit.
 * Syscalls follow the kv4-v1 ABI used by lvx-newlib's libgloss: the number is
 * the scall operand, arguments are already in $r0..$r7, the result comes back
 * in $r0.  gem5's shim implements #1 (exit) and #17 (write) today.
 *
 * Bundle syntax (";;" terminator, "scall N;; ret;;") mirrors the verified
 * lvx-newlib asm_syscalls.S and lvx-gem5/tests/lvx/*.s smoke tests.
 */
	.section .text, "ax", @progbits
	.align 4

	.global _start
_start:
	call main
	;;
	/* main() returns its result in $r0 -> becomes the exit status. */
	scall 1			/* __NR_exit */
	;;
1:	goto 1b			/* not reached */
	;;

	/* long sys_write(int fd, const void *buf, unsigned long n)
	   fd/buf/n arrive in $r0/$r1/$r2; result in $r0. */
	.global sys_write
sys_write:
	scall 17		/* __NR_write */
	;;
	ret
	;;

	/* void sys_exit(int code)  — code in $r0. */
	.global sys_exit
sys_exit:
	scall 1			/* __NR_exit */
	;;
	ret
	;;
