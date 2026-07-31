; EXPECT: 47
;
; Regression test for an incomplete caller-saved clobber list on CALL/ICALL.
;
; LVXInstrInfo.td's `let Defs` on CALL must name every caller-saved GPR, which
; per lvx-refs Convention.table is R0-R11, R15, R16, R17 AND R32-R63 -- the
; complement of CSR_LVX's callee-saved R14 + R18-R31. The list originally
; stopped at R17, so the allocator believed R32-R63 survived a call. Those sort
; first among the caller-saved scratch registers in GPR's allocation order, so
; they are exactly what a function reaches for first: a plain recursive fib()
; at -O2 kept its induction variable in $r32 and its accumulator in $r33 across
; "call fib", the callee reused both, and the loop never terminated (the test
; harness reported it as a timeout, not a wrong answer).
;
; The shape that catches it is values that MUST stay live across a call and
; MUST NOT be rematerializable -- hence the volatile loads and the recursion.
; A leaf function, or one whose live values are constants, will not reproduce
; it no matter how many registers it uses.

@seed = global i64 10

define i64 @rec(i64 %n) noinline {
entry:
  %isbase = icmp slt i64 %n, 2
  br i1 %isbase, label %base, label %step
base:
  ret i64 %n
step:
  ; Two independent values live across two calls. With a short clobber list
  ; these land in $r32/$r33 and are destroyed by the recursive callee.
  %n1 = sub i64 %n, 1
  %n2 = sub i64 %n, 2
  %a = call i64 @rec(i64 %n1)
  %b = call i64 @rec(i64 %n2)
  %s = add i64 %a, %b
  ret i64 %s
}

define i32 @main() {
entry:
  %n = load volatile i64, ptr @seed
  %f = call i64 @rec(i64 %n)        ; fib(10) = 55
  %ok = icmp eq i64 %f, 55
  %r = select i1 %ok, i32 47, i32 1
  ret i32 %r
}
