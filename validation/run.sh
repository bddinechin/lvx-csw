#!/usr/bin/env bash
# Native-x86 differential harness — spine.
#
# For each test: build+run an x86 reference (the independent oracle), build+run
# the LVX ELF under gem5, and compare the framed result markers.  Everything
# after "produce an ELF" is shared across front-ends; swapping FRONTEND is the
# only difference between validating GCC, LLVM, or the MLIR path.
#
# Env:
#   FRONTEND  front-end adapter name in frontends/ (default: gcc)
#   OPT       optimization level for both sides (default: 2)
#   TESTS     glob of test .c files (default: tests/micro/*.c)
#   LVX_TOOLS GEM5 GEM5_CFG  paths (defaulted below to this checkout)
set -u

ROOT=$(cd "$(dirname "$0")" && pwd)
FRONTEND=${FRONTEND:-gcc}
OPT=${OPT:-2}
TESTS=${TESTS:-"$ROOT/tests/micro/*.c"}

export LVX_TOOLS=${LVX_TOOLS:-/home/bd3/lvx-csw/lvx-toolchain/bin}
export GEM5=${GEM5:-/home/bd3/lvx-csw/lvx-gem5/build/LVX/gem5.opt}
export GEM5_CFG=${GEM5_CFG:-/home/bd3/lvx-csw/lvx-gem5/tests/lvx/run_lvx.py}
export LIB_DIR="$ROOT/lib"

WD=$(mktemp -d)
trap 'rm -rf "$WD"' EXIT
FE="$ROOT/frontends/$FRONTEND.sh"
[ -x "$FE" ] || { echo "no front-end: $FE"; exit 2; }

marker() { echo "$1" | grep -E '^__LVXR__ ' | tail -1 | awk '{print $2}'; }

declare -A N=()
tap=0; total=0; fails=0
echo "TAP version 13"

for t in $TESTS; do
	[ -e "$t" ] || continue
	total=$((total+1)); tap=$((tap+1))
	name=$(basename "$t" .c)
	twd="$WD/$name"; mkdir -p "$twd"

	# --- x86 reference (the independent oracle) ---
	ref="$twd/ref"
	if ! cc -O"$OPT" -fno-strict-aliasing -fwrapv -I"$LIB_DIR" "$t" -o "$ref" 2>"$twd/cc.err"; then
		echo "not ok $tap - $name # SKIP x86 reference failed to build"
		N[SKIP]=$(( ${N[SKIP]:-0} + 1 )); continue
	fi
	ref_out=$("$ref"); ref_val=$(marker "$ref_out")

	# --- LVX build (staged; buckets on failure) ---
	if ! elf=$("$FE" "$t" "$twd" "$OPT"); then
		bucket=$elf
		echo "not ok $tap - $name # $bucket"
		N[$bucket]=$(( ${N[$bucket]:-0} + 1 )); fails=$((fails+1)); continue
	fi

	# --- LVX run under gem5 ---
	run_out=$("$ROOT/lib/run_lvx.sh" "$elf")
	lvx_val=$(marker "$run_out")
	run_stat=$(echo "$run_out" | grep -E '^__RUN__' | awk '{print $2}')

	if [ "$run_stat" = TIMEOUT ]; then
		echo "not ok $tap - $name # RUN_TIMEOUT"; N[RUN_TIMEOUT]=$(( ${N[RUN_TIMEOUT]:-0}+1 )); fails=$((fails+1)); continue
	fi
	if [ "$run_stat" = CRASH ]; then
		sig=$(echo "$run_out" | grep -E '^__RUN__ CRASH' | awk '{print $3}')
		echo "not ok $tap - $name # RUN_CRASH ($sig)"; N[RUN_CRASH]=$(( ${N[RUN_CRASH]:-0}+1 )); fails=$((fails+1)); continue
	fi
	if [ "$run_stat" = NOEXIT ]; then
		echo "not ok $tap - $name # RUN_NOEXIT"; N[RUN_NOEXIT]=$(( ${N[RUN_NOEXIT]:-0}+1 )); fails=$((fails+1)); continue
	fi
	if [ -z "$lvx_val" ]; then
		echo "not ok $tap - $name # RUN_NO_OUTPUT (x86=$ref_val)"; N[RUN_NO_OUTPUT]=$(( ${N[RUN_NO_OUTPUT]:-0}+1 )); fails=$((fails+1)); continue
	fi
	if [ "$lvx_val" != "$ref_val" ]; then
		echo "not ok $tap - $name # MISMATCH x86=$ref_val lvx=$lvx_val"; N[MISMATCH]=$(( ${N[MISMATCH]:-0}+1 )); fails=$((fails+1)); continue
	fi
	echo "ok $tap - $name (=$ref_val)"; N[PASS]=$(( ${N[PASS]:-0}+1 ))
done

echo "1..$tap"
echo "# ---- summary (FRONTEND=$FRONTEND OPT=$OPT) ----"
for k in PASS MISMATCH COMPILE_ICE COMPILE_FAIL ASSEMBLE_MISSING_INSN ASSEMBLE_FAIL CRT_FAIL LINK_FAIL RUN_CRASH RUN_TIMEOUT RUN_NOEXIT RUN_NO_OUTPUT SKIP; do
	[ -n "${N[$k]:-}" ] && printf '#   %-22s %d\n' "$k" "${N[$k]}"
done
printf '#   %-22s %d/%d\n' TOTAL "${N[PASS]:-0}" "$total"
[ "${fails:-0}" -eq 0 ]
