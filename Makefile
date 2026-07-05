ROOT := $(CURDIR)
BUILD_DIR := $(ROOT)/lvx-mds/build_lvx
BINUTILS_BUILD_DIR := $(ROOT)/lvx-binutils-build

.PHONY: config all check refs install opcode clean binutils regress

# Run the first line of HOWTO (from lvx-mds/), pointing BE/GBU's install
# prefixes at the sibling toolchain checkouts so a plain "make all" here
# delivers generated files straight into lvx-binutils/lvx-gdb/lvx-gcc.
config:
	mkdir -p $(BUILD_DIR) && cd $(BUILD_DIR) && $(ROOT)/lvx-mds/lvx-family/configure --target=lvx \
	  --with-binutils-prefix=$(ROOT)/lvx-binutils \
	  --with-gdb-prefix=$(ROOT)/lvx-gdb \
	  --with-gcc-prefix=$(ROOT)/lvx-gcc \
	  --with-newlib-prefix=$(ROOT)/lvx-newlib

all check refs:
	$(MAKE) -C $(BUILD_DIR) $@

# Deliberately scoped to BE/GBU and BE/LIBC, not the blanket top-level
# "install" (which would also run BE/GDB/BE/GCC): those two back-ends'
# generated output has never been checked against the hand-maintained
# files it would overwrite (lvx-gdb/gdb/lvx-mds-tdep.c, lvx-gcc/gcc/config/
# lvx/*), and running it once already produced a confirmed regression
# (a stale KVX feature-name string reintroduced into lvx-mds-tdep.c) plus
# stray misplaced files in lvx-gcc. Revisit only after verifying those
# backends' output matches by hand first.
install:
	$(MAKE) -C $(BUILD_DIR)/BE/GBU install
	$(MAKE) -C $(BUILD_DIR)/BE/LIBC install

binutils:
	$(MAKE) -C $(BINUTILS_BUILD_DIR) all

# Full edit-YAML -> verify loop: rebuild lvx-mds, deliver BE/GBU's output
# into lvx-binutils/lvx-gdb, rebuild lvx-binutils against it, then diff
# every back-end's generated output (incl. testbin.pl/testasm.pl's
# per-core opcode tests) against the committed reference tree.
regress: all install binutils check

FAMILY := $(shell sed -n 's/^FAMILY:=[[:space:]]*//p' $(BUILD_DIR)/Makerules)
CORES  := $(shell sed -n 's/^CORES:=[[:space:]]*//p' $(BUILD_DIR)/Makerules)
OPCODE_TXT := $(addprefix $(FAMILY)/,$(addsuffix /Opcode.txt,$(CORES)))

opcode:
	rm -f $(addprefix $(BUILD_DIR)/FE/YAML/,$(OPCODE_TXT))
	$(MAKE) -C $(BUILD_DIR)/FE/YAML $(OPCODE_TXT)

clean:
	rm -rf $(BUILD_DIR)
