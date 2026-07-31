; EXPECT: 47
;
; Hardware divide/remainder via DIVMODD / DIVMODUD.
;
; These instructions compute quotient AND remainder in one shot into a 128-bit
; register pair, so ISD::SDIVREM/UDIVREM are Legal and hand-selected in
; LVXISelDAGToDAG; the single-result SDIV/UDIV/SREM/UREM are Expand and the
; legalizer routes them through the same node, keeping result 0 or 1.
;
; Two things here are easy to get backwards and are invisible in the assembly,
; which is why this test checks values on the ISS rather than mnemonics:
;
;   1. Which half is which. Description.yml: "result1.64[0] = dividend /
;      divisor; result1.64[1] = dividend % divisor", and .64[0] is the
;      architecturally LOW half of the pair (subregister index sub_hi, offset
;      0, the even-numbered GPR). Swapping the two exchanges "/" and "%" --
;      and for many operand pairs both results are plausible-looking numbers.
;   2. Operand order. ALU_DDMWRR_Inst is "(ins GPR:$rY, GPR:$rZ)" printed as
;      "$rM = $rZ, $rY", with $rZ the dividend -- so the machine node takes
;      (divisor, dividend), the reverse of the assembly's reading order.
;
; Every divisor below is loaded through a volatile global so nothing is
; strength-reduced into a reciprocal multiply; these must be real DIVMODs.
; The values are deliberately asymmetric (quotient != remainder, and a/b !=
; b/a) so a swap cannot coincidentally still produce 47.

@a = global i64 100
@b = global i64 7
@n = global i64 -100
@m = global i64 3
@u = global i64 18446744073709551615   ; 2^64-1, negative if read as signed

define i32 @main() {
entry:
  %av = load volatile i64, ptr @a
  %bv = load volatile i64, ptr @b
  %nv = load volatile i64, ptr @n
  %mv = load volatile i64, ptr @m
  %uv = load volatile i64, ptr @u

  ; 100 / 7 = 14, 100 % 7 = 2  -- quotient and remainder clearly distinct.
  %q1 = sdiv i64 %av, %bv
  %r1 = srem i64 %av, %bv
  %ok1 = icmp eq i64 %q1, 14
  %ok2 = icmp eq i64 %r1, 2
  %v1 = select i1 %ok1, i32 8, i32 0
  %v2 = select i1 %ok2, i32 8, i32 0

  ; Reversed operands: 7 / 100 = 0, 7 % 100 = 7. Catches a dividend/divisor
  ; swap, which the case above cannot (both orders give nonzero results).
  %q2 = sdiv i64 %bv, %av
  %r2 = srem i64 %bv, %av
  %ok3 = icmp eq i64 %q2, 0
  %ok4 = icmp eq i64 %r2, 7
  %v3 = select i1 %ok3, i32 8, i32 0
  %v4 = select i1 %ok4, i32 8, i32 0

  ; Signed with a negative dividend: C truncates toward zero, so
  ; -100 / 3 = -33 and -100 % 3 = -1.
  %q3 = sdiv i64 %nv, %mv
  %r3 = srem i64 %nv, %mv
  %ok5 = icmp eq i64 %q3, -33
  %ok6 = icmp eq i64 %r3, -1
  %v5 = select i1 %ok5, i32 5, i32 0
  %v6 = select i1 %ok6, i32 5, i32 0

  ; Unsigned must NOT sign-extend: (2^64-1) / 3 = 6148914691236517205.
  ; Selecting DIVMODD here instead of DIVMODUD gives 0, so this pins the
  ; signed/unsigned opcode choice.
  %q4 = udiv i64 %uv, %mv
  %ok7 = icmp eq i64 %q4, 6148914691236517205
  %v7 = select i1 %ok7, i32 5, i32 0

  %s1 = add i32 %v1, %v2
  %s2 = add i32 %s1, %v3
  %s3 = add i32 %s2, %v4
  %s4 = add i32 %s3, %v5
  %s5 = add i32 %s4, %v6
  %s6 = add i32 %s5, %v7
  ret i32 %s6                        ; 8*4 + 5*3 = 47
}
