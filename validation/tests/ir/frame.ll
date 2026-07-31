; EXPECT: 47
;
; Regression test for the Frame Marker / local-object collision.
;
; emitPrologue lowers SP by AllocSize = StackSize + 16, adding the extra 16
; bytes at the BOTTOM of the frame, but writes the Frame Marker ($ra, caller
; FP) at the TOP -- just below the incoming SP. PEI hands out local offsets
; counting down from that same incoming SP, so the two locals nearest the top
; used to land exactly on the $ra and caller-FP slots. The failure mode is
; brutal and silent at compile time: a local store overwrites the saved $ra,
; the epilogue reloads it, and `ret` jumps to whatever the local held (here it
; would be a small integer, so execution faults near address 0).
;
; To hit it a function must (a) be non-leaf, so the marker exists at all, and
; (b) have live-across-the-call values that get spilled into the top local
; slots. At -O0 almost anything qualifies; at higher -O levels the values have
; to genuinely survive a call, which is what the interleaved calls below force.
; Run this at OPT=0 as well as the default -- -O0 is where it reproduces most
; reliably.

@g = global i64 3

define i64 @sink(i64 %x) noinline {
  %r = add i64 %x, 1
  ret i64 %r
}

define i32 @main() {
entry:
  %gv = load volatile i64, ptr @g

  ; Several values that must stay live across multiple calls, so they are
  ; spilled to the local slots that used to alias the marker.
  %a = add i64 %gv, 10          ; 13
  %b = add i64 %gv, 20          ; 23
  %c = add i64 %gv, 30          ; 33

  %r1 = call i64 @sink(i64 %a)  ; 14
  %r2 = call i64 @sink(i64 %b)  ; 24
  %r3 = call i64 @sink(i64 %c)  ; 34

  ; Use both the pre-call and post-call values, so none of them can be
  ; rematerialized instead of spilled.
  %s1 = add i64 %r1, %r2        ; 38
  %s2 = add i64 %s1, %r3        ; 72
  %s3 = add i64 %s2, %a         ; 85
  %s4 = add i64 %s3, %b         ; 108
  %s5 = add i64 %s4, %c         ; 141

  ; 141 / 3 = 47, computed without a division (no libgcc here).
  %ok = icmp eq i64 %s5, 141
  %r = select i1 %ok, i32 47, i32 1
  ret i32 %r
}
