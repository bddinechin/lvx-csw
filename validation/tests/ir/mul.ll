; EXPECT: 47
;
; Executes multiplication on the ISS. This is the end-to-end counterpart to
; llvm/test/CodeGen/LVX/mul-highmult.ll: that one checks the *mnemonic*, this
; one checks the *value*, so a wrong highmult encoding shows up as a wrong
; answer even if the assembly looks plausible.
;
; LVX's MULD selects the low half of the product with highmult=3 (plain
; "muld") and the high half with 0/1/2 (".h"/".hu"/".hsu") -- inverted from
; KVX. The operands are chosen so low and high halves differ, so that a
; wrong modifier changes the answer rather than coinciding with it:
; %av * %av has low half 0xDCA5E20890F2A521 and high half 0x000014B7DA13B4EC.
;
; Note this file only exercises the LOW multiply (ISD::MUL). The high forms
; (mulhs/mulhu) are covered by llvm/test/CodeGen/LVX/mul-highmult.ll, and
; they are the ones that were actually mis-selected -- see that file. Keeping
; the value check here anyway guards the low path against a future one-sided
; fix to either the modifier table or the pattern constants, which would
; break the cancellation that used to make plain multiply work.
;
; `optnone`/`noinline` plus loads from a volatile-ish global keep the
; constant folder from evaluating the products at compile time, which would
; make the test vacuous.

@a = global i64 81985529216486895   ; 0x0123456789ABCDEF
@b = global i64 16                  ; 0x10
@s = global i64 -3
@t = global i64 7

define i32 @main() {
entry:
  %av = load volatile i64, ptr @a
  %bv = load volatile i64, ptr @b
  %sv = load volatile i64, ptr @s
  %tv = load volatile i64, ptr @t

  ; Low half of the 64-bit product must be 0x123456789ABCDEF0.
  %lo = mul i64 %av, %bv
  %ok1 = icmp eq i64 %lo, 1311768467463790320
  %v1 = select i1 %ok1, i32 10, i32 0

  ; Signed multiply with a negative operand: -3 * 7 = -21.
  %p2 = mul i64 %sv, %tv
  %ok2 = icmp eq i64 %p2, -21
  %v2 = select i1 %ok2, i32 10, i32 0

  ; A product whose high half is nonzero AND different from the low half,
  ; so neither half can be mistaken for the other by coincidence.
  %p3 = mul i64 %av, %av
  %ok3 = icmp eq i64 %p3, -2547381487788710623  ; low 64 bits of a*a (0xDCA5E20890F2A521)
  %v3 = select i1 %ok3, i32 10, i32 0

  ; Accumulating loop, so the product is consumed rather than compared
  ; directly: 5! = 120.
  %f = call i64 @fact(i64 5)
  %ok4 = icmp eq i64 %f, 120
  %v4 = select i1 %ok4, i32 17, i32 0

  %r1 = add i32 %v1, %v2
  %r2 = add i32 %r1, %v3
  %r3 = add i32 %r2, %v4
  ret i32 %r3
}

define i64 @fact(i64 %n) noinline {
entry:
  br label %loop
loop:
  %i = phi i64 [ 1, %entry ], [ %inext, %loop ]
  %acc = phi i64 [ 1, %entry ], [ %accnext, %loop ]
  %accnext = mul i64 %acc, %i
  %inext = add i64 %i, 1
  %done = icmp sgt i64 %inext, %n
  br i1 %done, label %exit, label %loop
exit:
  ret i64 %accnext
}
