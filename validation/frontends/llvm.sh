#!/usr/bin/env bash
# LLVM front-end adapter: build an lvx-mbr ELF from a C test, in stages so a
# failure buckets cleanly.  Same contract as gcc.sh:
#
#   llvm.sh <test.c> <workdir> <opt-level>
#     success: prints the ELF path, exits 0
#     failure: prints ONE bucket keyword, exits 1
#
# The LVX back-end has no clang driver support and no MCCodeEmitter/integrated
# assembler yet -- it is registered as RegisterTarget<Triple::UnknownArch>
# under the name "lvx" and emits *text* assembly, which GNU as then encodes.
# So the pipeline has one more stage than gcc.sh:
#
#   C --clang--> LLVM IR --llc -mtriple=lvx--> .s --lvx-mbr-as--> .o --ld--> ELF
#
# clang generates the IR for riscv64-unknown-elf, not for LVX.  That is
# deliberate and it is exactly equivalent at the IR level, because LVX's data
# layout string (LVXTargetMachine.cpp) is the RV64 one verbatim --
# "e-m:e-p:64:64-i64:64-i128:128-n32:64-S128" -- so the module llc consumes
# already has LVX's own layout: LP64, little-endian, same integer sizes and
# alignments.  Picking a mismatched host triple (e.g. x86_64) instead would
# make llc silently re-lay-out the module.
#
# -D__lvx__=1 is passed by hand because clang has no LVX target to predefine
# it, and lib/harness.h switches on it to pick crt.S's freestanding
# scall-based write(2) over a hosted <unistd.h> one.
set -u

T=$1; WD=$2; OPT=$3
LVX=${LVX_TOOLS:?set LVX_TOOLS}
LIB=${LIB_DIR:?set LIB_DIR}
LLVM_BIN=${LLVM_BIN:?set LLVM_BIN (llvm-project build bin/ with clang and llc)}
CLANG="$LLVM_BIN/clang"
LLC="$LLVM_BIN/llc"
AS="$LVX/lvx-mbr-as"
LD="$LVX/lvx-mbr-ld"
base="$WD/$(basename "$T" .c)"

CFLAGS="-O$OPT --target=riscv64-unknown-elf -ffreestanding -fno-strict-aliasing
        -fwrapv -fno-builtin -D__lvx__=1 -I$LIB"

# 1. C -> LLVM IR.  Failures here are clang front-end problems, not LVX
#    back-end ones (nothing LVX-specific has run yet), so they bucket as
#    COMPILE_FAIL / COMPILE_ICE just like gcc.sh's stage 1.
if ! err=$("$CLANG" $CFLAGS -S -emit-llvm "$T" -o "$base.ll" 2>&1); then
	echo "$err" | grep -qiE "internal compiler error|PLEASE submit a bug report" \
		&& { echo COMPILE_ICE; exit 1; }
	echo COMPILE_FAIL; exit 1
fi

# 2. LLVM IR -> LVX assembly.  This is the stage under test: an unselectable
#    DAG node ("Cannot select"), a missing pattern, or an assertion in the LVX
#    lowering all land here.  LLVM reports its own crashes with a stack trace
#    header rather than the words "internal compiler error".
if ! err=$("$LLC" -mtriple=lvx -O"$OPT" "$base.ll" -o "$base.s" 2>&1); then
	echo "$err" | grep -qiE "PLEASE submit a bug report|Assertion.*failed|UNREACHABLE executed|Stack dump" \
		&& { echo COMPILE_ICE; exit 1; }
	echo "$err" | grep -qiE "Cannot select|unable to legalize|LLVM ERROR" \
		&& { echo COMPILE_FAIL; exit 1; }
	echo COMPILE_FAIL; exit 1
fi

# 3. asm -> obj.  Same bucketing as gcc.sh: a mnemonic/operand form the
#    assembler rejects means the back-end emitted something the ISA does not
#    have -- the signal this harness exists to surface.
if ! err=$("$AS" "$base.s" -o "$base.o" 2>&1); then
	echo "$err" | grep -qiE "Unexpected token when parsing|Did you mean|expected one of|unrecognized|bad instruction|no match|Error:.*Instruction" \
		&& { echo ASSEMBLE_MISSING_INSN; exit 1; }
	echo ASSEMBLE_FAIL; exit 1
fi

if ! err=$("$AS" "$LIB/crt.S" -o "$WD/crt.o" 2>&1); then
	echo CRT_FAIL; exit 1
fi

# 4. link, mirroring gcc.sh's verified recipe.
if ! err=$("$LD" -e _start -Ttext=0x10000 -nostdlib "$WD/crt.o" "$base.o" -o "$base.elf" 2>&1); then
	echo LINK_FAIL; exit 1
fi

echo "$base.elf"
