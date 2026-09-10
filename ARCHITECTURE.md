# Architecture Diagrams — MIPS Multi-Cycle CPU

Companion to [`README.md`](README.md). Every diagram below reflects the RTL as
written in `top_cpu_mc.v`, `cpu_top_mc.v`, `control_unit_mc.v`, `ALU_32_bit.v`,
`regfile.v`, `imem.v`, and `dmem.v`.

---

## 1. System overview (board level)

`top_cpu_mc.v` is the top-level entity. It owns all board-specific concerns —
pin wiring, clock division, debouncing, and the debug probes — and wraps the
CPU, which runs on a divided clock.

```
  BOARD PINS                    top_cpu_mc.v  (top-level entity)
  ──────────────────────────────────────────────────────────────────────

  clk ──► PIN_23 (50 MHz)
            │
            ├──► /4 divider ────────────────►  cpu_clk (12.5 MHz)
            │
            ├──► debounce ──► 3-FF sync ──► edge ──────┐
            │    KEY[2] PIN_90                          │  start_pulse
            │                                           │  (& ~uart_loading)
            ├──► debounce ──► 2-FF sync (level) ───────┼──►  rst
            │    KEY[3] PIN_91                          │
            │                                           │
            ├──► debounce ──────────────────────────────┼──►  mmio_btn_in
            │    KEY[4] PIN_25                          │
            │                                           │
            └──► uart_rx ──► uart_loader ───────────────┼──►  uart_wr_clk
                 9600 8N1, 50 MHz                       │    uart_wr_en
                 UART_RXD (pin unassigned)              │    uart_wr_addr
                                                        │    uart_wr_data
                                                        ▼
                                              ┌──────────────────────────┐
                                              │      cpu_top_mc.v        │
                                              │   multi-cycle datapath   │
                                              │     + control FSM        │
                                              └──────────────────────────┘


  OUTPUTS
  ──────────────────────────────────────────────────────────────────────

  mmio_led_out ──► [invert] ──► LEDG[3:0]     board LEDs are active-LOW
  debug_*      ──► 5 × ISSP cores ──► JTAG debugger
  KEY[1:0]     ──► seg7_display ──► SEG[7:0] / DIG[3:0]
                   shows $5 / $6 / $7 / $8;  decimal point = overflow flag
```

**Clock domains.** Everything left of `cpu_top_mc`'s clock input runs on the raw
50 MHz clock: the debouncers (timing calibrated in real milliseconds), the UART
receiver (baud timing must be precise), the UART loader, and the `imem` write
port. The CPU itself runs on `cpu_clk` (50/4 = 12.5 MHz). Only two signals cross
into `cpu_clk` — `rst` and `start_pulse` — and both are synchronized first.

---

## 2. Datapath — structural view

`cpu_top_mc.v` holds *all* state; the FSM holds none. The FSM observes a few
status signals and issues latch enables.

```
  ┌──────────────────────────────┐
  │      control_unit_mc.v       │
  │      FSM — holds no data     │
  └──────────────────────────────┘

  CONTROL SIGNALS OUT  (latch enables and mux selects)
  ──────────────────────────────────────────────────────────────────────
    ir_write            pc_plus1_write      ab_write
    branch_target_write alu_out_write       pc_write
    mdr_write           md_init             md_step
    hi_write            lo_write            alu_op[3:0]
    alu_src             pc_source[1:0]      reg_write
    reg_dst[1:0]        wb_sel[1:0]         dmem_write

  STATUS SIGNALS IN
  ──────────────────────────────────────────────────────────────────────
    ir_reg
    regs_equal          (= a_reg == b_reg)
    alu_ov
    md_counter_done
```

### 2.1 Data flow through the shared datapath

```
  ── IF : fetch ─────────────────────────────────────────────────────────
     pc[11:0] ─────► imem.v (4096 × 32) ─────► ir_reg[31:0]
     pc + 1   ─────► pc_plus1_reg[11:0]

  ── ID : decode / operand fetch ────────────────────────────────────────
     ir_reg[25:21] = rs ──► regfile.v (32 × 32, $0 ≡ 0) ──► a_reg[31:0]
     ir_reg[20:16] = rt ──► regfile.v                   ──► b_reg[31:0]
     pc_plus1_reg + sext(imm16) ─────────────────────────► branch_target_reg

  ── EX : execute ───────────────────────────────────────────────────────
     a_reg ────────────────────────────────────────────────► ALU_32_bit.v
     b_reg ──(or)── sext(imm16)    selected by alu_src ────► ALU_32_bit.v
     ALU_32_bit.v ──► alu_out_reg[31:0]
     ALU_32_bit.v ──► Cout, Ov
     pc_next ──► pc                selected by pc_source

  ── MEM : data memory ──────────────────────────────────────────────────
     alu_out_reg[4:0] ──► MMIO decode ──► dmem.v (32 × 32) ──► mdr_reg
     b_reg ─────────────────────────────► dmem write data
     b_reg[3:0] ────────────────────────► led_reg   (SW to address 31 only)

  ── WB : write back ────────────────────────────────────────────────────
     write_data ──► regfile write port   selected by wb_sel / reg_dst
```

### 2.2 Field decode

Decoded combinationally from the **latched** instruction, so the fields stay
valid through ID/EX/MEM/WB — not just during IF:

```
     ir_reg[31:26] ──► opcode[5:0]
     ir_reg[25:21] ──► rs[4:0]
     ir_reg[20:16] ──► rt[4:0]
     ir_reg[15:11] ──► rd[4:0]
     ir_reg[5:0]   ──► funct[5:0]
     ir_reg[15:0]  ──► imm16[15:0] ──► sext ──► imm_sext[31:0]
     ir_reg[11:0]  ──► jump_target[11:0]      JAL absolute target
```

### 2.3 The three output muxes

```
  write_data mux          (priority order — first match wins)
     reg_dst == 2  ──► {25'b0, pc_plus1_reg}     JAL: return address
     wb_sel  == 1  ──► mdr_reg                   LW: from memory
     wb_sel  == 2  ──► hi_reg                    MFHI
     wb_sel  == 3  ──► lo_reg                    MFLO
     otherwise     ──► alu_out_reg               R-type / ADDI

  write_reg mux
     reg_dst == 2  ──► $31                       JAL
     reg_dst == 1  ──► rt                        ADDI, LW
     reg_dst == 0  ──► rd                        R-type, MFHI, MFLO

  pc_next mux             (pc_source)
     2'd0  ──► pc_plus1_reg                      fall-through
     2'd1  ──► branch_target_reg                 BEQ/BNE taken
     2'd2  ──► jump_target = ir_reg[11:0]        JAL (absolute)
     2'd3  ──► a_reg[11:0]                       JR
```

The PC updates **once per instruction, during EX**, for every instruction type.

---

## 3. Instruction lifecycle

The same hardware, cycled one state at a time. This is the view that makes the
multi-cycle nature obvious: one shared datapath, reused 3–5 times per
instruction.

```
  IDLE ──► IF ──► ID ──► EX ──┬──► WB ──────────────┐  R-type, ADDI, MFHI/MFLO
    ▲                         ├──► MEM ──┬─► WB ────┤  LW
    │                         │          └─────────┤  SW
    │                         └────────────────────┤  BEQ/BNE, JR, JAL
    │                                              │
    │                                              ▼
    │                                        back to IF   (auto-run)
    │
    └── rst only
```

---

## 4. ALU internals (`ALU_32_bit.v`)

Patterson & Hennessy style: 31 identical `alu_1bit` slices plus an `alu_1Xbit`
slice for the MSB that additionally exposes its raw sum bit for `SLT`.

```
  ── ONE BIT-SLICE (used for bits 0..30) ──────────────────────────────

     Step 1 — optional inversion
        N1 = Ainvert ? ~A[i] : A[i]
        N2 = Binvert ? ~B[i] : B[i]

     Step 2 — compute every candidate result in parallel
        AND  = N1 & N2
        OR   = N1 | N2
        Sum  = N1 + N2 + Cin            via full_adder
        Less = the LT signal            only wired into bit 0

     Step 3 — select one
        mux4x1( AND, OR, Sum, Less ,  Sel = Op[1:0] ) ──► Result[i]

        Sel:   00 = AND    01 = OR    10 = SUM    11 = LESS


  ── MSB SLICE (bit 31) ───────────────────────────────────────────────
     Identical to the above, plus two extra outputs:
        Set  = Sum        raw sum bit, exported so the top level can build LT
        Cout = final carry out


  ── FULL ADDER (full_adder) ─────────────────────────────────────────
        Sum  = A ^ B ^ Cin
        Cout = (A & B) | (B & Cin) | (A & Cin)


  ── BIT-0 SPECIAL CASES ─────────────────────────────────────────────
     Only slice 0 takes Cin = Op[2]   — supplies the +1 that makes SUB work
     Only slice 0 receives LT         — the SLT comparison result
     Every other slice takes the carry from the slice below
```

**Top-level flags:**

```
  Cout = carry out of bit 31
  Ov   = Carry[30] ^ Cout     signed overflow: carry-in XOR carry-out of MSB
  LT   = Ov ^ Set             SLT result, corrected when overflow occurred
```

**Op encoding** — `Op = {Ainvert, Binvert, Op[1:0]}`:

```
  4'b0000  AND
  4'b0001  OR
  4'b0010  ADD
  4'b0110  SUB     (A + ~B + 1   via Binvert=1, Op=10, Cin=1)
  4'b0111  SLT     (Result = LT)
  4'b1100  NOR     (Ainvert=1, Binvert=1, Op=00   →   ~A & ~B)
```

---

## 5. MULT / DIV unit

Both operations share one 64-bit working register and one 32-cycle state
(`MD_LOOP`), selected by `is_mult` / `is_div`. Sharing storage is safe because
`ir_reg` is stable, so only one can ever be in flight.

```
  ── EX : md_init ──────────────────────────────────────────────────────
     md_sign_reg    ← a_reg[31] ^ b_reg[31]
     md_counter     ← 0
     a_abs = |a_reg|          b_abs = |b_reg|

     MULT :  md_b_reg       ← a_abs               multiplicand
             md_product_reg ← {32'b0, b_abs}      multiplier, in LOW half

     DIV  :  md_b_reg       ← b_abs               divisor
             md_product_reg ← {32'b0, a_abs}      dividend, in LOW half


  ── MD_LOOP : one step per cycle, ×32 (md_step) ───────────────────────

     MULT — shift-add, shifting RIGHT
        if (md_product[0])   md_product[63:32] += md_b_reg
        md_product >>= 1

     DIV — restoring division, shifting LEFT
        shifted = md_product << 1
        diff    = shifted[63:32] - md_b_reg
        if (diff < 0)
            md_product = { shifted[63:32], shifted[31:1], 1'b0 }
                            ^ restore value        ^ quotient bit 0
        else
            md_product = { diff[31:0],      shifted[31:1], 1'b1 }
                            ^ keep value           ^ quotient bit 1

     md_counter += 1          done when md_counter == 31


  ── MD_DONE : sign-correct and latch ──────────────────────────────────

     MULT :  product = sign ? -(md_product) : md_product      (64-bit)
             HI ← product[63:32]          LO ← product[31:0]

     DIV  :  QUOT = sign   ? -md_product[31:0]  : md_product[31:0]
             REM  = a[31]  ? -md_product[63:32] : md_product[63:32]
             HI ← REM                     LO ← QUOT
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
| `EX` | `4'd3` | `TRAP` if illegal → else `HALT` if halt → else `MD_LOOP` if mult/div → else `MEM` if lw/sw → else `WB` if rtype/addi/mfhi/mflo → else **`IF`** |
| `MEM` | `4'd4` | `WB` if `lw`, else `IF` |
| `WB` | `4'd5` | `IF` |
| `TRAP` | `4'd6` | `TRAP` (absorbing) |
| `MD_LOOP` | `4'd7` | `MD_DONE` if `md_counter_done`, else `MD_LOOP` |
| `MD_DONE` | `4'd8` | `IF` |
| `HALT` | `4'd9` | `HALT` (absorbing) |

The branches ending in `IF` implement **auto-run**: after the one-time `IDLE`
exit, every instruction returns to `IF`, so a single `KEY[2]` press runs the
entire program.

### 6.2 Transition graph

Every branch terminates on its own line, so no join lines are needed.

```
  IDLE ─(start)─► IF ─► ID ─► EX ─┬─(illegal)────────► TRAP     (stuck; rst only)
                                  ├─(halt)───────────► HALT     (stuck; rst only)
                                  ├─(mult / div)─────► MD_LOOP ─(×32)─► MD_DONE ─► IF
                                  ├─(lw)─────────────► MEM ─(lw)─► WB ─► IF
                                  ├─(sw)─────────────► MEM ─► IF
                                  ├─(rtype / addi /
                                  │   mfhi / mflo)───► WB ─► IF
                                  └─(beq / bne / jr / jal)────────► IF
```

`MD_LOOP` self-loops 32 times (`md_counter_done` low), then proceeds to
`MD_DONE`. `TRAP` and `HALT` are absorbing — only `rst` leaves them.

### 6.3 Control signals asserted per state

```
              IDLE   IF    ID    EX    MEM   WB   MD_LOOP MD_DONE TRAP  HALT
  ir_write      ·     ●     ·     ·     ·     ·       ·       ·      ·     ·
  pc_plus1_wr   ·     ●     ·     ·     ·     ·       ·       ·      ·     ·
  ab_write      ·     ·     ●     ·     ·     ·       ·       ·      ·     ·
  branch_tgt_wr ·     ·     ●     ·     ·     ·       ·       ·      ·     ·
  alu_out_write ·     ·     ·     ●     ·     ·       ·       ·      ·     ·
  pc_write      ·     ·     ·     ●     ·     ·       ·       ·      ·     ·
  mdr_write     ·     ·     ·     ·     ●     ·       ·       ·      ·     ·
  md_init       ·     ·     ·    ●¹     ·     ·       ·       ·      ·     ·
  md_step       ·     ·     ·     ·     ·     ·       ●       ·      ·     ·
  hi_write      ·     ·     ·     ·     ·     ·       ·       ●      ·     ·
  lo_write      ·     ·     ·     ·     ·     ·       ·       ●      ·     ·
  dmem_write    ·     ·     ·     ·    ●²     ·       ·       ·      ·     ·
  reg_write     ·     ·     ·    ●³     ·     ●⁴      ·       ·      ·     ·

  ¹ MULT / DIV only
  ² SW only
  ³ JAL only  ($31 ← pc_plus1_reg)
  ⁴ rtype / addi / lw / mfhi / mflo only
```

---

## 7. Memory map and MMIO decode

`dmem` keeps a 5-bit address, so only the low 5 bits of a computed address are
used. Two addresses are intercepted **before** reaching `dmem.v`, leaving that
module completely unmodified.

```
     alu_out_reg[4:0]
            │
            ├── == 5'd31 ──► is_led_addr ──┐
            │                              │  on SW
            │                              ▼
            │                       led_reg ← b_reg[3:0] ──► ~LEDG[3:0]
            │                       (real dmem write suppressed)
            │
            ├── == 5'd30 ──► is_btn_addr ──┐
            │                              │  on LW
            │                              ▼
            │                       read_data = {31'b0, KEY[4]}
            │
            └── otherwise ────────────────► dmem.v (32 × 32)
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

```
  RAW 50 MHz DOMAIN                        cpu_clk DOMAIN (12.5 MHz)
  ─────────────────────────────────────────────────────────────────────

  clk ──► /4 divider ──────────────────────────► cpu_clk
            │
  KEY[2] ──► debounce ──┐
                        │  key2_debounced (level)
                        └──► 3-FF sync ──► edge ──► start_pulse ──►  start
                             detect        (& gated by ~uart_loading,
                                            evaluated in the cpu_clk domain)

  KEY[3] ──► debounce ──┐
                        │  key3_debounced (level)
                        └──► 2-FF sync, LEVEL ──────────────────►  rst
                             (hold = held reset; not edge-detected)

  KEY[4] ──► debounce ─────────────────────────────────────────►  mmio_btn_in
                                                                      │
                                        (2-FF sync inside cpu_top_mc:
                                         btn_sync1 ──► btn_sync2)

  UART_RXD ──► uart_rx ──► uart_loader ──► imem write port
              9600 8N1                     (wr_clk = raw 50 MHz)
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

```
                     IF   ID   EX   MEM   WB   MD_LOOP    MD_DONE   total
  ADD/SUB/AND/OR/SLT ███  ███  ███   ·    ███     ·           ·        4
  ADDI               ███  ███  ███   ·    ███     ·           ·        4
  MFHI / MFLO        ███  ███  ███   ·    ███     ·           ·        4
  LW                 ███  ███  ███  ███   ███     ·           ·        5
  SW                 ███  ███  ███  ███    ·      ·           ·        4
  BEQ / BNE          ███  ███  ███   ·     ·      ·           ·        3
  JR  / JAL          ███  ███  ███*  ·     ·      ·           ·        3
  MULT / DIV         ███  ███  ███   ·     ·   ███ × 32       ███      36
  HALT               ███  ███  ███   ·     ·      ·           ·     3 → stuck
  (illegal)          ███  ███  ███   ·     ·      ·           ·     3 → stuck

  ███ = a cycle spent in that state
  *   = JAL writes $31 during EX

  IDLE is NOT counted: it is visited once after reset, then never again.
```

---

## 11. Module dependency graph

```
                        top_cpu_mc.v   (TOP-LEVEL ENTITY)
                               │
        ┌──────────────────────┼───────────────────────┐
        │                      │                       │
        ▼                      ▼                       ▼
   board glue              the CPU              serial loader
        │                      │                       │
        ├── debounce.v         ├── cpu_top_mc.v        ├── uart_rx.v
        │   (+ edge_detector)  │        │              └── uart_loader.v
        │                      │        ├── control_unit_mc.v
        ├── seg7_display.v     │        ├── regfile.v
        │        │             │        ├── ALU_32_bit.v
        │        └── seg7_     │        │      └── alu_1bit / alu_1Xbit
        │            decoder.v │        │          full_adder / mux4x1
        │                      │        ├── imem.v
        └── 5 × ISSP cores     │        └── dmem.v
                               │
                    (the FSM holds no data —
                     it only issues latch enables)
```

**Not in the build** (removed during the repository cleanup, recoverable from
git commit `c64214a`): `cpu_top.v`, `top_cpu.v`, `control_unit.v`, and the legacy
ISSP cores `cpu_issp_lo`, `cpu_issp_hi`, `cpu_issp_mem`, `cpu_issp_dmem2`,
`cpu_issp_dmem3`.
