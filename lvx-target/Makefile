# Build readable PDFs from the LVX specification sources.
#
#   make            -> build/<name>.pdf for every *.tex here
#   make clean      -> remove build/
#   make show       -> list what would be built, and where the inputs come from
#
# The .tex files here are deliberately *fragments*: each starts at
# \section{...} with no \documentclass, so it can be \input into a larger
# document. That is what makes them reusable as LaTeX snippets -- copy a
# subsection straight out -- but it also means they cannot be compiled on
# their own. This Makefile wraps each one in a minimal document *in build/*,
# leaving the sources untouched.
#
# They also \input three MDS-generated tables (Convention-regular, DwarfId,
# Relocation) that live in the sibling lvx-mds repo, so the PDFs carry the
# real machine-generated ABI/DWARF/relocation tables rather than a
# transcription. TEXINPUTS below is what makes those resolve; without it
# LaTeX reports a missing file for each.

# Derive the superproject root rather than hardcoding it: this checkout sits
# at a different absolute path on each machine.
CSW := $(shell git rev-parse --show-superproject-working-tree 2>/dev/null)
ifeq ($(CSW),)
CSW := $(shell git rev-parse --show-toplevel)
endif

MDS_TEX := $(CSW)/lvx-mds/lvx-refs/BE/TEX/lvx/lvx_v1

SRCS := $(wildcard *.tex)
PDFS := $(patsubst %.tex,build/%.pdf,$(SRCS))

LATEXMK := latexmk
# -halt-on-error: fail loudly instead of dropping into LaTeX's interactive
# prompt, which hangs a non-interactive build forever.
LATEXMKFLAGS := -pdf -halt-on-error -interaction=nonstopmode -quiet

.PHONY: all clean show
all: $(PDFS)

build:
	@mkdir -p build

# The wrapper: minimal preamble (xcolor for the \color used in the tables),
# generous margins so the wide generated tables fit, and the fragment
# \input as the body. Named .wrapper.tex so it cannot collide with a real
# source file.
build/%.pdf: %.tex | build
	@printf '%s\n' \
	  '\documentclass[11pt,a4paper]{article}' \
	  '\usepackage[margin=25mm]{geometry}' \
	  '\usepackage{xcolor}' \
	  '\usepackage{hyperref}' \
	  '\setlength{\parindent}{0pt}' \
	  '\setlength{\parskip}{6pt}' \
	  '\title{$(subst _,\_,$*)}' \
	  '\date{}' \
	  '\begin{document}' \
	  '\maketitle' \
	  '\tableofcontents' \
	  '\bigskip' \
	  '\input{$(CURDIR)/$*}' \
	  '\end{document}' > build/$*.wrapper.tex
	@echo "  PDF  $@"
	@cd build && TEXINPUTS="$(MDS_TEX):$(CURDIR):" \
	  $(LATEXMK) $(LATEXMKFLAGS) $*.wrapper.tex >/dev/null
	@mv build/$*.wrapper.pdf $@

show:
	@echo "sources:      $(SRCS)"
	@echo "outputs:      $(PDFS)"
	@echo "MDS tables:   $(MDS_TEX)"
	@test -d "$(MDS_TEX)" && echo "              (found)" || echo "              *** MISSING -- \\input will fail ***"

clean:
	@rm -rf build
