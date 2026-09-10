# Architecture Diagrams — MIPS Multi-Cycle CPU

Companion to [`README.md`](README.md). Every diagram below reflects the RTL as
written in `top_cpu_mc.v`, `cpu_top_mc.v`, `control_unit_mc.v`, `ALU_32_bit.v`,
`regfile.v`, `imem.v`, and `dmem.v`.

> The diagrams are [Mermaid](https://mermaid.js.org/). They render inline on
> GitHub, GitLab, in VS Code (with a Mermaid extension), and in Obsidian. In a
> plain text viewer you will see the Mermaid source instead of a picture.

---

## 1. System overview (board level)

`top_cpu_mc.v` is the top-level entity. It owns all board-specific concerns —
pin wiring, clock division, debouncing, and the debug probes — and wraps the
CPU, which runs on a divided clock.

```mermaid
flowchart TB
    CLK["clk PIN_23 — 50 MHz"]

    DIV["/4 clock divider"]
    CCP["cpu_clk — 12.5 MHz"]

    D2["debounce<br/>KEY[2] PIN_90"]
    D3["debounce<br/>KEY[3] PIN_91"]
    D4["debounce<br/>KEY[4] PIN_25"]

    SY2["3-FF sync then edge detect"]
    SY3["2-FF sync — level"]

    URX["uart_rx — 9600 8N1"]
    ULD["uart_loader"]

    CPU["cpu_top_mc.v — multi-cycle datapath and control FSM"]

    SEG["seg7_display and seg7_decoder"]
    LED["LEDG[3:0] — active-LOW"]
    DBG["5 x ISSP debug cores to JTAG"]

    CLK --> DIV
    DIV --> CCP
    CCP --> CPU

    CLK --> D2
    CLK --> D3
    CLK --> D4
    CLK --> URX
    CLK --> SEG

    D2 --> SY2
    SY2 -->|"start_pulse, gated by uart_loading"| CPU

    D3 --> SY3
    SY3 -->|rst| CPU

    D4 -->|mmio_btn_in| CPU

    URX --> ULD
    ULD -->|"wr_clk, wr_en, wr_addr, wr_data"| CPU

    CPU -->|mmio_led_out| LED
    CPU -->|"debug register, PC, state, HI/LO"| DBG
    CPU -->|"$5, $6, $7, $8 and overflow flag"| SEG

    KEY10["KEY[1:0]"]
    KEY10 -->|display select| SEG
```

**Clock domains.** Everything left of `cpu_top_mc`'s clock input runs on the raw
50 MHz clock: the debouncers (timing calibrated in real milliseconds), the UART
receiver (baud timing must be precise), the UART loader, and the `imem` write
port. The CPU itself runs on `cpu_clk` (50 / 4 = 12.5 MHz). Only two signals
cross into `cpu_clk` — `rst` and `start_pulse` — and both are synchronized first.

---

## 2. Datapath — structural view

`cpu_top_mc.v` holds *all* state; the FSM holds none. The FSM observes a few
status signals and issues latch enables.

### 2.1 Data flow through the shared datapath

```mermaid
flowchart TD
    FSM["control_unit_mc.v — FSM, holds no data"]

    PC["pc register"]
    IMEM["imem.v — 4096 x 32"]
    IR["ir_reg"]
    RF["regfile.v — 32 x 32, $0 always reads 0"]
    A["a_reg"]
    B["b_reg"]
    BMUX["ALU B mux — alu_src"]
    ALU["ALU_32_bit.v"]
    AO["alu_out_reg"]
    MMIO["MMIO decode — address 30 and 31"]
    DM["dmem.v — 32 x 32"]
    MDR["mdr_reg"]
    WBMUX["write_data mux — wb_sel, reg_dst"]
    MD["MULT / DIV unit"]
    PCPLUS["pc_plus1_reg"]
    BTR["branch_target_reg"]
    PCMUX["pc_next mux — pc_source"]

    PC -->|address| IMEM
    IMEM -->|instruction| IR
    PC --> PCPLUS

    IR -->|"rs, rt"| RF
    RF -->|read_data1| A
    RF -->|read_data2| B
    PCPLUS -->|"plus sign-extended imm16"| BTR

    A --> ALU
    B --> BMUX
    IR -->|imm_sext| BMUX
    BMUX -->|alu_b| ALU
    ALU -->|Result| AO
    ALU -->|"Cout, Ov"| FSM

    AO -->|"address bits 4:0"| MMIO
    MMIO -->|"real writes"| DM
    B -->|write data| DM
    DM -->|read data| MDR

    AO --> WBMUX
    MDR --> WBMUX
    MD -->|"HI, LO"| WBMUX
    WBMUX -->|write_data| RF

    PCPLUS -->|"JAL return address"| WBMUX
    PCMUX -->|next PC| PC
    PCPLUS --> PCMUX
    BTR --> PCMUX
    IR -->|"JAL target"| PCMUX
    A -->|"JR target"| PCMUX

    FSM -.->|"ir_write, pc_plus1_write"| IR
    FSM -.->|ab_write| A
    FSM -.->|ab_write| B
    FSM -.->|branch_target_write| BTR
    FSM -.->|alu_out_write| AO
    FSM -.->|pc_write| PC
    FSM -.->|mdr_write| MDR
    FSM -.->|reg_write| RF
    FSM -.->|md_init| MD
    FSM -.->|dmem_write| DM

    A -.->|regs_equal| FSM
    IR -.->|"opcode, funct"| FSM
    MD -.->|md_counter_done| FSM
```

### 2.2 Field decode

Decoded combinationally from the **latched** instruction, so the fields stay
valid through ID/EX/MEM/WB — not just during IF:

```mermaid
flowchart LR
    IR["ir_reg[31:0]"]
    OP["opcode[5:0]"]
    RS["rs[4:0]"]
    RT["rt[4:0]"]
    RD["rd[4:0]"]
    FN["funct[5:0]"]
    IMM["imm16[15:0]"]
    SEXT["imm_sext[31:0]"]
    JT["jump_target[11:0]"]

    IR -->|"bits 31:26"| OP
    IR -->|"bits 25:21"| RS
    IR -->|"bits 20:16"| RT
    IR -->|"bits 15:11"| RD
    IR -->|"bits 5:0"| FN
    IR -->|"bits 15:0"| IMM
    IMM -->|sign extend| SEXT
    IR -->|"bits 11:0"| JT
```

### 2.3 The three output muxes

| `write_data` mux (priority — first match wins) | Selects |
|---|---|
| `reg_dst == 2` | `{25'b0, pc_plus1_reg}` — JAL return address |
| `wb_sel == 1` | `mdr_reg` — LW, from memory |
| `wb_sel == 2` | `hi_reg` — MFHI |
| `wb_sel == 3` | `lo_reg` — MFLO |
| otherwise | `alu_out_reg` — R-type / ADDI |

| `write_reg` mux | Selects |
|---|---|
| `reg_dst == 2` | `$31` — JAL |
| `reg_dst == 1` | `rt` — ADDI, LW |
| `reg_dst == 0` | `rd` — R-type, MFHI, MFLO |

| `pc_next` mux (`pc_source`) | Selects |
|---|---|
| `2'd0` | `pc_plus1_reg` — fall-through |
| `2'd1` | `branch_target_reg` — BEQ / BNE taken |
| `2'd2` | `jump_target` = `ir_reg[11:0]` — JAL (absolute) |
| `2'd3` | `a_reg[11:0]` — JR |

The PC updates **once per instruction, during EX**, for every instruction type.

### 2.4 Control and status signals

| Direction | Signals |
|---|---|
| Out — latch enables | `ir_write`, `pc_plus1_write`, `ab_write`, `branch_target_write`, `alu_out_write`, `pc_write`, `mdr_write`, `md_init`, `md_step`, `hi_write`, `lo_write` |
| Out — mux selects | `alu_op[3:0]`, `alu_src`, `pc_source[1:0]`, `reg_write`, `reg_dst[1:0]`, `wb_sel[1:0]`, `dmem_write` |
| In — status | `ir_reg`, `regs_equal` (`a_reg == b_reg`), `alu_ov`, `md_counter_done` |

---

## 3. Instruction lifecycle

The same hardware, cycled one state at a time. This is the view that makes the
multi-cycle nature obvious: one shared datapath, reused 3–5 times per
instruction.

```mermaid
stateDiagram-v2
    [*] --> IDLE
    IDLE --> IF : start pulse
    IF --> ID
    ID --> EX

    EX --> WB : R-type, ADDI, MFHI, MFLO
    EX --> MEM : LW, SW
    EX --> IF : BEQ, BNE, JR, JAL

    MEM --> WB : LW
    MEM --> IF : SW

    WB --> IF

    note right of IDLE
        rst returns the FSM to IDLE
        from any state
    end note

    note left of IF
        Auto-run: every instruction ends
        back at IF, so one KEY[2] press
        runs the whole program
    end note
```

---

## 4. ALU internals (`ALU_32_bit.v`)

Patterson & Hennessy style: 31 identical `alu_1bit` slices plus an `alu_1Xbit`
slice for the MSB that additionally exposes its raw sum bit for `SLT`.

```mermaid
flowchart LR
    AI["A[i]"]
    BI["B[i]"]
    NA["N1 — invert if Ainvert"]
    NB["N2 — invert if Binvert"]
    ANDG["AND"]
    ORG["OR"]
    FA["full_adder"]
    SUM["Sum"]
    LT["Less — the LT signal"]
    MUX["mux4x1 — Sel equals Op[1:0]"]
    RES["Result[i]"]

    AI --> NA
    BI --> NB

    NA --> ANDG
    NB --> ANDG
    NA --> ORG
    NB --> ORG
    NA --> FA
    NB --> FA

    CIN["Cin"]
    CIN --> FA
    FA --> SUM

    ANDG --> MUX
    ORG --> MUX
    SUM --> MUX
    LT --> MUX
    MUX --> RES

    note1["Sel 00 = AND, 01 = OR, 10 = SUM, 11 = LESS"]
    MUX --- note1
```

**MSB slice (bit 31).** Identical to the above, plus two extra outputs:
`Set = Sum` (the raw sum bit, exported so the top level can build `LT`) and
`Cout` (the final carry out).

**Bit-0 special cases.** Only slice 0 takes `Cin = Op[2]` — this supplies the
`+1` that makes `SUB` work. Only slice 0 receives `LT`, the SLT comparison
result. Every other slice takes the carry from the slice below.

**Top-level flags:**

```
  Cout = carry out of bit 31
  Ov   = Carry[30] ^ Cout     signed overflow: carry-in XOR carry-out of MSB
  LT   = Ov ^ Set             SLT result, corrected when overflow occurred
```

**Op encoding** — `Op = {Ainvert, Binvert, Op[1:0]}`:

| `Op[3:0]` | Operation |
|---|---|
| `4'b0000` | AND |
| `4'b0001` | OR |
| `4'b0010` | ADD |
| `4'b0110` | SUB — `A + ~B + 1`, via Binvert=1, Op=10, Cin=1 |
| `4'b0111` | SLT — `Result = LT` |
| `4'b1100` | NOR — Ainvert=1, Binvert=1, Op=00 → `~A & ~B` |

---

## 5. MULT / DIV unit

Both operations share one 64-bit working register and one 32-cycle state
(`MD_LOOP`), selected by `is_mult` / `is_div`. Sharing storage is safe because
`ir_reg` is stable, so only one can ever be in flight.

```mermaid
flowchart TD
    INIT["EX — md_init"]

    INIT --> SIGN["md_sign_reg gets a_reg[31] XOR b_reg[31]"]
    INIT --> CNT["md_counter gets 0"]
    INIT --> ABS["a_abs and b_abs — magnitudes"]

    SIGN --> SEL{"is_mult or is_div"}

    SEL -->|MULT| MSET["md_b_reg gets a_abs — multiplicand<br/>md_product_reg gets b_abs in LOW half"]
    SEL -->|DIV| DSET["md_b_reg gets b_abs — divisor<br/>md_product_reg gets a_abs in LOW half"]

    MSET --> LOOP["MD_LOOP — 32 iterations, md_step"]
    DSET --> LOOP

    LOOP --> MSTEP["MULT — shift-add, shifting RIGHT<br/>if md_product bit 0 then add md_b_reg to high half<br/>then shift the whole 64-bit register right by 1"]
    LOOP --> DSTEP["DIV — restoring division, shifting LEFT<br/>shift left, subtract divisor from high half<br/>negative restores and shifts in 0, else keeps and shifts in 1"]

    MSTEP --> DONEQ{"md_counter_done"}
    DSTEP --> DONEQ
    DONEQ -->|no| LOOP
    DONEQ -->|yes| MDD["MD_DONE — sign-correct and latch"]

    MDD --> MOUT["MULT result — 64-bit product<br/>HI gets product 63:32<br/>LO gets product 31:0"]
    MDD --> DOUT["DIV result<br/>HI gets remainder, LO gets quotient<br/>remainder follows the dividend sign"]
```

After the 32 division steps the **quotient sits in the low half and the
remainder in the high half** — exactly the MIPS `LO`/`HI` convention, so no
reshuffling is needed. The remainder takes the **dividend's** sign (`a_reg[31]`),
matching real MIPS.

`HI` and `LO` are read back through the write-back mux by `MFHI` (`wb_sel = 2`)
and `MFLO` (`wb_sel = 3`).

---

## 6. Control FSM (`control_unit_mc.v`)

### 6.1 Transition table (authoritative)

| State | Encoding | Next state |
|---|---|---|
| `IDLE` | `4'd0` | `IF` if `start`, else `IDLE` |
| `IF` | `4'd1` | `ID` |
| `ID` | `4'd2` | `EX` |
| `EX` | `4'd3` | `TRAP` if illegal, else `HALT` if halt, else `MD_LOOP` if mult/div, else `MEM` if lw/sw, else `WB` if rtype/addi/mfhi/mflo, else **`IF`** |
| `MEM` | `4'd4` | `WB` if `lw`, else `IF` |
| `WB` | `4'd5` | `IF` |
| `TRAP` | `4'd6` | `TRAP` (absorbing) |
| `MD_LOOP` | `4'd7` | `MD_DONE` if `md_counter_done`, else `MD_LOOP` |
| `MD_DONE` | `4'd8` | `IF` |
| `HALT` | `4'd9` | `HALT` (absorbing) |

### 6.2 State diagram

```mermaid
stateDiagram-v2
    [*] --> IDLE

    IDLE --> IF : start pulse
    IDLE --> IDLE : rst held

    IF --> ID
    ID --> EX

    EX --> TRAP : illegal opcode
    EX --> HALT : HALT instruction
    EX --> MD_LOOP : MULT or DIV
    EX --> MEM : LW or SW
    EX --> WB : R-type, ADDI, MFHI, MFLO
    EX --> IF : BEQ, BNE, JR, JAL

    MEM --> WB : LW
    MEM --> IF : SW

    WB --> IF

    MD_LOOP --> MD_LOOP : md_counter_done is 0
    MD_LOOP --> MD_DONE : md_counter_done is 1
    MD_DONE --> IF

    TRAP --> TRAP : stuck — rst only
    HALT --> HALT : stuck — rst only

    note right of TRAP
        Sticky illegal_opcode flag
        latches here
    end note

    note left of IF
        Branches ending at IF implement
        auto-run: one KEY[2] press runs
        the entire program
    end note
```

`MD_LOOP` self-loops 32 times, then proceeds to `MD_DONE`. `TRAP` and `HALT` are
absorbing — only `rst` leaves them.

### 6.3 Control signals asserted per state

| Signal | IDLE | IF | ID | EX | MEM | WB | MD_LOOP | MD_DONE | TRAP | HALT |
|---|---|---|---|---|---|---|---|---|---|---|
| `ir_write` | | ● | | | | | | | | |
| `pc_plus1_write` | | ● | | | | | | | | |
| `ab_write` | | | ● | | | | | | | |
| `branch_target_write` | | | ● | | | | | | | |
| `alu_out_write` | | | | ● | | | | | | |
| `pc_write` | | | | ● | | | | | | |
| `mdr_write` | | | | | ● | | | | | |
| `md_init` | | | | ● ¹ | | | | | | |
| `md_step` | | | | | | | ● | | | |
| `hi_write` | | | | | | | | ● | | |
| `lo_write` | | | | | | | | ● | | |
| `dmem_write` | | | | | ● ² | | | | | |
| `reg_write` | | | | ● ³ | | ● ⁴ | | | | |

¹ MULT / DIV only ² SW only ³ JAL only (`$31` ← `pc_plus1_reg`)
⁴ rtype / addi / lw / mfhi / mflo only

---

## 7. Memory map and MMIO decode

`dmem` keeps a 5-bit address, so only the low 5 bits of a computed address are
used. Two addresses are intercepted **before** reaching `dmem.v`, leaving that
module completely unmodified.

```mermaid
flowchart TD
    ADDR["alu_out_reg bits 4:0"]

    ADDR -->|"equals 31"| LEDA["is_led_addr"]
    ADDR -->|"equals 30"| BTNA["is_btn_addr"]
    ADDR -->|otherwise| REAL["dmem.v — 32 x 32"]

    LEDA -->|"on SW"| LED["led_reg gets b_reg bits 3:0<br/>real dmem write suppressed"]
    LED --> OUT["invert then LEDG[3:0]"]

    BTNA -->|"on LW"| BTN["read_data gets zero-extended KEY[4]"]

    BREG["b_reg — write data"]
    BREG --> REAL
    BREG --> LED
```

| Address | `LW` | `SW` |
|---|---|---|
| `0`–`29` | ordinary `dmem` read | ordinary `dmem` write |
| `30` | **MMIO** → `{31'b0, KEY[4]}` | ordinary write to `mem[30]` |
| `31` | ordinary read of `mem[31]` | **MMIO** → `led_reg[3:0]` |

The asymmetry means `mem[30]` is unreachable via `LW` and `mem[31]` unreachable
via `SW`, but each stays reachable in the other direction.

The button input passes through a 2-FF synchronizer (`btn_sync1` / `btn_sync2`)
inside `cpu_top_mc.v`, since it arrives from a different clock domain.

---

## 8. Clock, reset, and clock-domain crossing

```mermaid
flowchart TB
    subgraph RAW["RAW 50 MHz DOMAIN"]
        CLK["clk — 50 MHz"]
        DIV["/4 divider"]
        D2["debounce KEY[2]"]
        D3["debounce KEY[3]"]
        D4["debounce KEY[4]"]
        URX["uart_rx — 9600 8N1"]
        ULD["uart_loader"]
    end

    subgraph SLOW["cpu_clk DOMAIN — 12.5 MHz"]
        CCP["cpu_clk"]
        SY2["3-FF sync then edge detect"]
        SY3["2-FF sync — level"]
        CPU["cpu_top_mc.v"]
        BSYNC["2-FF sync — btn_sync1, btn_sync2"]
    end

    CLK --> DIV
    DIV --> CCP
    CCP --> CPU

    CLK --> D2
    CLK --> D3
    CLK --> D4

    D2 -->|level| SY2
    SY2 -->|"start_pulse — one full cpu_clk wide"| CPU

    D3 -->|level| SY3
    SY3 -->|"rst — held level, not edge detected"| CPU

    D4 --> BSYNC
    BSYNC -->|mmio_btn_in| CPU

    URX --> ULD
    ULD -->|"imem write port, wr_clk is 50 MHz"| CPU
```

`start` is edge-detected **inside the `cpu_clk` domain**, not the fast one. A
single-cycle pulse generated at 50 MHz could be too narrow for a 12.5 MHz clock
to ever sample; synchronizing the *level* first and then edge-detecting
guarantees a pulse a full `cpu_clk` period wide.

`rst` is deliberately a **level**, not a pulse — holding the button holds reset.

---

## 9. ISSP debug probe layout

Five `altera_in_system_sources_probes` cores, clocked from the JTAG domain.
Word *n* within an instance occupies bits `[32n+31 : 32n]`, with no gaps.

```mermaid
flowchart LR
    RLO["cpu_issp_regs_lo — 480 bits<br/>$0 to $14"]
    RHI["cpu_issp_regs_hi — 480 bits<br/>$15 to $29"]
    DLO["cpu_issp_dmem_lo — 480 bits<br/>mem[0] to mem[14]"]
    DHI["cpu_issp_dmem_hi — 480 bits<br/>mem[15] to mem[29]"]
    STA["cpu_issp_status — 312 bits<br/>PC, state, flags, HI/LO, ir_reg,<br/>dmem transaction, $30, $31, mem[30], mem[31]"]

    CPU["cpu_top_mc.v debug ports"]
    JTAG["JTAG debugger"]

    CPU --> RLO
    CPU --> RHI
    CPU --> DLO
    CPU --> DHI
    CPU --> STA

    RLO --> JTAG
    RHI --> JTAG
    DLO --> JTAG
    DHI --> JTAG
    STA --> JTAG
```

| Core | Width | Bits `[31:0]` | Bits `[479:448]` |
|---|---|---|---|
| `cpu_issp_regs_lo` | 480 | `$0` (tied to constant 0) | `$14` |
| `cpu_issp_regs_hi` | 480 | `$15` | `$29` |
| `cpu_issp_dmem_lo` | 480 | `mem[0]` | `mem[14]` |
| `cpu_issp_dmem_hi` | 480 | `mem[15]` | `mem[29]` |

So `cpu_issp_regs_lo` holds `$0`–`$14` and `cpu_issp_regs_hi` holds `$15`–`$29`,
packed at `$n` → bits `[32n+31 : 32n]`. The memory cores follow the same pattern
for `mem[0]`–`mem[14]` and `mem[15]`–`mem[29]`.

### `cpu_issp_status` — 312 bits

| Bits | Width | Contents |
|---|---|---|
| `[311:300]` | 12 | PC |
| `[299:296]` | 4 | FSM state |
| `[295]` | 1 | sticky overflow flag |
| `[294]` | 1 | sticky illegal-opcode flag |
| `[293:262]` | 32 | HI |
| `[261:230]` | 32 | LO |
| `[229:198]` | 32 | `ir_reg` (current instruction) |
| `[197:193]` | 5 | dmem address |
| `[192:161]` | 32 | dmem write data |
| `[160]` | 1 | dmem write enable |
| `[159:128]` | 32 | dmem read data |
| `[127:96]` | 32 | `$30` |
| `[95:64]` | 32 | `$31` |
| `[63:32]` | 32 | `mem[30]` |
| `[31:0]` | 32 | `mem[31]` |

**Why this grouping:** `ALTSOURCE_PROBE` has a hard **511-bit `PROBE_WIDTH`
limit** — 16 words × 32 bits = 512 bits is rejected. Each core therefore carries
15 words (480 bits), and the four leftovers (`$30`, `$31`, `mem[30]`, `mem[31]`)
are folded into the status core, which has headroom.

---

## 10. Instruction timing (cycles on `cpu_clk`, 12.5 MHz)

The x-axis of the chart below is the **cycle index**, not wall-clock time.
`IDLE` is not shown: it is visited once after reset and then never again.

```mermaid
gantt
    title Instruction timing — cycles on cpu_clk
    dateFormat X
    axisFormat %s

    section R-type, ADDI, MFHI, MFLO
    IF        :r1, 0, 1
    ID        :r2, 1, 1
    EX        :r3, 2, 1
    WB        :r4, 3, 1

    section LW
    IF        :l1, 0, 1
    ID        :l2, 1, 1
    EX        :l3, 2, 1
    MEM       :l4, 3, 1
    WB        :l5, 4, 1

    section SW
    IF        :s1, 0, 1
    ID        :s2, 1, 1
    EX        :s3, 2, 1
    MEM       :s4, 3, 1

    section BEQ, BNE, JR, JAL
    IF        :b1, 0, 1
    ID        :b2, 1, 1
    EX        :b3, 2, 1

    section MULT and DIV
    IF        :m1, 0, 1
    ID        :m2, 1, 1
    EX        :m3, 2, 1
    MD_LOOP x32 :m4, 3, 32
    MD_DONE   :m5, 35, 1
```

| Instruction | States | Cycles |
|---|---|---|
| ADD, SUB, AND, OR, SLT | IF, ID, EX, WB | 4 |
| ADDI | IF, ID, EX, WB | 4 |
| MFHI, MFLO | IF, ID, EX, WB | 4 |
| LW | IF, ID, EX, MEM, WB | 5 |
| SW | IF, ID, EX, MEM | 4 |
| BEQ, BNE | IF, ID, EX | 3 |
| JR, JAL | IF, ID, EX (JAL writes `$31` in EX) | 3 |
| MULT, DIV | IF, ID, EX, 32 × MD_LOOP, MD_DONE | 36 |
| HALT | IF, ID, EX, then stuck | 3 |
| illegal opcode | IF, ID, EX, then stuck | 3 |

---

## 11. Module dependency graph

```mermaid
flowchart TD
    TOP["top_cpu_mc.v — TOP-LEVEL ENTITY"]

    subgraph GLUE["Board glue"]
        DEB["debounce.v — includes edge_detector"]
        SEGD["seg7_display.v"]
        SEGC["seg7_decoder.v"]
        ISSPS["5 x ISSP cores"]
    end

    subgraph CORECPU["The CPU"]
        CPU["cpu_top_mc.v"]
        CTRL["control_unit_mc.v"]
        RF["regfile.v"]
        ALU["ALU_32_bit.v"]
        ALUSUB["alu_1bit, alu_1Xbit, full_adder, mux4x1"]
        IMEM["imem.v"]
        DMEM["dmem.v"]
    end

    subgraph LOADER["Serial loader"]
        URX["uart_rx.v"]
        ULD["uart_loader.v"]
    end

    TOP --> DEB
    TOP --> SEGD
    TOP --> ISSPS
    TOP --> CPU
    TOP --> URX

    SEGD --> SEGC

    CPU --> CTRL
    CPU --> RF
    CPU --> ALU
    CPU --> IMEM
    CPU --> DMEM
    ALU --> ALUSUB

    URX --> ULD
    ULD -->|"imem write port"| IMEM

    CTRL -.->|"holds no data — issues latch enables"| CPU
```

**Not in the build** (removed during the repository cleanup, recoverable from
git commit `c64214a`): `cpu_top.v`, `top_cpu.v`, `control_unit.v`, and the legacy
ISSP cores `cpu_issp_lo`, `cpu_issp_hi`, `cpu_issp_mem`, `cpu_issp_dmem2`,
`cpu_issp_dmem3`.
