---
name: build-lvx-toolchain
description: Build, reconfigure, or debug the LVX cross-toolchain (binutils, GCC). Use when building or rebuilding lvx-binutils / lvx-gcc, reconfiguring a build directory from scratch, building only libgcc, or dumping the fully expanded GCC machine description (mddump) to debug .md pattern mismatches.
---

# Building the LVX cross-toolchain

All builds are out-of-tree. The installed toolchain lands in
`/home/bd3/lvx-csw/lvx-toolchain` with binaries prefixed `lvx-mbr-`.

## Binutils (must be built before GCC)

```bash
cd lvx-binutils-build
make -j$(nproc)
make install
```

To reconfigure from scratch:
```bash
mkdir lvx-binutils-build && cd lvx-binutils-build
../lvx-binutils/configure \
  --target=lvx-mbr \
  --prefix=/home/bd3/lvx-csw/lvx-toolchain \
  --enable-64-bit-bfd
make -j$(nproc) && make install
```

## GCC

```bash
cd lvx-gcc-build
make -j$(nproc)
make install
```

To reconfigure from scratch (requires binutils already installed):
```bash
mkdir lvx-gcc-build && cd lvx-gcc-build
../lvx-gcc/gcc/configure \
  --target=lvx-mbr \
  --prefix=/home/bd3/lvx-csw/lvx-toolchain \
  --disable-werror \
  --enable-languages=c,c++ \
  --without-headers \
  --disable-nls \
  --disable-shared \
  --disable-threads \
  --disable-libssp --disable-libgomp --disable-libquadmath \
  --enable-64-bit-bfd \
  --with-as=/home/bd3/lvx-csw/lvx-toolchain/bin/lvx-mbr-as \
  --with-ld=/home/bd3/lvx-csw/lvx-toolchain/bin/lvx-mbr-ld
make -j$(nproc) && make install
```

## GCC machine description debugging

To see the **fully expanded** RTL patterns (all iterators resolved, conditions
visible) for the current build:

```bash
make -C /home/bd3/lvx-csw/lvx-gcc-build/gcc mddump
# Output: /home/bd3/lvx-csw/lvx-gcc-build/gcc/tmp-mddump.md
```

This is the authoritative source for understanding which patterns are active and
how they expand. Use it when debugging mismatches between `.md` source and
generated assembly.

To build only libgcc (useful for testing the compiler without a full toolchain):

```bash
make -C /home/bd3/lvx-csw/lvx-gcc-build all-target-libgcc 2>&1 | grep -E 'Error:|error:|internal compiler'
```
