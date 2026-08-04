---
name: build-lvx-toolchain
description: Build, reconfigure, or debug the LVX cross-toolchain (binutils, GCC). Use when building or rebuilding lvx-binutils / lvx-gcc, reconfiguring a build directory from scratch, configuring a second compiler with RTL/tree checking to diagnose an ICE, building only libgcc, or dumping the fully expanded GCC machine description (mddump) to debug .md pattern mismatches.
---

# Building the LVX cross-toolchain

All builds are out-of-tree, in build directories at the **superproject root**
(`lvx-binutils-build/`, `lvx-gcc-build/`, …). The installed toolchain lands in
`lvx-toolchain/` with binaries prefixed `lvx-mbr-`.

## Paths: never hardcode an absolute one

This checkout lives at a different absolute path on each machine
(`/home/bd3/lvx-csw` on one, `/home/guembu/bd3/lvx-csw` on another), so every
path below is **relative to the superproject root** — run these from there.

Where a command genuinely needs an absolute path (`--prefix`, `--with-as`,
`--with-ld`), derive it instead of writing it:

```bash
CSW=$(git rev-parse --show-superproject-working-tree 2>/dev/null)
[ -z "$CSW" ] && CSW=$(git rev-parse --show-toplevel)
```

Both lines are needed: `--show-toplevel` alone returns the *submodule* root when
run from inside one (`lvx-mds`, `lvx-gdb`, `lvx-gcc/gcc`, …), while
`--show-superproject-working-tree` returns the right answer there but prints
nothing (exit 0) at the superproject itself.

`$CLAUDE_PROJECT_DIR` is **not** available to shell commands — it reaches hooks
only. Don't reach for it.

## Binutils (must be built before GCC)

```bash
make -C lvx-binutils-build -j$(nproc)
make -C lvx-binutils-build install
```

To reconfigure from scratch:
```bash
CSW=$(git rev-parse --show-superproject-working-tree 2>/dev/null)
[ -z "$CSW" ] && CSW=$(git rev-parse --show-toplevel)

mkdir -p lvx-binutils-build && cd lvx-binutils-build
../lvx-binutils/configure \
  --target=lvx-mbr \
  --prefix=$CSW/lvx-toolchain \
  --enable-64-bit-bfd
make -j$(nproc) && make install
```

## GCC

The GCC source is the **`lvx-gcc/gcc/` submodule** — a fork of gcc-mirror/gcc on
branch `lvx-gcc`, not the `lvx-gcc/` directory itself (which also holds
`CLAUDE.md`). Requires binutils installed first.

```bash
make -C lvx-gcc-build -j$(nproc)
make -C lvx-gcc-build install
```

To reconfigure from scratch:
```bash
CSW=$(git rev-parse --show-superproject-working-tree 2>/dev/null)
[ -z "$CSW" ] && CSW=$(git rev-parse --show-toplevel)

mkdir -p lvx-gcc-build && cd lvx-gcc-build
../lvx-gcc/gcc/configure \
  --target=lvx-mbr \
  --prefix=$CSW/lvx-toolchain \
  --disable-werror \
  --enable-languages=c \
  --without-headers \
  --disable-nls \
  --disable-shared \
  --disable-threads \
  --disable-libssp --disable-libgomp --disable-libquadmath \
  --with-as=$CSW/lvx-toolchain/bin/lvx-mbr-as \
  --with-ld=$CSW/lvx-toolchain/bin/lvx-mbr-ld
make -j$(nproc) && make install
```

Prerequisites are taken from the system (`libgmp-dev`, `libmpfr-dev`,
`libmpc-dev`); there is no in-tree gmp/mpfr/mpc. On Debian/Ubuntu `gmp.h` lives
under `/usr/include/x86_64-linux-gnu/`, which configure finds on its own — a
missing `/usr/include/gmp.h` is not the problem it looks like.

`--enable-languages=c` is the default build. C++ is only needed to reach the
vector ternary (`c ? a : b` on vector types is C++-only); `lvx-gcc-build-cxx` is
a second build dir with `c,c++` for that, where `make all-gcc` suffices.

## A second compiler with RTL checking, to diagnose an ICE

A segfault gives a stack but no diagnosis. RTL checking turns the same crash
into `RTL check: expected code 'reg', have 'zero_extract' in rhs_regno, at
rtl.h:1950`, which names the fault outright. Configure exactly as above but add:

```bash
  --enable-checking=yes,rtl,extra,tree,gc
```

Verify it actually took effect — the option string in `config.log` is not proof
(a `--enable-checking=release` default also appears there):

```bash
grep -E "ENABLE_(RTL|TREE|GC|EXTRA)" lvx-gcc-build/gcc/auto-host.h
# expect ENABLE_RTL_CHECKING, ENABLE_RTL_FLAG_CHECKING,
#        ENABLE_TREE_CHECKING, ENABLE_GC_CHECKING, ENABLE_EXTRA_CHECKING
```

A checked compiler is markedly slower. `lvx-gcc/CLAUDE.md` recommends keeping it
in a **separate** build dir with a throwaway `--prefix`, so the installed
toolchain and the `run_diff.sh` harness baseline stay untouched.

## GCC machine description debugging

To see the **fully expanded** RTL patterns (all iterators resolved, conditions
visible) for the current build:

```bash
make -C lvx-gcc-build/gcc mddump
# Output: lvx-gcc-build/gcc/tmp-mddump.md
```

This is the authoritative source for understanding which patterns are active and
how they expand. Use it when debugging mismatches between `.md` source and
generated assembly.

To build only libgcc (useful for testing the compiler without a full toolchain):

```bash
make -C lvx-gcc-build all-target-libgcc 2>&1 | grep -E 'Error:|error:|internal compiler'
```
