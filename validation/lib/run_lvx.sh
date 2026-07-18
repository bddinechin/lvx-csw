#!/usr/bin/env bash
# Run an LVX ELF under gem5 SE mode and distill the result to two lines:
#   __LVXR__ <n>        the guest's framed stdout marker (from harness_report)
#   __RUN__ EXIT <code> | __RUN__ TIMEOUT | __RUN__ NOEXIT
#
# Reuses lvx-gem5's own verified run config (tests/lvx/run_lvx.py), which prints
# "... target exited (code=N) ...".  The guest's write(2) goes to the real host
# stdout, so its marker appears in gem5's captured output.
set -u

elf=$1
GEM5=${GEM5:?set GEM5}
CFG=${GEM5_CFG:?set GEM5_CFG}
TIMEOUT=${LVX_TIMEOUT:-30}

out=$(timeout "$TIMEOUT" "$GEM5" --outdir="$(dirname "$elf")/m5out" "$CFG" "$elf" 2>&1)
status=$?

echo "$out" | grep -E '^__LVXR__ ' | tail -1

if [ "$status" -eq 124 ]; then
	echo "__RUN__ TIMEOUT"
elif echo "$out" | grep -q "target exited"; then
	code=$(echo "$out" | sed -n 's/.*code=\(-\{0,1\}[0-9]\{1,\}\).*/\1/p' | tail -1)
	echo "__RUN__ EXIT ${code:-?}"
elif [ "$status" -ge 128 ]; then
	# gem5 itself died on a signal (SIGILL from a panic stub / unimplemented
	# opcode, SIGSEGV, etc.) — an ISS bug, not the guest exiting.
	echo "__RUN__ CRASH sig$((status - 128))"
else
	echo "__RUN__ NOEXIT"
fi
