#!/usr/bin/env bash
# GCC front-end adapter: build an lvx-mbr ELF from a C test, in stages so a
# failure buckets cleanly.  With the LVX GCC port unfinished (and LVX missing
# some KVX instructions), "does it build" is most of the early signal, so we
# separate the compiler frontend/codegen (C -> asm) from the assembler
# (asm -> obj, where a missing/unsupported instruction shows up) from the link.
#
# Usage:  gcc.sh <test.c> <workdir> <opt-level>
# On success: prints the ELF path, exits 0.
# On failure: prints ONE bucket keyword, exits 1.
set -u

T=$1; WD=$2; OPT=$3
LVX=${LVX_TOOLS:?set LVX_TOOLS}
LIB=${LIB_DIR:?set LIB_DIR}
GCC="$LVX/lvx-mbr-gcc"
AS="$LVX/lvx-mbr-as"
LD="$LVX/lvx-mbr-ld"
CFLAGS="-O$OPT -march=lvx-1 -ffreestanding -fno-strict-aliasing -fwrapv -I$LIB"
base="$WD/$(basename "$T" .c)"

# 1. C -> asm.  An ICE here is a compiler bug (see lvx-newlib CLAUDE.md clusters).
if ! err=$("$GCC" $CFLAGS -S "$T" -o "$base.s" 2>&1); then
	echo "$err" | grep -qi "internal compiler error" && { echo COMPILE_ICE; exit 1; }
	echo COMPILE_FAIL; exit 1
fi

# 2. asm -> obj.  "expected one of"/"unrecognized" = instruction the assembler
#    (hence the ISA) does not provide — the KVX-vs-LVX gap the caveat names.
if ! err=$("$GCC" $CFLAGS -c "$base.s" -o "$base.o" 2>&1); then
	echo "$err" | grep -qiE "Unexpected token when parsing|Did you mean|expected one of|unrecognized|bad instruction|no match|Error:.*Instruction" \
		&& { echo ASSEMBLE_MISSING_INSN; exit 1; }
	echo ASSEMBLE_FAIL; exit 1
fi

# crt (freestanding runtime) — assembled fresh each time; cheap.
if ! err=$("$AS" "$LIB/crt.S" -o "$WD/crt.o" 2>&1); then
	echo CRT_FAIL; exit 1
fi

# 3. link, mirroring the verified milestone recipe.
if ! err=$("$LD" -e _start -Ttext=0x10000 -nostdlib "$WD/crt.o" "$base.o" -o "$base.elf" 2>&1); then
	echo LINK_FAIL; exit 1
fi

echo "$base.elf"
