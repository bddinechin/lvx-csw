# Native-x86 differential harness for the LVX toolchain.
#
#   make check                 # GCC front-end, -O2, micro-tests
#   make check FRONTEND=gcc OPT=0
#   make check TESTS='tests/micro/arith.c'
#
# Requires: lvx-mbr-* toolchain installed, lvx-gem5 built (build/LVX/gem5.opt).
# See README.md.

FRONTEND ?= gcc
OPT      ?= 2

.PHONY: check
check:
	@FRONTEND=$(FRONTEND) OPT=$(OPT) $(if $(TESTS),TESTS='$(TESTS)') ./run.sh
