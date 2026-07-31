; EXPECT: 47
;
; 32-bit division on the ISS. This is the shape ordinary C `int` arithmetic
; produces, and it does NOT map to LVX's 32-bit DIVMODW/DIVMODUW: i32 is not a
; legal type in this back-end, so the type legalizer promotes to i64 and the
; operands are extended first -- sign-extended for sdiv/srem, zero-extended
; for udiv/urem -- before a 64-bit DIVMODD/DIVMODUD.
;
; That extension is load-bearing and is what this test checks. Sign-extending
; where zero-extension was needed (or vice versa) changes the answer only for
; operands whose bit 31 is set, so the negative and large-unsigned cases below
; are the ones that matter; the small positive case would pass either way.
;
; (Using DIVMODW/DIVMODUW directly would drop the extension instructions --
; an optimization left for later, not a correctness issue.)

@a  = global i32 -100
@b  = global i32 3
@ua = global i32 -1        ; 0xFFFFFFFF = 4294967295 unsigned
@ub = global i32 5

define i32 @main() {
entry:
  %av = load volatile i32, ptr @a
  %bv = load volatile i32, ptr @b
  %uav = load volatile i32, ptr @ua
  %ubv = load volatile i32, ptr @ub

  ; Signed, negative dividend: C truncates toward zero.
  ; -100 / 3 = -33, -100 % 3 = -1.
  %q1 = sdiv i32 %av, %bv
  %r1 = srem i32 %av, %bv
  %ok1 = icmp eq i32 %q1, -33
  %ok2 = icmp eq i32 %r1, -1
  %v1 = select i1 %ok1, i32 12, i32 0
  %v2 = select i1 %ok2, i32 12, i32 0

  ; Unsigned with bit 31 set: 4294967295 / 5 = 858993459, remainder 0.
  ; If the operand were sign-extended instead of zero-extended it would be
  ; -1, giving quotient 0 -- so this pins the extension choice.
  %q2 = udiv i32 %uav, %ubv
  %r2 = urem i32 %uav, %ubv
  %ok3 = icmp eq i32 %q2, 858993459
  %ok4 = icmp eq i32 %r2, 0
  %v3 = select i1 %ok3, i32 12, i32 0
  %v4 = select i1 %ok4, i32 11, i32 0

  %s1 = add i32 %v1, %v2
  %s2 = add i32 %s1, %v3
  %s3 = add i32 %s2, %v4
  ret i32 %s3                 ; 12 + 12 + 12 + 11 = 47
}
