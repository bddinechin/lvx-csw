// 32-bit integer arithmetic feeding both kinds of widening, chosen so that
// sign- and zero-extension give *different* answers -- otherwise the test
// cannot tell the two apart and proves nothing about `-lvx-combine`'s
// signextw folding.
//
// With a = 0x7FFFFFFF, b = 1:
//
//   a + b  = 0x80000000   sign-extended -> -2147483648
//                         zero-extended ->  2147483648   (wrong)
//   a * b  = 0x7FFFFFFF   zero-extended ->  2147483647
//
//   sum = -1
//
// After -lvx-combine this is `addw.sx` (the sxwd folded into the modifier)
// and a bare `mulw` (the zxwd deleted, since bare already zero-extends).
func.func @wext(%a: i32, %b: i32) -> i64 {
  %0 = arith.addi %a, %b : i32
  %1 = arith.extsi %0 : i32 to i64
  %2 = arith.muli %a, %b : i32
  %3 = arith.extui %2 : i32 to i64
  %4 = arith.addi %1, %3 : i64
  return %4 : i64
}
