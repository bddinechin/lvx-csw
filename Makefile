ROOT := $(CURDIR)
BUILD_DIR := $(ROOT)/lvx-mds/build_lvx

.PHONY: config all check refs opcode clean

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

FAMILY := $(shell sed -n 's/^FAMILY:=[[:space:]]*//p' $(BUILD_DIR)/Makerules)
CORES  := $(shell sed -n 's/^CORES:=[[:space:]]*//p' $(BUILD_DIR)/Makerules)
OPCODE_TXT := $(addprefix $(FAMILY)/,$(addsuffix /Opcode.txt,$(CORES)))

opcode:
	rm -f $(addprefix $(BUILD_DIR)/FE/YAML/,$(OPCODE_TXT))
	$(MAKE) -C $(BUILD_DIR)/FE/YAML $(OPCODE_TXT)

clean:
	rm -rf $(BUILD_DIR)
