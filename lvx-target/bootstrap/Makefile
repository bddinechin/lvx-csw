all: lvx_Opcode.txt lvx_Format.yml
	-

lvx_v1_opcode?= ../../lvx-mds/refs/FE/YAML/lvx/lvx_v1/Opcode.txt
lvx_v1_description?= ../../lvx-mds/refs/FE/YAML/lvx/lvx_v1/Description.yml

lvx_Opcode.txt lvx_formats.txt: $(lvx_v1_opcode)
	perl prune_opcode.pl < $< > $@

lvx_Format.yml: $(lvx_v1_description) lvx_formats.txt
	perl prune_format.pl < $< > $@

diff:
	diff -r . REF/

clean:
	rm -f lvx_Opcode.txt lvx_formats.txt lvx_Format.yml

