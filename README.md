# MIPS Multi-Cycle CPU (Cyclone IV E FPGA)

A **multi-cycle MIPS softcore** written in Verilog, targeting an Altera/Intel
**Cyclone IV E `EP4CE6E22C8`** (EP4CE6 development board). The CPU executes a
17-instruction MIPS subset with an FSM-driven datapath, on-chip instruction and
data memory, a UART program loader, memory-mapped I/O, and a 4-digit 7-segment
register display. Five in-system source-and-probe (ISSP) debug cores used to
provide live inspection in Quartus; they were removed (see §10) and remain
recoverable from git history.

This project is the **multi-cycle successor** to an earlier single-cycle design.
The single-cycle RTL and its unused ISSP cores were removed during a cleanup
pass; they remain recoverable from git history (see §13).

---

## 1. Hardware & toolchain

| Item | Value |
|---|---|
| FPGA | Intel/Altera Cyclone IV E, `EP4CE6E22C8` |
| Board clock | 50 MHz on `PIN_23` |
| CPU clock | 50 MHz / 4 = **12.5 MHz** (internal divider) |
| Toolchain | Quartus Prime **25.1std Lite Edition** |
| Top-level entity | `top_cpu_mc` |
| Project file | `Mips_Multi_Cycle_Cpu.qpf` / `.qsf` / `.qws` |
| Timing constraints | `timing_constraints.sdc` |

### Current fit (last successful compile)

From `output_files/Mips_Multi_Cycle_Cpu.fit.summary`:

| Resource | Usage |
|---|---|
| Total logic elements | **3,279 / 6,272 (52 %)** |
| Combinational functions | 3,011 / 6,272 (48 %) |
| Dedicated logic registers | 1,564 / 6,272 (25 %) |
| Memory bits | 147,456 / 276,480 (53 %) |
| Pins | 23 / 92 (25 %) |
| Embedded multipliers | 0 / 30 |
| PLLs | 0 / 2 |

Timing (`sta.summary`): worst-case setup slack on `clk` is **+13.470 ns** against
the 20 ns period constraint, so the design closes timing at 50 MHz with room to
spare.

The win comes from two changes: removing `dmem`'s 32 fixed-address debug taps
(which had forced Quartus to shadow the whole 512-word data memory into
flip-flops), and giving `dmem` a synchronous read so Quartus infers real M9K
block RAM — compensated by a new `MEM2` FSM state (LW = IF, ID, EX, MEM, MEM2,
WB; see §3.3 and §3.6). The five ISSP debug cores and their probe wiring were
also removed outright (§10), so the fit above has no debug overhead at all.

The ISSP probes were the area hog — the probe shadow registers alone were
4 × 480 + 312 = 2,232 bits, on top of the 32×32-bit register file. They were
first made compile-time optional (the `CPU_ISSP` macro), then removed outright
along with the `dmem` debug taps (see §10) — the 52 % fit above carries no
debug overhead at all.

> **Note:** `timing_constraints.sdc` only declares the 50 MHz `clk`. The divided
> 12.5 MHz `cpu_clk` is *not* separately constrained — it is analyzed as part of
> the `clk` domain, which is conservative.

---

## 2. Repository layout

### Active RTL (compiled — listed in `.qsf`)

| File | Role |
|---|---|
| `top_cpu_mc.v` | Board-level top: pin wiring, clock divider, debounce, MMIO, UART loader, register-select display |
| `cpu_top_mc.v` | Multi-cycle **datapath**: PC, datapath registers, register file, ALU, memories, MULT/DIV |
| `control_unit_mc.v` | Multi-cycle **control FSM**: state machine + all control signals |
| `ALU_32_bit.v` | 32-bit ripple ALU (`alu_1bit`, `alu_1Xbit`, `full_adder`, `mux4x1`) |
| `regfile.v` | 32×32 register file, 2 combinational read ports, 1 write port, `$0` hardwired to 0 |
| `imem.v` | Instruction memory, 4,096 × 32, `$readmemh("program.hex")` + UART write port |
| `dmem.v` | Data memory, 512 × 32, `$readmemh("data.hex")`, synchronous read (M9K) |
| `debounce.v` | Button debouncer + `edge_detector` module |
| `seg7_decoder.v` | 4-bit hex → 7-segment pattern |
| `seg7_display.v` | 4-digit time-multiplexed scan driver |
| `uart_rx.v` | 8N1 UART receiver, 9600 baud @ 50 MHz |
| `uart_loader.v` | Assembles UART bytes into 32-bit words, writes `imem` |

### Documentation

| File | Role |
|---|---|
| `README.md` | This file — full project documentation |
| `ARCHITECTURE.md` | Architecture diagrams (board, datapath, FSM, ALU, MULT/DIV, clock domains, instruction timing) |
| `docs/RZ-EasyFPGA-A2.2-Board.md` | Board & FPGA reference: specs, pinout, config, quirks |
| `docs/diagrams/` | Pre-rendered PNGs of every diagram, for viewers that cannot render ELK |

### Software

| File | Role |
|---|---|
| `assembler.py` | MIPS-subset assembler; emits `program.hex` + `data.hex` |
| `program.asm` | Source for the default test program (§11) |
| `program(sum).asm`, `program(big_test).asm` | Sources for the alternate test programs |
| `program.hex` | Instruction image (4,096 words, zero-padded) |
| `data.hex` | Initial data memory (512 words, zero-padded) |
| `program(sum).hex`, `program(big_test).hex` | Alternate test programs |
| `data(sum).hex`, `data(big_test).hex` | Alternate data images |

### Build outputs (regenerable, gitignored)

| Path | Role |
|---|---|
| `output_files/` | Quartus outputs (`.sof`, reports). Regenerate with `quartus_sh --flow compile` |
| `db/`, `dba/`, `incremental_db/`, `incremental_dba/` | Quartus internal databases (gitignored, regenerable) |
| `simulation/questa/` | Generated Questa simulation netlist + `.sft` (gitignored) |

> The original assembly sources are now checked in alongside the `.hex` images:
> `program.asm`, `program(sum).asm`, and `program(big_test).asm`. Re-assemble any
> of them with `python3 assembler.py <source>` and compare against the matching
> `.hex` (the default reproduces `program.hex` byte-for-byte; the two alternates
> gain one unreachable trailing `HALT`, see §8).

---

## 3. Architecture

> Full-page [Mermaid](https://mermaid.js.org/) diagrams (board level, datapath,
> control/status signals, FSM state diagram, ALU, MULT/DIV, clock domains,
> instruction timing) are in **[`ARCHITECTURE.md`](ARCHITECTURE.md)**.
> The summary below is the quick-reference version.

### 3.1 Block diagram

```
                    ┌──────────────────────────────────────────────┐
                    │              control_unit_mc.v               │
                     │   FSM: IDLE→IF→ID→EX→{MEM,MEM2,WB,MD_LOOP,...}│
                    │   emits: ir_write, pc_write, alu_op, ...      │
                    └───────┬──────────────────────────────────────┘
                            │ control signals
   ┌────────────┐           ▼                ┌────────────────────┐
   │  imem.v    │◄── pc ──────────────┐       │   regfile.v        │
   │ 4096 × 32  │── ir ──┐           │       │  32 × 32, $0 == 0  │
   └─────┬──────┘        │      ┌────┴────┐  └──┬──────────┬──────┘
         │               │      │ pc_plus1│     │ A        │ B
         │               │      │  _reg   │     ▼          ▼
         │               │      └─────────┘  ┌──────────────┐
         │               │                   │  ALU_32_bit  │
         │               ▼                   │ A op {B,imm} │
         │        ┌─────────────┐            └──────┬───────┘
         │        │   ir_reg    │                   │ alu_out_reg
         │        │  (latched)  │                   ▼
         │        └──────┬──────┘            ┌──────────────┐
         │               │ opcode/funct      │    dmem.v    │
         │               ▼                   │   32 × 32    │
         │        ┌─────────────┐            └──────┬───────┘
         │        │ MULT/DIV    │ ◄─ md_step        │ mdr_reg
         │        │ 64-bit loop │                   │
         │        └──────┬──────┘            writeback mux
         │               │ HI / LO                  │
         └───────────────┴──────────────────────────┘
```

### 3.2 Multi-cycle datapath (`cpu_top_mc.v`)

The datapath is **time-multiplexed**: unlike a single-cycle CPU, it uses
intermediate registers to hold partial results across cycles. Control only
decides *which* register latches on a given clock edge.

**Cross-cycle registers:**

| Register | Width | Written in | Purpose |
|---|---|---|---|
| `pc` | 12 | EX | Architectural program counter (4,096 words) |
| `ir_reg` | 32 | IF | Latched instruction (decode is done off this, not off `imem` output) |
| `pc_plus1_reg` | 12 | IF | PC+1 captured at fetch — return address / fall-through |
| `a_reg`, `b_reg` | 32 | ID | Latched register-file read operands |
| `branch_target_reg` | 12 | ID | `pc_plus1_reg + sign_extend(imm16)` |
| `alu_out_reg` | 32 | EX | Latched ALU result (arithmetic result *or* memory address) |
| `mdr_reg` | 32 | MEM2 | Latched data-memory read value (one cycle after MEM presents the address — `dmem`'s read is synchronous so Quartus infers M9K) |
| `hi_reg`, `lo_reg` | 32 | MD_DONE | Architectural HI/LO for MFHI/MFLO |
| `md_product_reg` | 64 | MD_LOOP | MULT product accumulator / DIV `{remainder:quotient}` |
| `md_b_reg` | 32 | EX | MULT multiplicand / DIV divisor magnitude |
| `md_sign_reg` | 1 | EX | XOR of operand signs — final negation flag |
| `md_counter` | 6 | MD_LOOP | 0..31 iteration counter |
| `led_reg` | 4 | MEM (SW) | MMIO LED output state |
| `btn_sync1/2` | 1 each | every clk | 2-FF synchronizer for the MMIO button |

Key design points:

* **Decode happens off `ir_reg`**, not the `imem` output. Since `pc` is frozen
  for the whole instruction, `imem` could be read combinationally at any state,
  but the instruction fields are needed through WB, so `ir_reg` is the source.
* **PC updates exactly once per instruction, during EX**, for *every*
  instruction type. `pc_source` selects the next value.
* **Write-back mux** (`wb_sel`) selects ALUOut, MDR, HI, or LO. Destination
  register (`reg_dst`) selects `rd`, `rt`, or `$31`.
* **MMIO is decoded before `dmem`**, keeping `dmem.v` unmodified: `SW` to
  address 511 diverts to the LED register and suppresses the real memory write;
  `LW` from address 510 returns the button value.

### 3.3 Control FSM (`control_unit_mc.v`)

The control unit holds **no data** — only the current state. It decodes
`opcode`/`funct` from the latched instruction and asserts per-state pulses.

**States:**

| State | Encoding | Purpose |
|---|---|---|
| `IDLE` | `4'd0` | Visited only once after reset, waiting for the first `KEY[2]` press |
| `IF` | `4'd1` | Fetch: `ir_reg <= imem[pc]`, `pc_plus1_reg <= pc+1` |
| `ID` | `4'd2` | Decode/operand fetch: `A <= rf[rs]`, `B <= rf[rt]`, branch target |
| `EX` | `4'd3` | Execute: ALU, PC update, JAL `$31` write |
| `MEM` | `4'd4` | Address present for LW/SW; SW writes here |
| `MEM2` | `4'd10` | LW only: capture `dmem` read data into MDR (one cycle of synchronous-read latency for M9K inference; SW skips this state) |
| `WB` | `4'd5` | Register write-back |
| `TRAP` | `4'd6` | Illegal instruction — permanent until reset |
| `MD_LOOP` | `4'd7` | MULT/DIV 32-iteration shift-add / restoring-division loop |
| `MD_DONE` | `4'd8` | MULT/DIV sign correction, write HI/LO |
| `HALT` | `4'd9` | Explicit stop (opcode `111111`) — permanent until reset |

**Auto-run behaviour:** `IDLE` is exited exactly once, on the first `KEY[2]`
press. Every instruction's terminal transition points back to **`IF`** rather
than `IDLE`, so after one press the FSM free-runs the **entire program** on
`cpu_clk`. Only `rst` (KEY[3]) returns it to `IDLE`.

**Sticky flags:**

* `overflow` — latches the first time `ADD`/`SUB`/`ADDI` genuinely overflows the
  signed 32-bit range. Cleared only by reset. Deliberately sticky so an overflow
  cannot be missed by looking at the wrong cycle. Drives the 7-segment decimal
  point.
* `illegal_opcode` — latches when the FSM enters `TRAP`. Since `TRAP` is
  permanent, this flag and "the FSM is stuck" always agree.

**Illegal-instruction detection:** `is_illegal` is a proper whitelist. For
`opcode == 0` it requires one of the ten known R-type functs; otherwise it
requires one of the six known opcodes. This closes an earlier gap where an
unrecognized funct silently executed as `ADD` (the `alu_op` default).

### 3.4 ALU (`ALU_32_bit.v`)

Patterson & Hennessy style: 31 identical `alu_1bit` slices plus one `alu_1Xbit`
slice for the MSB that also exposes the raw sum bit (`Set`) needed by `SLT`.

**Op encoding** (`Op = {Ainvert, Binvert, Op[1:0]}`):

| `Op[3:0]` | Operation |
|---|---|
| `4'b0000` | AND |
| `4'b0001` | OR |
| `4'b0010` | ADD |
| `4'b0110` | SUB (`A + ~B + 1`) |
| `4'b0111` | SLT (set-less-than) |
| `4'b1100` | NOR (`Ainvert=1, Binvert=1, Op=00`) |

* `Ov = Carry[30] ^ Cout` — signed overflow (carry into MSB XOR carry out).
* `LT = Ov ^ Set` — corrects the SLT sign when overflow occurred.

### 3.5 Register file (`regfile.v`)

* 32 × 32-bit storage, two **combinational** read ports, one **clocked** write port.
* `$0` is hardwired to read as 0 and ignores writes (`write_reg != 5'd0`).
* `rst` synchronously clears all 32 physical registers, taking priority over writes.
* Every register `$1`–`$31` has a dedicated debug output (used by the
  7-segment register-select display in `top_cpu_mc.v`).

### 3.6 Memories

| Memory | Size | Read | Write | Init |
|---|---|---|---|---|
| `imem.v` | 4,096 × 32 | Combinational | Clocked (`wr_clk`) via UART loader | `$readmemh("program.hex")` |
| `dmem.v` | 512 × 32 | Synchronous (1-cycle latency) | Clocked, gated by `write_enable` | `$readmemh("data.hex")` |

The synchronous `dmem` read is deliberate: Cyclone IV block RAM has no
combinational read path Quartus can infer, so an async
`assign read_data = mem[addr]` fails inference (Error 276003) and falls back
to one flip-flop per bit (16,384 registers). The registered read is the
standard single-port-RAM template Quartus maps to 2 M9K blocks; the FSM
compensates with the extra `MEM2` state (LW = IF, ID, EX, MEM, MEM2, WB).

`imem` uses a **12-bit address**, chosen deliberately: 4,096 words needs
16 M9K blocks at 32-bit width, within the EP4CE6's 30-block budget (14 spare).
An earlier 8,192-word / 13-bit attempt needed 32 blocks and **failed to fit**.

Both `program.hex` and `data.hex` are **zero-padded to full depth** by the
assembler (4,096 and 512 words respectively), so both files must always exist
even if a program has no `.data` section. Full padding is mandatory: `$readmemh`
leaves any word not present in the file uninitialised rather than 0.

### 3.7 Clocking, reset, and the start button (`top_cpu_mc.v`)

* **Clock divider:** `clkdiv[1]` produces `cpu_clk = 50 MHz / 4 = 12.5 MHz`.
  The divider exists because timing analysis once showed a ~23.75 ns critical
  path (Fmax ≈ 42 MHz) — longer than the 50 MHz period — which caused wrong
  `SLT` results on hardware. The current build closes timing at 50 MHz, so the
  divider is now pure margin.
* **Reset (`KEY[3]`)** — debounced on the fast clock, then passed through a
  2-FF synchronizer into `cpu_clk` as a **level** (hold = held reset), not an
  edge pulse. Zeroes the PC, all registers, and both sticky flags.
* **Start (`KEY[2]`)** — debounced on the fast clock, then synchronized into
  `cpu_clk` with a 3-FF chain and edge-detected *in the `cpu_clk` domain*. This
  matters because a single-cycle pulse generated in the fast domain could be too
  narrow for the slow clock to ever sample. The pulse is suppressed while a UART
  transfer is in flight (`~uart_loading`), preventing a half-loaded program from
  being executed.
* **Debounce** module runs on the raw 50 MHz clock (its timing is calibrated in
  real milliseconds), and includes a 2-FF input synchronizer.

---

## 4. Instruction set

17 instructions are decoded. Format follows real MIPS encodings.

| Mnemonic | Format | Syntax | Opcode | Funct |
|---|---|---|---|---|
| `ADD` | R | `ADD $rd, $rs, $rt` | `000000` | `100000` |
| `SUB` | R | `SUB $rd, $rs, $rt` | `000000` | `100010` |
| `AND` | R | `AND $rd, $rs, $rt` | `000000` | `100100` |
| `OR` | R | `OR $rd, $rs, $rt` | `000000` | `100101` |
| `SLT` | R | `SLT $rd, $rs, $rt` | `000000` | `101010` |
| `MULT` | R | `MULT $rs, $rt` → HI:LO | `000000` | `011000` |
| `DIV` | R | `DIV $rs, $rt` → LO/quot, HI/rem | `000000` | `011010` |
| `MFHI` | R | `MFHI $rd` | `000000` | `010000` |
| `MFLO` | R | `MFLO $rd` | `000000` | `010010` |
| `JR` | R | `JR $rs` | `000000` | `001000` |
| `ADDI` | I | `ADDI $rt, $rs, imm` | `001000` | — |
| `LW` | I | `LW $rt, offset($rs)` | `100011` | — |
| `SW` | I | `SW $rt, offset($rs)` | `101011` | — |
| `BEQ` | I | `BEQ $rs, $rt, label` | `000100` | — |
| `BNE` | I | `BNE $rs, $rt, label` | `000101` | — |
| `JAL` | J | `JAL label` (writes `$31 = PC+1`) | `000011` | — |
| `HALT` | — | `HALT` (no operands) | `111111` | — |

**Encoding notes:**

* **Branches** use PC-relative offsets: `offset = label − (addr + 1)`, stored as
  a 16-bit signed field. Range checked by the assembler.
* **`JAL`** is *not* standard MIPS pseudo-direct addressing. The assembler emits
  the absolute target in the low 26 bits, and the hardware reads only
  `ir_reg[11:0]` — i.e. a 12-bit absolute target, valid because `imem` is
  4,096 words.
* **`JR`** sets `PC = $rs` (low 12 bits used).
* **`HALT`** is a project-specific instruction (`opcode 111111`) that parks the
  FSM in `HALT` permanently.
* **`MULT`/`DIV`** take no `rd`; results go to HI/LO and must be moved out with
  `MFHI`/`MFLO`.

### MULT / DIV implementation

Both share the same 64-bit working register and the same 32-cycle state
(`MD_LOOP`), selected by `is_mult`/`is_div` (constant while the instruction is
in flight since `ir_reg` is stable).

* **MULT — shift-add.** Each step: if the low half's LSB is 1, add the
  multiplicand into the high half; shift the whole 64-bit register right by 1.
* **DIV — restoring division.** Each step: shift the 64-bit
  `{remainder:quotient}` register left; subtract the divisor from the new high
  half; if negative, restore and shift in a `0`, else keep and shift in a `1`.
  After 32 steps the **quotient is in the low half** and the **remainder in the
  high half** — exactly matching the MIPS `LO`/`HI` convention, so no
  reshuffling is required.
* **Sign handling.** Operands are converted to magnitude up front
  (`a_abs`/`b_abs`), the sign XOR is latched in `md_sign_reg`, and the final
  result is negated in `MD_DONE`. The **remainder follows the dividend's sign**,
  as in real MIPS.

`md_counter_done = (md_counter == 6'd31)`; combined with `md_step` being
asserted whenever the state is `MD_LOOP`, the loop executes exactly
**32 iterations** before moving to `MD_DONE`.

---

## 5. Instruction timing

Cycle counts on `cpu_clk` (12.5 MHz), per instruction:

| Instruction | Cycles | States |
|---|---|---|
| `ADD`/`SUB`/`AND`/`OR`/`SLT` | 4 | IF, ID, EX, WB |
| `ADDI` | 4 | IF, ID, EX, WB |
| `MFHI`/`MFLO` | 4 | IF, ID, EX, WB |
| `LW` | 6 | IF, ID, EX, MEM, MEM2, WB |
| `SW` | 4 | IF, ID, EX, MEM |
| `BEQ`/`BNE` | 3 | IF, ID, EX |
| `JR`/`JAL` | 3 | IF, ID, EX (JAL writes `$31` in EX) |
| `MULT`/`DIV` | **36** | IF, ID, EX, 32 × MD_LOOP, MD_DONE |
| `HALT` | 3 then stuck | IF, ID, EX → HALT |
| *(illegal)* | 3 then stuck | IF, ID, EX → TRAP |

`IDLE` is **not** part of an instruction's cycle count — it is visited only once
after reset. At 12.5 MHz, a plain ALU instruction takes 320 ns.

---

## 6. Memory map & memory-mapped I/O

### Data memory (`dmem`, 512 words, 9-bit address)

Addresses come from `alu_out_reg[8:0]`, so the low 9 bits of a computed address
select the word.

| Address | Access | Behaviour |
|---|---|---|
| `0` – `509` | read/write | Ordinary data memory words |
| `510` | `LW` | **MMIO**: returns `{31'b0, KEY[4]}` (the debounced spare button) |
| `510` | `SW` | Ordinary write to `mem[510]` (not intercepted) |
| `511` | `SW` | **MMIO**: writes `b_reg[3:0]` to `led_reg` → `LEDG[3:0]` |
| `511` | `LW` | Ordinary read of `mem[511]` (not intercepted) |

The asymmetry (510 is read-intercepted, 511 is write-intercepted) means
`mem[510]` is unusable via `LW` and `mem[511]` is unusable via `SW`, but each
remains accessible in the other direction.

The **LEDs are physically active-LOW** on this board. `top_cpu_mc.v` inverts at
the pin (`assign LEDG = ~led_bus`), so `cpu_top_mc.v` stays board-agnostic:
`mmio_led_out = 4'b1100` genuinely means "bits 3 and 2 on".

### Instruction memory

12-bit word address, 4,096 words, fully readable; writable at runtime only
through the UART loader's dedicated write port.

---

## 7. Board I/O

### Pin assignments (from `.qsf`)

| Signal | Pin(s) | Notes |
|---|---|---|
| `clk` | `PIN_23` | 50 MHz |
| `KEY[0]` | `PIN_88` | Display select bit 0 |
| `KEY[1]` | `PIN_89` | Display select bit 1 |
| `KEY[2]` | `PIN_90` | **Start / run** — one press runs the whole program |
| `KEY[3]` | `PIN_91` | **Reset** — held level |
| `KEY[4]` | `PIN_25` | **MMIO input button** (read from address 30) |
| `SEG[0..7]` | `PIN_128,121,125,129,132,126,124,127` | 7-segment + DP |
| `DIG[0..3]` | `PIN_133,135,136,137` | Digit select |
| `LEDG[0..3]` | `PIN_87,86,85,84` | MMIO output (active-LOW) |
| `UART_RXD` | `PIN_115` | Serial program loading (3.3-V LVCMOS) — see §9 |

All I/O standard `3.3-V LVCMOS`. `set_false_path` is applied to `KEY[*]` in the
SDC since they are asynchronous push-buttons.

### 7-segment display

`seg7_display.v` time-multiplexes 4 digits using `refresh_counter[18:17]`.

* **Value shown:** the low 16 bits of a selectable register. `KEY[0]` steps the
  selection through `$0`…`$31` (one press = next register, wrapping; it powers up
  on `$5`). Holding `KEY[1]` shows the **selected register index** instead of its
  value. Both keys are debounced and `KEY[0]` is edge-detected, so one press is
  exactly one step.
* **Decimal point:** lights on the leftmost digit when the **sticky overflow
  flag** is set.
* **Polarity:** this board's segments and digit selects are **active-LOW**, so
  `seg7_display.v` inverts both (`seg = ~seg_active_high`,
  `an = ~(4'b0001 << digit_sel)`). This was determined empirically on hardware.
  `seg7_decoder.v` itself produces active-HIGH patterns.

### UART program loader

| Module | Detail |
|---|---|
| `uart_rx.v` | 8N1, `CLK_FREQ = 50_000_000`, `BAUD_RATE = 9600` → ~5,208 clocks/bit. Samples each bit at its **midpoint**; the start bit is confirmed at half a bit period to reject glitches. |
| `uart_loader.v` | Shifts bytes **big-endian** into a 32-bit assembly register (first byte = MSB). Every 4th byte pulses a one-cycle `imem` write, then advances the word address. |

The loader runs entirely on the **raw 50 MHz clock** — baud timing must be
precise. There is no CDC hazard for the memory contents because `imem`'s write
port has its own `wr_clk` input, also fed from the raw clock, so write data and
write clock are in the same domain.

The loader counts up to word address 4095 (a full 4,096-word image =
16,384 bytes ≈ 17 s at 9600 baud), then asserts `load_done` and resets its
address counter for the next transfer. While `loading` is high, `KEY[2]` is
ignored.

> The loader targets the full 4,096-word image — see §8 for the assembler's
> padding and `uart_loader.v`'s byte handling.

---

## 8. Assembler (`assembler.py`)

A single-file Python 3 assembler with no dependencies.

**Usage:**

```bash
python3 assembler.py program.asm
```

**Outputs** (written to the current directory):

* `program.hex` — 4,096 lines, one 32-bit hex word per line, zero-padded.
* `data.hex` — 512 lines, zero-padded.

**Source syntax:**

```asm
# comments start with '#' and run to end of line

        ADDI $1, $0, 0        # R-type:  ADD $rd, $rs, $rt
        ADDI $3, $0, 10       # I-type:  ADDI $rt, $rs, imm
        LW   $5, 0($1)        # memory:  LW/SW $rt, offset($rs)
        SW   $2, 10($0)
loop:   BEQ  $3, $0, done     # branch:  BEQ/BNE $rs, $rt, label
        BNE  $1, $2, loop
        JAL  myfunc           # jump:    JAL label / JR $rs
        JR   $31
        MULT $1, $2           # MULT/DIV $rs, $rt
        DIV  $1, $2
        MFHI $3               # MFHI/MFLO $rd
        MFLO $4
        HALT                  # no operands

.data                         # everything after this is data memory
        1                     # mem[0]
        0x0A                  # mem[1] (hex allowed)
```

**Assembler behaviour worth knowing:**

* Labels may stand alone on a line or prefix an instruction.
* Immediates accept decimal or `0x`-prefixed hex.
* `.data` splits the file; values are assigned to addresses 0, 1, 2, … in order.
  Data labels are parsed and reported but **not yet usable as operands** in
  `LW`/`SW` (reserved for future symbolic addressing).
* **A trailing `HALT` is appended automatically** if the source doesn't end with
  one. This is important: in auto-run mode the FSM never returns to `IDLE`, so a
  program without a stop would run off the end into zero padding (`opcode 0`,
  `funct 0` — not a valid R-type) and land in `TRAP`, polluting
  `illegal_opcode` with "program finished" events.
* Branch offsets are validated against the 16-bit signed range; `ADDI`
  immediates against the 16-bit signed range; `JAL` targets against the
  4,096-word memory depth.

---

## 9. Build & program workflow

1. **Write** a program (`program.asm`).
2. **Assemble:** `python3 assembler.py program.asm` → `program.hex`, `data.hex`.
   Ensure both files sit **in the project root** (the `$readmemh` paths are
   relative to the Quartus working directory).
3. **Compile** in Quartus Prime (25.1std Lite): open `Mips_Multi_Cycle_Cpu.qpf`,
   run Analysis & Synthesis → Fitter → Assembler → TimeQuest.
4. **Program the device** with `output_files/Mips_Multi_Cycle_Cpu.sof` via the
   Programmer (JTAG), or use `output_files/Mips_Multi_Cycle_Cpu.cdf`.
5. **Run:** press **`KEY[2]`** once to run the entire program.
   **`KEY[3]`** resets. Flip `KEY[1:0]` to change which register is displayed.

> The `.qsf` used to reference three `.spf` probe-snapshot files for the ISSP
> debugger; those snapshots and the cores they attached to were removed (§10).

### Alternative: UART loading

`uart_loader.v` can write `imem` at runtime over serial. `UART_RXD` is now pinned
at `PIN_115` (3.3-V LVCMOS, see §7), so wiring a host-side sender for the padded
`program.hex` bytes is all that remains to use it. While a transfer is in flight
`loading` is high and `KEY[2]` is ignored.

### Simulation

A Questa testbench drives `cpu_top_mc` directly with `program.hex`/`data.hex`,
pulses `start`, and checks the run: HALT reached, `MEM2` visited, no `TRAP`,
and `mem[10] = $2 = 55` for the default sum program. (The board-level
`top_cpu_mc` is not simulated — its debounce/divider/display logic is
board-only. Quartus can also emit a gate-level netlist under
`simulation/questa/`, gitignored.)

---

## 10. Debugging (ISSP removed)

Five `altera_in_system_sources_probes` cores used to be instantiated in
`top_cpu_mc.v` (register file halves, data-memory halves, and a status word),
guarded by the `CPU_ISSP` macro. They were the area hog — 4 × 480 + 312 bits
of shadow registers on top of the register file — and Quartus had to duplicate
the whole `dmem` into flip-flops to serve the 32 fixed memory taps. After the
synchronous-`dmem` + `MEM2` fix freed ~2,500 LEs, the cores and their
Platform Designer sources (`cpu_issp_*/*.qsys`, `.qsys_edit/`, `.spf`
snapshots, `.qsf` `QIP_FILE` lines) were removed outright. They remain
recoverable from git history if live probing is ever needed again.

**On-board debugging now:** the 7-segment display shows any register's low
16 bits (`KEY[0]` steps `$0`–`$31`, `KEY[1]` held shows the index), and the
decimal point lights when the sticky overflow flag latches. FSM-state and
HALT/TRAP diagnosis (`state == 6` = illegal instruction, `state == 9` = HALT)
is done in simulation via the `debug_state` port.

---

## 11. Test programs

### Default program (`program.hex` + `data.hex`)

The default program (`program.asm`) sums `data[0..9]` (1 through 10) and stores
the result (55 = `0x37`) at `mem[10]`. Re-assembling it reproduces the checked-in
`program.hex` / `data.hex` byte-for-byte. Disassembled:

```asm
        ADDI $1, $0, 0        # $1 = pointer = 0
        ADDI $2, $0, 0        # $2 = sum = 0
        ADDI $3, $0, 10       # $3 = counter = 10
        ADDI $6, $0, 1        # $6 = constant 1
loop:   BEQ  $3, $0, done     # if counter == 0, exit
        LW   $5, 0($1)        # $5 = mem[pointer]
        ADD  $2, $2, $5       # sum += $5
        ADDI $1, $1, 1        # pointer++
        SUB  $3, $3, $6       # counter--
        BEQ  $0, $0, loop     # unconditional back-edge
done:   SW   $2, 10($0)       # mem[10] = sum
        HALT                  # explicit stop (present in program.asm)
```

Expected: `$1 = 10`, `$2 = 55`, `$3 = 0`, `mem[10] = 0x37`.

### Alternate images

* **`program(sum).asm` → `program(sum).hex` + `data(sum).hex`** — walks
  `data[0..]` counting with `$1` and stops when the index reaches the value
  loaded from `mem[6]` (= 6), using a `JAL` as the back-edge and ending in a
  `BEQ $0,$0,-1` spin loop.
* **`program(big_test).asm` → `program(big_test).hex` + `data(big_test).hex`** —
  exercises `AND`, `OR`, and both directions of `SLT` on `$1 = 12`, `$2 = 10`,
  then a conditional branch over `ADDI $7, $0, 999`, ending in a spin loop. In
  practice `$1 != $2`, so the branch is never taken. Useful for verifying the SLT
  fix that motivated the clock divider.

Both alternate images were regenerated from these sources: they are now padded to
the full 4,096 words and carry one trailing `HALT` appended by the assembler
(unreachable, since both end in a spin loop). `program(big_test).hex` also has a
corrected branch offset — the original image targeted padding, a leftover from
the pre-`PC+1` branch convention.

To use an alternate image, copy it over `program.hex` / `data.hex` (or adjust the
`$readmemh` filenames) and recompile.

---

## 12. Caveats

The nine issues previously documented here are all addressed:

* **1** — `UART_RXD` is pinned at `PIN_115` (3.3-V LVCMOS) in the `.qsf` (§7).
* **2–5** — the stale comments and the 7-bit PC literals were corrected in
  `top_cpu_mc.v`, `cpu_top_mc.v`, `regfile.v`, and `uart_loader.v`.
* **6** — the ISSP probe cores are now removed outright (first made
   compile-time optional via the `CPU_ISSP` macro, then deleted with the `dmem`
   tap removal — see §10).
* **7** — `dmem` grew to 512 words and MMIO moved to addresses 510/511 (§6).
* **8** — `program.asm`, `program(sum).asm`, and `program(big_test).asm` are
  checked in, with the matching `.hex` images regenerated (§11).
* **9** — the 7-segment display can now show any register, not just `$5`–`$8` (§7).

What remains worth knowing:

1. **Verified by synthesis and simulation, not on hardware.** Analysis &
   Synthesis, the Fitter, and TimeQuest all pass from this state (52 % logic,
   +13.470 ns setup slack, §1), and a Questa testbench runs the sum program
   end-to-end (HALT in 267 cycles, `mem[10] = $2 = 55`, `MEM2` visited, no
   `TRAP`). But the new `dmem`/`MEM2` timing has not been exercised on the
   board — the display select, the 512-word `dmem`, and the MMIO move to
   510/511 should be checked on hardware.
2. **Live probing was removed, not just disabled.** The ISSP cores were first
   made compile-time optional via the `CPU_ISSP` macro, then deleted outright
   with the `dmem` tap removal (§10) — the 52 % fit carries no debug overhead,
   at the cost that the old `.spf` snapshots no longer have anything to attach
   to.
3. **Two MMIO addresses stay partly consumed.** `mem[510]` is unreadable via
   `LW` and `mem[511]` is unwritable via `SW` (§6).
4. **`cpu_clk` is not separately constrained.** `timing_constraints.sdc` only
   declares the 50 MHz `clk`; the divided clock is folded into that domain,
   which is conservative (§1).

---

## 13. Design history

The old `.v.bak` snapshots and the single-cycle sources were removed during the
repository cleanup. They are **not lost** — they still exist in git history, in
the baseline commit `c64214a` ("Baseline: state before cleanup"). To recover any
of them:

```bash
git show c64214a:control_unit.v.bak      # view a single file
git checkout c64214a -- top_cpu.v        # restore it into the working tree
```

The design evolved in five stages:

1. **Single-cycle core.** Every instruction completed in one clock via a purely
   combinational control unit (`control_unit.v`, `cpu_top.v`, `top_cpu.v`). The
   PC was 7 bits (128 instructions). Memory was initialized from a hand-written
   `case` statement in `imem.v`.
2. **Multi-cycle datapath.** Replaced by an FSM-driven datapath
   (`control_unit_mc.v`, `cpu_top_mc.v`) with intermediate registers
   (`ir_reg`, `a_reg`, `b_reg`, …) reused across cycles. Each instruction ended
   back in `IDLE`. The ALU gained the `Ov` output for signed overflow.
3. **Auto-run mode.** Instructions began returning to `IF` instead of `IDLE`, so
   one `KEY[2]` press runs the whole program; `IDLE` became a one-time entry
   state. The PC widened to 12 bits (4,096 instructions).
4. **Instruction-set growth.** Added `MULT`/`DIV` (shared 32-cycle shift-add /
   restoring-division loop), `MFHI`/`MFLO`, `JAL`, `HALT`, and the sticky
   `overflow` / `illegal_opcode` flags; `TRAP` was introduced for unrecognized
   instructions.
5. **I/O and tooling.** Memory-mapped I/O (originally button at address 30 and
   LEDs at 31, later moved to 510/511 when `dmem` grew), a 9600-baud UART program
   loader, and finally the cleanup that removed the single-cycle legacy files,
   `.bak` snapshots, and duplicate artifacts.
6. **Synchronous `dmem` + `MEM2`.** `dmem`'s 32 fixed-address debug taps had been
   forcing Quartus to shadow the whole 512-word memory into flip-flops
   (~5,790 LEs, 92 % full, and masking a latent Error 276003 once the taps were
   removed). The read path is now registered so Quartus infers 2× M9K, with a
   new `MEM2` FSM state absorbing the extra cycle (LW = IF, ID, EX, MEM, MEM2,
   WB) — fit dropped to ~3,279 LEs (52 %), verified by Questa sim.

---

## 14. Quick reference

```
Assemble:   python3 assembler.py program.asm
Build:      quartus_sh --flow compile Mips_Multi_Cycle_Cpu   (or use the Quartus GUI)
Program:    output_files/Mips_Multi_Cycle_Cpu.sof via JTAG
Run:        KEY[2]   (one press = whole program)
Reset:      KEY[3]
Display:    KEY[0] steps the shown register ($0-$31); KEY[1] held shows its index
MMIO:       LW from address 510 = KEY[4] button;  SW to address 511 = LEDG[3:0]
Halt:       HALT instruction (opcode 111111), or a BEQ $0,$0,-1 spin loop
```
