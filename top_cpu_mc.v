//====================================================================
// top_cpu_mc.v  (board top-level for the MULTI-CYCLE CPU)
//
// Same board wiring as top_cpu.v (KEY[2] via debounce+edge_detector,
// same SEG/DIG display), but instantiates cpu_top_mc instead of
// cpu_top, and now KEY[2] means "run the next full instruction"
// (auto-runs internal IF/ID/EX/MEM/WB cycles on CLOCK_50) rather than
// "advance one cycle."
//
// NOTE: PC is now 13 bits (was 7) - the ISSP .spf needs rebuilding to
// match this and the current register/memory/status signal set. See
// project notes for the planned full 32-register/32-memory .spf rebuild.
//====================================================================

module top_cpu_mc (
    input        clk,      // PIN_23
    input  [4:0] KEY,       // PIN_88,89,90,91,25 - KEY[4] is NEW: previously
                             // unused, now the memory-mapped input button
    output [7:0] SEG,       // PIN_128,121,125,129,132,126,124,127
    output [3:0] DIG,       // PIN_133,135,136,137
    output [3:0] LEDG,       // NEW: PIN_87,86,85,84 - memory-mapped output
    input        UART_RXD    // NEW: PIN_115 - program loading over serial
);

    //--------------------------------------------------------------
    // Clock divider for the CPU's own logic. Timing analysis showed
    // the real critical path is ~23.75ns (Fmax 42.1MHz), which is
    // longer than CLOCK_50's 20ns period - that's the root cause of
    // the wrong SLT results on hardware. Dividing by 4 gives the CPU
    // an 80ns period per cycle, over 3x the margin it actually needs.
    // Debounce stays on raw clk since its timing is calibrated in
    // real milliseconds and shouldn't change.
    //--------------------------------------------------------------
    reg [1:0] clkdiv = 2'd0;
    always @(posedge clk)
        clkdiv <= clkdiv + 2'd1;
    wire cpu_clk = clkdiv[1]; // CLOCK_50 / 4

    wire key2_raw = ~KEY[2];
    wire key2_debounced;

    debounce db_step (.clk(clk), .btn_in(key2_raw), .btn_out(key2_debounced));

    //--------------------------------------------------------------
    // NEW: reset button on KEY[3]. Debounced on the fast clk like
    // KEY[2], then synchronized into the slow cpu_clk domain the same
    // safe way - but as a LEVEL (rst held = held reset), not an
    // edge-detected pulse, since reset should stay active the whole
    // time the button is down, not just for one cycle.
    //--------------------------------------------------------------
    wire key3_raw = ~KEY[3];
    wire key3_debounced;
    debounce db_rst (.clk(clk), .btn_in(key3_raw), .btn_out(key3_debounced));

    reg rst_sync1 = 1'b0, rst_sync2 = 1'b0;
    always @(posedge cpu_clk) begin
        rst_sync1 <= key3_debounced;
        rst_sync2 <= rst_sync1;
    end
    wire rst = rst_sync2;

    //--------------------------------------------------------------
    // NEW: KEY[4] - the memory-mapped input button. Debounced on the
    // fast clk like the others; the actual crossing into cpu_clk
    // happens inside cpu_top_mc.v's own 2-FF synchronizer (btn_sync1/
    // btn_sync2), so this module just needs to hand off a clean level.
    //--------------------------------------------------------------
    wire key4_raw = ~KEY[4];
    wire key4_debounced;
    debounce db_mmio_btn (.clk(clk), .btn_in(key4_raw), .btn_out(key4_debounced));

    //--------------------------------------------------------------
    // NEW: this board's LEDs are active-LOW (confirmed on hardware -
    // all 4 lit at power-up when led_reg was 0000, only 2 lit after
    // writing 1100 - exactly inverted from what active-high would
    // show). Invert right here, at the pin - cpu_top_mc.v itself
    // stays board-agnostic and logically correct (mmio_led_out=1100
    // genuinely means "bits 3,2 on"; this is the only place that
    // needs to know the physical polarity quirk.
    //--------------------------------------------------------------
    wire [3:0] led_bus;
    assign LEDG = ~led_bus;

    //--------------------------------------------------------------
    // NEW: UART program loader. Runs entirely on the fast raw clk
    // (50MHz) - baud-rate timing needs to be precise. No CDC concern
    // for the imem write itself, since imem's write port has its own
    // dedicated wr_clk input (also fed from raw clk here) - the write
    // and the data being written are both registered in the SAME
    // clock domain as each other, so there's no cross-domain hazard
    // for the memory contents themselves.
    //--------------------------------------------------------------
    wire [7:0] uart_byte;
    wire uart_byte_ready;
    uart_rx #(.CLK_FREQ(50_000_000), .BAUD_RATE(9600)) uart_receiver (
        .clk(clk), .rx(UART_RXD),
        .data_out(uart_byte), .byte_ready(uart_byte_ready)
    );

    wire loader_wr_en;
    wire [11:0] loader_wr_addr;  // 12 bits
    wire [31:0] loader_wr_data;
    wire uart_loading, uart_load_done;
    uart_loader program_loader (
        .clk(clk), .byte_ready(uart_byte_ready), .byte_in(uart_byte),
        .wr_en(loader_wr_en), .wr_addr(loader_wr_addr), .wr_data(loader_wr_data),
        .loading(uart_loading), .load_done(uart_load_done)
    );

    //--------------------------------------------------------------
    // key2_debounced changes in the FAST clk domain but needs to
    // start an action in the SLOW cpu_clk domain. A single-cycle
    // pulse generated in the fast domain (the old edge_detector
    // approach) could be too narrow for the slow clock to ever
    // sample - a real clock-domain-crossing hazard now that there
    // are two different clocks. Fix: synchronize the LEVEL signal
    // into cpu_clk with two flip-flops (standard CDC practice), then
    // edge-detect it there, so the pulse we generate is a full
    // cpu_clk-wide pulse, guaranteed to be seen.
    //--------------------------------------------------------------
    reg sync1 = 1'b0, sync2 = 1'b0, sync2_prev = 1'b0;
    always @(posedge cpu_clk) begin
        sync1      <= key2_debounced;
        sync2      <= sync1;
        sync2_prev <= sync2;
    end
    // NEW: ignore KEY[2] entirely while a UART transfer is mid-flight -
    // prevents accidentally running a half-loaded program
    wire start_pulse = (sync2 & ~sync2_prev) & ~uart_loading;

    wire [31:0] r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12, r13, r14, r15, r16, r17, r18, r19, r20, r21, r22, r23, r24, r25, r26, r27, r28, r29, r30, r31;
    wire [11:0] pc_debug;  // 12 bits (4,096 instructions)
                           // NOTE: this widens probe_bus_lo below to 492
                           // bits (was 487, sized for the original 7-bit
                           // PC) - cpu_issp_lo's .probe port must be
                           // regenerated to 492 bits in Quartus IP Catalog
                           // before this will compile - see hardware steps
    wire [31:0] cur_instr;
    wire [4:0]  dmem_addr;
    wire [31:0] dmem_wdata, dmem_rdata;
    wire        dmem_we;
    wire [31:0] mem0, mem1, mem2, mem3, mem4, mem5, mem6, mem7, mem8, mem9, mem10;
    wire [31:0] mem11, mem12, mem13, mem14, mem15, mem16, mem17, mem18, mem19, mem20;
    wire [31:0] mem21, mem22, mem23, mem24, mem25, mem26, mem27, mem28, mem29, mem30, mem31;
    wire [3:0]  fsm_state; // WIDENED to 4 bits for MULT/DIV's new MD_LOOP/MD_DONE states
    wire        overflow_flag; // NEW: sticky signed-overflow flag
    wire        illegal_opcode_flag; // NEW: sticky illegal-opcode/TRAP flag, now wired to an ISSP
    wire [31:0] hi_debug, lo_debug;  // NEW: HI/LO architectural registers, now wired to an ISSP

    cpu_top_mc mycpu (
        .clk(cpu_clk),
        .rst(rst),
        .start(start_pulse),
        .debug_reg1(r1), .debug_reg2(r2), .debug_reg3(r3), .debug_reg4(r4),
        .debug_reg5(r5), .debug_reg6(r6), .debug_reg7(r7), .debug_reg8(r8),
        .debug_reg9(r9), .debug_reg10(r10), .debug_reg11(r11), .debug_reg12(r12),
        .debug_reg13(r13), .debug_reg14(r14), .debug_reg15(r15), .debug_reg16(r16),
        .debug_reg17(r17), .debug_reg18(r18), .debug_reg19(r19), .debug_reg20(r20),
        .debug_reg21(r21), .debug_reg22(r22), .debug_reg23(r23), .debug_reg24(r24),
        .debug_reg25(r25), .debug_reg26(r26), .debug_reg27(r27), .debug_reg28(r28),
        .debug_reg29(r29), .debug_reg30(r30), .debug_reg31(r31),
        .debug_pc(pc_debug),
        .debug_instruction(cur_instr),
        .debug_dmem_addr(dmem_addr),
        .debug_dmem_write_data(dmem_wdata),
        .debug_dmem_write_enable(dmem_we),
        .debug_dmem_read_data(dmem_rdata),
        .debug_dmem0(mem0), .debug_dmem1(mem1),
        .debug_dmem2(mem2), .debug_dmem3(mem3),
        .debug_dmem4(mem4), .debug_dmem5(mem5),
        .debug_dmem6(mem6), .debug_dmem7(mem7),
        .debug_dmem8(mem8), .debug_dmem9(mem9),
        .debug_dmem10(mem10),
        .debug_dmem11(mem11), .debug_dmem12(mem12),
        .debug_dmem13(mem13), .debug_dmem14(mem14),
        .debug_dmem15(mem15), .debug_dmem16(mem16),
        .debug_dmem17(mem17), .debug_dmem18(mem18),
        .debug_dmem19(mem19), .debug_dmem20(mem20),
        .debug_dmem21(mem21), .debug_dmem22(mem22),
        .debug_dmem23(mem23), .debug_dmem24(mem24),
        .debug_dmem25(mem25), .debug_dmem26(mem26),
        .debug_dmem27(mem27), .debug_dmem28(mem28),
        .debug_dmem29(mem29), .debug_dmem30(mem30),
        .debug_dmem31(mem31),
        .debug_state(fsm_state),
        .debug_overflow(overflow_flag),
        .debug_illegal_opcode(illegal_opcode_flag),
        .debug_hi(hi_debug),
        .debug_lo(lo_debug),
        .mmio_btn_in(key4_debounced),
        .mmio_led_out(led_bus),
        .uart_wr_clk(clk),
        .uart_wr_en(loader_wr_en),
        .uart_wr_addr(loader_wr_addr),
        .uart_wr_data(loader_wr_data)
    );

    wire [1:0] sel = KEY[1:0];
    wire [31:0] shown =
        (sel == 2'b00) ? r5 :
        (sel == 2'b01) ? r6 :
        (sel == 2'b10) ? r7 : r8;

    seg7_display disp (
        .clk(clk),
        .hex_value(shown[15:0]),
        .cout(overflow_flag), // NEW: decimal point lights up when overflow has latched
        .seg(SEG),
        .an(DIG)
    );

    //================================================================
    // ISSP instances - 5 instances. NOTE: ALTSOURCE_PROBE has a hard
    // PROBE_WIDTH limit of 511 bits (confirmed by a real Quartus
    // Analysis & Synthesis error: 16 words x 32 bits = 512 bits was
    // rejected). So each register/memory instance below holds 15
    // words (480 bits), not 16 - the 4 words that don't fit
    // ($30, $31, mem30, mem31) are folded into cpu_issp_status
    // instead, which has plenty of headroom.
    //   cpu_issp_regs_lo   - registers $0-$14   (480 bits)
    //   cpu_issp_regs_hi   - registers $15-$29  (480 bits)
    //   cpu_issp_dmem_lo   - memory[0..14]      (480 bits)
    //   cpu_issp_dmem_hi   - memory[15..29]     (480 bits)
    //   cpu_issp_status    - PC, FSM state, overflow, illegal-opcode,
    //                        HI, LO, current instruction, live dmem
    //                        transaction, plus $30/$31/mem30/mem31
    //                        (312 bits)
    // Word n occupies bits [32*n+31 : 32*n] within its instance.
    //================================================================

    //--------------------------------------------------------------
    // cpu_issp_regs_lo: $0-$14. $0 is architecturally hardwired to
    // zero in MIPS (no real debug port for it) - tied to a constant
    // here so it's visible, and reading 0 back is a sanity check.
    //--------------------------------------------------------------
    wire [479:0] probe_bus_regs_lo = {
        r14, r13, r12, r11, r10, r9, r8,
        r7, r6, r5, r4, r3, r2, r1, 32'd0
    };

    cpu_issp_regs_lo inst_issp_regs_lo (
        .source (),
        .probe  (probe_bus_regs_lo)
    );

    //--------------------------------------------------------------
    // cpu_issp_regs_hi: $15-$29 ($30/$31 moved into cpu_issp_status)
    //--------------------------------------------------------------
    wire [479:0] probe_bus_regs_hi = {
        r29, r28, r27, r26, r25, r24, r23,
        r22, r21, r20, r19, r18, r17, r16, r15
    };

    cpu_issp_regs_hi inst_issp_regs_hi (
        .source (),
        .probe  (probe_bus_regs_hi)
    );

    //--------------------------------------------------------------
    // cpu_issp_dmem_lo: memory[0..14]
    //--------------------------------------------------------------
    wire [479:0] probe_bus_dmem_lo = {
        mem14, mem13, mem12, mem11, mem10, mem9, mem8,
        mem7, mem6, mem5, mem4, mem3, mem2, mem1, mem0
    };

    cpu_issp_dmem_lo inst_issp_dmem_lo (
        .source (),
        .probe  (probe_bus_dmem_lo)
    );

    //--------------------------------------------------------------
    // cpu_issp_dmem_hi: memory[15..29] (mem30/mem31 moved into
    // cpu_issp_status)
    //--------------------------------------------------------------
    wire [479:0] probe_bus_dmem_hi = {
        mem29, mem28, mem27, mem26, mem25, mem24, mem23,
        mem22, mem21, mem20, mem19, mem18, mem17, mem16, mem15
    };

    cpu_issp_dmem_hi inst_issp_dmem_hi (
        .source (),
        .probe  (probe_bus_dmem_hi)
    );

    //--------------------------------------------------------------
    // cpu_issp_status: PC, FSM state, sticky overflow/illegal-opcode
    // flags, HI/LO, currently-fetched instruction, live dmem
    // transaction, plus the 4 leftover register/memory words that
    // didn't fit in the 15-word groups above ($30, $31, mem30, mem31).
    // 312 bits: 184 (original status fields) + 32*4 (leftover words)
    //--------------------------------------------------------------
    wire [311:0] probe_bus_status = {
        pc_debug,             // [311:300]
        fsm_state,             // [299:296]
        overflow_flag,          // [295]
        illegal_opcode_flag,     // [294]
        hi_debug,                // [293:262]
        lo_debug,                 // [261:230]
        cur_instr,                 // [229:198]
        dmem_addr,                  // [197:193]
        dmem_wdata,                  // [192:161]
        dmem_we,                      // [160]
        dmem_rdata,                    // [159:128]
        r30,                            // [127:96]
        r31,                             // [95:64]
        mem30,                            // [63:32]
        mem31                              // [31:0]
    };

    cpu_issp_status inst_issp_status (
        .source (),
        .probe  (probe_bus_status)
    );

endmodule