; EXPECT: 47
;
; Scalar integer ALU, comparisons and control flow -- the operations the LVX
; back-end has real patterns for today. Deliberately avoids sdiv/udiv/srem/
; urem: LVXTargetLowering marks those Expand, so they become __divdi3-style
; libcalls with no libgcc to link against on this freestanding target.
;
; Subtraction is the interesting case for ISA conformance. LVX's SBFD is
; "Subtract From": Description.yml annotates '%2': Right / '%3': Left and
; computes "result1 = argument3 - argument2", so `sbfd $rW = $rZ, $rY` is
; rY - rZ, not rZ - rY. Getting the printed operand order wrong negates every
; subtraction, which is why several checks below are asymmetric (a-b and b-a
; both appear, with different expected values).

@x = global i64 100
@y = global i64 37

define i32 @main() {
entry:
  %a = load volatile i64, ptr @x
  %b = load volatile i64, ptr @y

  ; add / sub, both orders (catches an inverted SBFD)
  %add = add i64 %a, %b                  ; 137
  %ok1 = icmp eq i64 %add, 137
  %v1 = select i1 %ok1, i32 5, i32 0

  %sub = sub i64 %a, %b                  ; 63
  %ok2 = icmp eq i64 %sub, 63
  %v2 = select i1 %ok2, i32 5, i32 0

  %rsub = sub i64 %b, %a                 ; -63
  %ok3 = icmp eq i64 %rsub, -63
  %v3 = select i1 %ok3, i32 5, i32 0

  ; immediate forms (ADDD_i / SBFD_i embed a signed10)
  %addi = add i64 %a, 5                  ; 105
  %ok4 = icmp eq i64 %addi, 105
  %v4 = select i1 %ok4, i32 5, i32 0

  %subi = sub i64 200, %a                ; 100
  %ok5 = icmp eq i64 %subi, 100
  %v5 = select i1 %ok5, i32 5, i32 0

  ; bitwise
  %and = and i64 %a, %b                  ; 100 & 37 = 36
  %or  = or  i64 %a, %b                  ; 101
  %xor = xor i64 %a, %b                  ; 65
  %ok6 = icmp eq i64 %and, 36
  %ok7 = icmp eq i64 %or, 101
  %ok8 = icmp eq i64 %xor, 65
  %v6 = select i1 %ok6, i32 4, i32 0
  %v7 = select i1 %ok7, i32 4, i32 0
  %v8 = select i1 %ok8, i32 4, i32 0

  ; shifts
  %shl = shl  i64 %a, 3                  ; 800
  %sra = ashr i64 %rsub, 2               ; -63 >> 2 = -16 (arithmetic)
  %srl = lshr i64 %a, 2                  ; 25
  %ok9  = icmp eq i64 %shl, 800
  %ok10 = icmp eq i64 %sra, -16
  %ok11 = icmp eq i64 %srl, 25
  %v9  = select i1 %ok9,  i32 4, i32 0
  %v10 = select i1 %ok10, i32 3, i32 0
  %v11 = select i1 %ok11, i32 3, i32 0

  %s1 = add i32 %v1, %v2
  %s2 = add i32 %s1, %v3
  %s3 = add i32 %s2, %v4
  %s4 = add i32 %s3, %v5
  %s5 = add i32 %s4, %v6
  %s6 = add i32 %s5, %v7
  %s7 = add i32 %s6, %v8
  %s8 = add i32 %s7, %v9
  %s9 = add i32 %s8, %v10
  %s10 = add i32 %s9, %v11
  ret i32 %s10                            ; 5*5 + 4*3 + 4 + 3 + 3 = 47
}
