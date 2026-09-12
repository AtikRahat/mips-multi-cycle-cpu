//====================================================================
// top_cpu_mc.v  (board top-level for the MULTI-CYCLE CPU)
//
// Board wiring, SEG/DIG display, clock divider, debounce and MMIO, with
// cpu_top_mc as the CPU. After reset, one KEY[2] press auto-runs the
// whole program on cpu_clk; KEY[3] resets.
//
// NOTE: PC is 12 bits (was 7) - 4,096 instructions.
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
    // longer than clk's 20ns period - that's the root cause of
    // the wrong SLT results on hardware. Dividing by 4 gives the CPU
    // an 80ns period per cycle, over 3x the margin it actually needs.
    // Debounce stays on raw clk since its timing is calibrated in
    // real milliseconds and shouldn't change.
    //--------------------------------------------------------------
    reg [1:0] clkdiv = 2'd0;
    always @(posedge clk)
        clkdiv <= clkdiv + 2'd1;
    wire cpu_clk = clkdiv[1]; // 50 MHz / 4

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
    wire [31:0] cur_instr;
    wire [4:0]  dmem_addr;
    wire [31:0] dmem_wdata, dmem_rdata;
    wire        dmem_we;
    wire [3:0]  fsm_state; // WIDENED to 4 bits for MULT/DIV's new MD_LOOP/MD_DONE states
    wire        overflow_flag; // sticky signed-overflow flag
    wire        illegal_opcode_flag; // sticky illegal-opcode/TRAP flag
    wire [31:0] hi_debug, lo_debug;  // HI/LO architectural registers

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

    //--------------------------------------------------------------
    // NEW: display register select. KEY[0] steps reg_sel through
    // $0..$31 (one press = next register, wrapping $31 -> $0);
    // KEY[1] held shows the register index instead of its value.
    // Both keys are debounced on the fast clk like the other buttons,
    // and KEY[0] is edge-detected so one press = one step.
    //--------------------------------------------------------------
    wire key0_raw = ~KEY[0];
    wire key1_raw = ~KEY[1];
    wire key0_debounced, key1_debounced;
    debounce db_sel0 (.clk(clk), .btn_in(key0_raw), .btn_out(key0_debounced));
    debounce db_sel1 (.clk(clk), .btn_in(key1_raw), .btn_out(key1_debounced));

    wire key0_pulse;
    edge_detector ed_sel0 (.clk(clk), .signal_in(key0_debounced), .pulse_out(key0_pulse));

    reg [4:0] reg_sel = 5'd5;   // start on $5, matching the old fixed view
    always @(posedge clk)
        if (key0_pulse)
            reg_sel <= reg_sel + 5'd1;

    // Only the displayed low 16 bits are muxed, to keep the added logic
    // small (the design is close to full); $0 reads as constant 0.
    wire [15:0] sel_lo =
        (reg_sel == 5'd0)  ? 16'd0  :
        (reg_sel == 5'd1)  ? r1[15:0]  : (reg_sel == 5'd2)  ? r2[15:0]  : (reg_sel == 5'd3)  ? r3[15:0]  :
        (reg_sel == 5'd4)  ? r4[15:0]  : (reg_sel == 5'd5)  ? r5[15:0]  : (reg_sel == 5'd6)  ? r6[15:0]  :
        (reg_sel == 5'd7)  ? r7[15:0]  : (reg_sel == 5'd8)  ? r8[15:0]  : (reg_sel == 5'd9)  ? r9[15:0]  :
        (reg_sel == 5'd10) ? r10[15:0] : (reg_sel == 5'd11) ? r11[15:0] : (reg_sel == 5'd12) ? r12[15:0] :
        (reg_sel == 5'd13) ? r13[15:0] : (reg_sel == 5'd14) ? r14[15:0] : (reg_sel == 5'd15) ? r15[15:0] :
        (reg_sel == 5'd16) ? r16[15:0] : (reg_sel == 5'd17) ? r17[15:0] : (reg_sel == 5'd18) ? r18[15:0] :
        (reg_sel == 5'd19) ? r19[15:0] : (reg_sel == 5'd20) ? r20[15:0] : (reg_sel == 5'd21) ? r21[15:0] :
        (reg_sel == 5'd22) ? r22[15:0] : (reg_sel == 5'd23) ? r23[15:0] : (reg_sel == 5'd24) ? r24[15:0] :
        (reg_sel == 5'd25) ? r25[15:0] : (reg_sel == 5'd26) ? r26[15:0] : (reg_sel == 5'd27) ? r27[15:0] :
        (reg_sel == 5'd28) ? r28[15:0] : (reg_sel == 5'd29) ? r29[15:0] : (reg_sel == 5'd30) ? r30[15:0] :
                             r31[15:0];

    wire [15:0] disp_value = key1_debounced ? {11'b0, reg_sel} : sel_lo;

    seg7_display disp (
        .clk(clk),
        .hex_value(disp_value),
        .cout(overflow_flag), // decimal point lights up when overflow has latched
        .seg(SEG),
        .an(DIG)
    );

endmodule