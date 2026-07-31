; EXPECT: 47
;
; Outgoing/incoming stack arguments. LVX's calling convention passes the
; first twelve 64-bit slots in R0-R11 (lvx-refs Convention.table
; "argument=" list); anything beyond that goes through the Outgoing
; Arguments region at the bottom of the caller's frame, and the callee reads
; it relative to its own incoming SP.
;
; This is the other half of the Frame Marker fix in
; LVXRegisterInfo::eliminateFrameIndex. Locals are shifted down by the
; 16-byte marker so the locals region ends where the marker begins -- which
; also puts PEI's outgoing-argument area, folded into the bottom of the local
; frame, at exactly SP+0 where the callee expects it. Fixed objects (the
; callee's incoming args, above its incoming SP) are deliberately not
; shifted. Getting either half wrong misplaces arguments by 16 bytes, so a
; callee with more than twelve parameters reads garbage.
;
; 16 parameters => four of them (the 13th..16th) travel on the stack.
;
; History worth keeping: this used to fail at -O1 and above with
;
;   *** Bad machine code: Using an undefined physical register ***
;   - instruction: RET implicit killed $ra, implicit killed $r0
;
; because CALL carries "implicit-def dead $ra", so no def of $ra reached a RET
; that EmitInstrWithCustomInserter had spliced into a select-diamond's sink
; block. It went away when LVXInstrInfo gained analyzeBranch/insertBranch/
; removeBranch: with those in place the CFG passes can lay the diamond out so
; that PEI's epilogue -- which is what actually redefines $ra -- ends up in the
; same block as the return.
;
; So the $ra modelling is still hand-rolled (GETRA/SETRA in the Frame Marker
; code rather than PEI's callee-saved machinery, per the carve-out in
; LVXCallingConv.td's CSR_LVX) and is only *incidentally* consistent now.
; If this test starts failing that way again, that carve-out is where to look.
; Note also that declaring $ra live-in on the entry block is NOT the fix --
; it was tried and makes every function fail the verifier instead.

define i64 @many(i64 %a0, i64 %a1, i64 %a2, i64 %a3,
                 i64 %a4, i64 %a5, i64 %a6, i64 %a7,
                 i64 %a8, i64 %a9, i64 %a10, i64 %a11,
                 i64 %a12, i64 %a13, i64 %a14, i64 %a15) noinline {
  ; Sum only the stack-passed tail, so a misplaced outgoing-argument area
  ; shows up as a wrong total rather than being masked by the register args.
  %s0 = add i64 %a12, %a13
  %s1 = add i64 %s0, %a14
  %s2 = add i64 %s1, %a15
  ret i64 %s2                      ; 13 + 14 + 15 + 16 = 58
}

define i32 @main() {
entry:
  %t = call i64 @many(i64 1, i64 2, i64 3, i64 4,
                      i64 5, i64 6, i64 7, i64 8,
                      i64 9, i64 10, i64 11, i64 12,
                      i64 13, i64 14, i64 15, i64 16)
  %ok = icmp eq i64 %t, 58
  %r = select i1 %ok, i32 47, i32 1
  ret i32 %r
}
