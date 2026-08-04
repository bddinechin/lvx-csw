; EXPECT: 47
;
; Which of LVX's two min/max instructions is which, decided on the ISS rather
; than by reading the description.
;
; LVX has both IEEE families, and nothing but a NaN can tell them apart:
;
;   fminn  (helper f64_minNum)  754-2008 minNum   -- returns the NUMERIC operand
;   fmin   (helper f64_min)     754-2019 minimum  -- PROPAGATES the NaN
;
; Every non-NaN input gives the same answer from both, which is exactly why a
; wrong pairing survives ordinary testing. This file feeds each one a NaN and
; checks which behaviour comes back, so the two instructions are distinguished
; by what the hardware does rather than by what their mnemonics suggest --
; "fmind" is NOT the one C's fmin() needs.
;
; That distinction is not academic here: lvx-gcc's fmindf3 emits `fmind` for
; C's fmin, which is the propagating one, so fmin(NaN, 1.5) returns NaN there
; instead of 1.5. This test pins the LLVM side against the same ISS, so the
; two compilers can be compared on identical hardware behaviour.

declare double @llvm.minnum.f64(double, double)
declare double @llvm.maxnum.f64(double, double)
declare double @llvm.minimum.f64(double, double)
declare double @llvm.maximum.f64(double, double)

@nan = global double 0x7FF8000000000000
@val = global double 1.5

define i32 @main() {
  %n = load volatile double, ptr @nan
  %v = load volatile double, ptr @val

  ; minNum: the NaN is discarded, both ways round.
  %a = call double @llvm.minnum.f64(double %n, double %v)
  %ao = fcmp oeq double %a, 1.5
  %as = select i1 %ao, i32 8, i32 0

  %b = call double @llvm.minnum.f64(double %v, double %n)
  %bo = fcmp oeq double %b, 1.5
  %bs = select i1 %bo, i32 8, i32 0

  %c = call double @llvm.maxnum.f64(double %n, double %v)
  %co = fcmp oeq double %c, 1.5
  %cs = select i1 %co, i32 8, i32 0

  ; minimum/maximum: the NaN wins, so the result compares unordered against
  ; everything -- including itself, which is the portable way to spot a NaN.
  %d = call double @llvm.minimum.f64(double %n, double %v)
  %du = fcmp uno double %d, %d
  %ds = select i1 %du, i32 8, i32 0

  %e = call double @llvm.maximum.f64(double %n, double %v)
  %eu = fcmp uno double %e, %e
  %es = select i1 %eu, i32 8, i32 0

  ; And with no NaN in sight the two families agree, which is the property
  ; that lets a wrong pairing hide.
  %f = call double @llvm.minimum.f64(double %v, double %v)
  %fo = fcmp oeq double %f, 1.5
  %fs = select i1 %fo, i32 7, i32 0

  %s1 = add i32 %as, %bs
  %s2 = add i32 %s1, %cs
  %s3 = add i32 %s2, %ds
  %s4 = add i32 %s3, %es
  %s5 = add i32 %s4, %fs
  ret i32 %s5                      ; 8*5 + 7 = 47
}
