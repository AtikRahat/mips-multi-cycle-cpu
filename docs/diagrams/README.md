# Rendered Architecture Diagrams

Pre-rendered PNGs of every diagram in [`../../ARCHITECTURE.md`](../../ARCHITECTURE.md),
for viewers that cannot render Mermaid with the ELK layout engine (for example
GitHub's built-in renderer, which does not bundle ELK).

These are **generated artefacts**. The Mermaid source in `ARCHITECTURE.md` is
the single source of truth — edit that, then re-render.

> ⚠️ **Stale renders.** The PNGs for §1, §3, §6.2, §9, §10, and §11 predate the
> synchronous-`dmem` + `MEM2` change and the ISSP removal, and no longer match
> the source (§9's PNG was deleted outright). Re-render per the instructions
> below before treating any of those six as current.

---

## 1. System overview (board level)

![System overview](01-1-system-overview-board-level.png)

## 2.1 Datapath — data flow

![Data flow](02-2-1-data-flow.png)

## 3. Instruction lifecycle

![Instruction lifecycle](03-3-instruction-lifecycle.png)

## 4. ALU internals

![ALU internals](04-4-alu-internals-alu-32-bit-v.png)

## 5. MULT / DIV unit

![MULT DIV unit](05-5-mult-div-unit.png)

## 6.2 Control FSM state diagram

![FSM state diagram](06-6-2-state-diagram.png)

## 7. Memory map and MMIO decode

![Memory map](07-7-memory-map-and-mmio-decode.png)

## 8. Clock, reset, and clock-domain crossing

![Clock domains](08-8-clock-reset-and-clock-domain-crossing.png)

## 9. On-board visibility (ISSP removed)

The ISSP probe-layout diagram was deleted with the cores (§9 of
`ARCHITECTURE.md` now shows the display + simulation visibility instead).

## 10. Instruction timing

![Instruction timing](10-10-instruction-timing.png)

## 11. Module dependency graph

![Module graph](11-11-module-dependency-graph.png)

---

## Re-rendering

Requires Node.js, plus Chrome/Chromium (or a downloaded Puppeteer browser).

```bash
npm install @mermaid-js/mermaid-cli @mermaid-js/layout-elk
```

Then, for each diagram, render its code block from `ARCHITECTURE.md`:

```bash
mmdc -i diagram.mmd -o diagram.png -b white -s 2
```

The ELK layout engine is requested per-diagram via the `%%{init: ...}%%`
directive at the top of each flowchart block, so no extra CLI flag is needed
once the `@mermaid-js/layout-elk` package is installed.
