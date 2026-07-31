#!/usr/bin/env bash
# Execution tests driven from hand-written LLVM IR, run on the gem5 ISS.
#
# Why this exists alongside run.sh: run.sh's oracle is "the same C compiled
# natively", which needs a C front-end, and building clang costs ~3x what
# building llc does. This path needs only llc, so the LVX back-end can be
# executed and checked against expected values long before clang is ready.
# It is a weaker oracle than run.sh's -- the expected value is written by
# hand rather than derived from an independent compiler -- so it complements
# the native-x86 differential harness rather than replacing it. Use it to
# pin specific instruction selections; use run.sh for broad correctness.
#
# Each test is a .ll defining `i32 @main()` and carrying one line
#   ; EXPECT: <n>
# with 0 <= n <= 255 (the value arrives as the process exit status, which
# crt.S takes from main()'s return in $r0).
#
# Env: LLVM_BIN LVX_TOOLS GEM5 GEM5_CFG (all defaulted from this checkout)
set -u

ROOT=$(cd "$(dirname "$0")" && pwd)
CSW=$(cd "$ROOT/.." && pwd)
OPT=${OPT:-2}
TESTS=${TESTS:-"$ROOT/tests/ir/*.ll"}

LLVM_BIN=${LLVM_BIN:-$CSW/lvx-llvm/llvm-project/build/bin}
LVX_TOOLS=${LVX_TOOLS:-$CSW/lvx-toolchain/bin}
export GEM5=${GEM5:-$CSW/lvx-gem5/build/gem5-lvx1.opt}
export GEM5_CFG=${GEM5_CFG:-$CSW/lvx-gem5/tests/lvx/run_lvx.py}

LLC="$LLVM_BIN/llc"
AS="$LVX_TOOLS/lvx-mbr-as"
LD="$LVX_TOOLS/lvx-mbr-ld"
for t in "$LLC" "$AS" "$LD" "$GEM5"; do
	[ -x "$t" ] || { echo "missing tool: $t" >&2; exit 2; }
done

WD=$(mktemp -d); trap 'rm -rf "$WD"' EXIT
"$AS" "$ROOT/lib/crt.S" -o "$WD/crt.o" || { echo "crt.S failed to assemble" >&2; exit 2; }

tap=0; fails=0
echo "TAP version 13"
for t in $TESTS; do
	[ -e "$t" ] || continue
	tap=$((tap+1))
	name=$(basename "$t" .ll)
	want=$(sed -n 's/^;[[:space:]]*EXPECT:[[:space:]]*\([0-9]\{1,\}\).*/\1/p' "$t" | head -1)
	if [ -z "$want" ]; then
		echo "not ok $tap - $name # NO_EXPECT (add '; EXPECT: <n>')"; fails=$((fails+1)); continue
	fi
	b="$WD/$name"

	if ! err=$("$LLC" -mtriple=lvx -O"$OPT" "$t" -o "$b.s" 2>&1); then
		echo "not ok $tap - $name # LLC_FAIL"
		echo "$err" | sed 's/^/#   /' | head -6
		fails=$((fails+1)); continue
	fi
	if ! err=$("$AS" "$b.s" -o "$b.o" 2>&1); then
		echo "not ok $tap - $name # ASSEMBLE_FAIL"
		echo "$err" | sed 's/^/#   /' | head -6
		fails=$((fails+1)); continue
	fi
	if ! err=$("$LD" -e _start -Ttext=0x10000 -nostdlib "$WD/crt.o" "$b.o" -o "$b.elf" 2>&1); then
		echo "not ok $tap - $name # LINK_FAIL"
		echo "$err" | sed 's/^/#   /' | head -6
		fails=$((fails+1)); continue
	fi

	run_out=$("$ROOT/lib/run_lvx.sh" "$b.elf")
	stat=$(echo "$run_out" | grep -E '^__RUN__' | awk '{print $2}')
	got=$(echo "$run_out" | grep -E '^__RUN__ EXIT' | awk '{print $3}')

	case "$stat" in
	EXIT)
		if [ "$got" = "$want" ]; then
			echo "ok $tap - $name (=$got)"
		else
			echo "not ok $tap - $name # MISMATCH want=$want got=$got"; fails=$((fails+1))
		fi ;;
	CRASH)
		sig=$(echo "$run_out" | grep -E '^__RUN__ CRASH' | awk '{print $3}')
		echo "not ok $tap - $name # RUN_CRASH ($sig)"; fails=$((fails+1)) ;;
	TIMEOUT) echo "not ok $tap - $name # RUN_TIMEOUT"; fails=$((fails+1)) ;;
	*)       echo "not ok $tap - $name # RUN_NOEXIT"; fails=$((fails+1)) ;;
	esac
done

echo "1..$tap"
printf '# %d/%d passed (OPT=%s)\n' "$((tap-fails))" "$tap" "$OPT"
[ "$fails" -eq 0 ]
