# Poster — MIPS Multi-Cycle CPU

A **30 in × 72 in portrait banner** poster for Innovation Fair Bangladesh,
built from the current `README.md` and `ARCHITECTURE.md`. It supersedes the
stale, untracked `PaperDraft.pdf`.

| File | Role |
|---|---|
| `poster.tex` | The whole poster — preamble, styles and content |
| `poster.pdf` | Built output, 30 in × 72 in (2160 × 5184 pt) |

---

## Build

Requires a TeX distribution with `tikzposter` (TeX Live 2025 is what this was
built and verified against). Run **twice** — tikzposter needs two passes to
settle block positions:

```bash
cd poster
pdflatex -interaction=nonstopmode poster.tex
pdflatex -interaction=nonstopmode poster.tex
```

Then confirm the page size, which is the make-or-break check:

```bash
pdfinfo poster.pdf | grep "Page size"
# must read: 2160 x 5184 pts
```

### Two things that will bite you when editing

**1. The custom page size.** `tikzposter` hard-codes `a0paper` in its own
option list and derives every block and column width from `\textwidth` at
class-load time. Passing `paperwidth`/`paperheight` as class options is
**silently ignored** — you get A0. The size is therefore applied *after* the
class, and the derived widths recomputed:

```latex
\geometry{paperwidth=30in,paperheight=72in}
\makeatletter
\setlength{\TP@visibletextwidth}{\textwidth-2\TP@innermargin}
\setlength{\TP@visibletextheight}{\textheight-2\TP@innermargin}
\makeatother
```

Without that recomputation the page is 30 in wide but every block is still
sized for A0.

**2. Vertical overflow is silent.** tikzposter spreads the rows to fill the
page height when the content fits, and quietly **drops the last rows off the
bottom** when it does not — it does *not* emit an `Overfull \vbox` warning.
After any content edit, re-check that the last block still renders. The
reliable test is to compare the lowest text coordinate against the page
height (5184 pt):

```bash
pdftotext -bbox poster.pdf - \
  | grep -o 'yMax="[0-9.]*"' | tr -d 'yMax="' | sort -g | tail -1
```

As built, that prints about `5126`, i.e. ~58 pt (0.8 in) of clear bottom
margin. If it prints `5184` or more, a row is being clipped — shrink the
type scale, trim block padding, or shorten a section.

A quick sanity check that the footer specifically survived:

```bash
pdftotext poster.pdf - | grep -c "Presented at Innovation Fair"
```

That must print `1`. Note that the text layer alone is *not* sufficient proof
of layout — clipped text can still be present in the PDF text stream, which
is exactly why the coordinate check above is the one that matters.

Three levers keep the content inside 72 in, in order of effect:

1. **The type scale** — the `25pt` class option loads `a0size.sty`, where
   `\large` is 29.86 pt, and tikzposter renders every block *body* at
   `\large`. The `\renewcommand{\normalsize}...` block rescales this.
2. **Block padding** — the `Simple` theme uses the `Minimal` block style,
   whose defaults are `titleinnersep=1cm` and `bodyinnersep=1cm`. Across ~11
   blocks that is roughly 9 in of padding, so it is trimmed via
   `\useblockstyle[...]{Minimal}`.
3. **Figure heights** — the near-square FSM and ISSP diagrams are
   height-constrained (`height=...`) rather than width-constrained; at full
   column width the FSM diagram alone would be ~15 in tall.

---

## Figures

The poster includes five diagrams from [`../docs/diagrams/`](../docs/diagrams),
pulled in via `\graphicspath`:

| Figure | Aspect | Placement |
|---|---|---|
| `01-1-system-overview-board-level.png` | 2.76 | width-constrained |
| `02-2-1-data-flow.png` | 3.72 | width-constrained |
| `10-10-instruction-timing.png` | 2.01 | height-constrained |
| `06-6-2-state-diagram.png` | 0.64 | height-constrained |
| `09-9-issp-debug-probe-layout.png` | 1.03 | height-constrained |

These are the pre-rendered PNGs documented in `docs/diagrams/README.md`; the
Mermaid source in `ARCHITECTURE.md` remains the single source of truth. If a
diagram changes, re-render the PNG there and rebuild — nothing here needs to
change.

The PNGs were exported at `-s 2`, so at poster scale they sit near 150 dpi:
fine on screen and acceptable in print. For a large-format print where the
lines must stay perfectly crisp, re-render just these five to vector PDF with
`mermaid-cli` and swap the extensions in `\includegraphics`:

```bash
npm install @mermaid-js/mermaid-cli @mermaid-js/layout-elk
mmdc -i <block>.mmd -o figures/<name>.pdf -b white -s 3
```

---

## Content

Every figure and number is taken from the current docs — nothing is carried
over from the stale `PaperDraft.pdf`. Sections, top to bottom:

1. **At a Glance** + **System Overview** — headline specs and the board-level
   block diagram
2. **Instruction Set** — all 17 instructions, split into two half-tables
3. **The Datapath** + **Compute Units** — data flow, ALU op encoding, MULT/DIV
4. **Instruction Timing** + **Memory, MMIO and Board I/O**
5. **Control FSM** + **Debug (ISSP probes)**
6. **Build, Load and Run** + **Design Journey / Future work**
7. **Footer** — the Innovation Fair credit line

Block accents follow the colour key published in `ARCHITECTURE.md` (orange =
storage, blue = compute, green = memory, purple = control, grey = clock/reset,
red = I/O) so the poster and the diagrams read as one artefact.
