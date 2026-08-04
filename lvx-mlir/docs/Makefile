# Build .tex and .pdf from the Markdown documents here.
#
#   make            -> build/<name>.tex and build/<name>.pdf for every *.md
#   make tex        -> just the .tex files
#   make clean      -> remove build/
#
# Both artifacts are wanted, for different reasons: the .pdf to read, and the
# .tex to lift LaTeX snippets out of. So the .tex is a real output, not a
# throwaway intermediate -- it is never deleted between runs, and the .pdf is
# compiled *from it* rather than generated separately, which means a .pdf
# proves its .tex actually compiles.
#
# The .tex is standalone (pandoc -s: it carries its own preamble) so that the
# compile step can verify it. To reuse a piece as a snippet, take what is
# between \begin{document} and \end{document} -- section structure, tables and
# verbatim blocks all survive intact.

SRCS := $(wildcard *.md)
TEXS := $(patsubst %.md,build/%.tex,$(SRCS))
PDFS := $(patsubst %.md,build/%.pdf,$(SRCS))

PANDOC := pandoc
# --toc: these documents are long and heavily sectioned.
# --wrap=preserve: keeps the source's line breaks, so a diff between two
#   generated .tex files stays readable.
# -V geometry: the tables here are wide (register tables, pass pipelines).
PANDOCFLAGS := -s --from=gfm --to=latex --toc --wrap=preserve \
               -V geometry:margin=25mm \
               -V colorlinks=true \
               -V documentclass=article \
               -V fontsize=11pt \
               -H latex-header.tex

# pdflatex, and ASCII diagrams to suit it: see latex-header.tex for why this
# environment cannot use lualatex (no luaotfload cache, no tool to build one)
# and what the header declares to make 8-bit pdflatex accept the remaining
# non-ASCII characters.
LATEXMK := latexmk
LATEXMKFLAGS := -pdf -halt-on-error -interaction=nonstopmode -quiet

.PHONY: all tex clean
all: $(PDFS)
tex: $(TEXS)

build:
	@mkdir -p build

build/%.tex: %.md | build
	@echo "  TEX  $@"
	@$(PANDOC) $(PANDOCFLAGS) -V title="$*" -o $@ $<

# Compiled from the .tex above, not from the .md -- so a successful .pdf is
# evidence the .tex is well-formed and reusable.
build/%.pdf: build/%.tex
	@echo "  PDF  $@"
	@cd build && $(LATEXMK) $(LATEXMKFLAGS) $*.tex >/dev/null

clean:
	@rm -rf build
