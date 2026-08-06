// 32-bit integer arithmetic feeding both kinds of widening, chosen so that
// sign- and zero-extension give *different* answers -- otherwise the test
// cannot tell the two apart and proves nothing about `-lvx-combine`'s
// signextw folding.
//
// With a = 0x7FFFFFFF, b = 1:
//
//   a + b   = 0x80000000   sign-extended -> -2147483648
//                          zero-extended ->  2147483648   (wrong)
//   a * b   = 0x7FFFFFFF   zero-extended ->  2147483647
//   ~a      = 0x80000000   sign-extended -> -2147483648
//   clz(b)  = 31           sign-extended ->  31
//
//   sum = -2147483618
//
// After -lvx-combine this is `addw.sx` and `notw.sx` (each sxwd folded into
// the modifier), a bare `mulw` (the zxwd deleted, since bare already
// zero-extends), and `clzw.sx`.
//
// The last two exercise the ALU_BWRW format specifically, which reserved the
// signextw encoding bit but never wired it into its operand list until
// 2026-08-05 -- so `notw.sx` was unencodable and this could not have been
// written before then.
func.func @wext(%a: i32, %b: i32) -> i64 {
  %cm1 = arith.constant -1 : i32

  %0 = arith.addi %a, %b : i32
  %1 = arith.extsi %0 : i32 to i64

  %2 = arith.muli %a, %b : i32
  %3 = arith.extui %2 : i32 to i64

  // MLIR spells bitwise complement as xor with all-ones; -lvx-combine turns
  // that into `notw`, which nothing else in the pipeline produces.
  %4 = arith.xori %a, %cm1 : i32
  %5 = arith.extsi %4 : i32 to i64

  %6 = math.ctlz %b : i32
  %7 = arith.extsi %6 : i32 to i64

  %8 = arith.addi %1, %3 : i64
  %9 = arith.addi %8, %5 : i64
  %10 = arith.addi %9, %7 : i64
  return %10 : i64
}
