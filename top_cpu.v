//====================================================================
// top_cpu.v  (THREE ISSP instances: all 32 registers split across
// two cores, plus a third core for instruction/memory visibility)
//====================================================================

module top_cpu (
    input        clk,      // PIN_23
    input  [3:0] KEY,       // PIN_88,89,90,91
    output [7:0] SEG,       // PIN_128,121,125,129,132,126,124,127
    output [3:0] DIG        // PIN_133,135,136,137
);

    wire key2_raw = ~KEY[2];
    wire key2_debounced, step_pulse;

    debounce db_step (.clk(clk), .btn_in(key2_raw), .btn_out(key2_debounced));
    edge_detector ed_step (.clk(clk), .signal_in(key2_debounced), .pulse_out(step_pulse));

    wire [31:0] r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12, r13, r14, r15, r16, r17, r18, r19, r20, r21, r22, r23, r24, r25, r26, r27, r28, r29, r30, r31;
    wire [6:0] pc_debug;   // was [4:0] - truncated the widened 7-bit PC, fixed
    wire [31:0] cur_instr;
    wire [4:0]  dmem_addr;
    wire [31:0] dmem_wdata, dmem_rdata;
    wire        dmem_we;
    wire [31:0] mem0, mem1, mem2, mem3, mem4, mem5, mem6, mem7, mem8, mem9, mem10;
    wire [31:0] mem11, mem12, mem13, mem14, mem15, mem16, mem17, mem18, mem19, mem20;
    wire [31:0] mem21, mem22, mem23, mem24, mem25, mem26, mem27, mem28, mem29, mem30, mem31;

    cpu_top mycpu (
        .clk(clk),
        .step_enable(step_pulse),
        .debug_reg1(r1),
        .debug_reg2(r2),
        .debug_reg3(r3),
        .debug_reg4(r4),
        .debug_reg5(r5),
        .debug_reg6(r6),
        .debug_reg7(r7),
        .debug_reg8(r8),
        .debug_reg9(r9),
        .debug_reg10(r10),
        .debug_reg11(r11),
        .debug_reg12(r12),
        .debug_reg13(r13),
        .debug_reg14(r14),
        .debug_reg15(r15),
        .debug_reg16(r16),
        .debug_reg17(r17),
        .debug_reg18(r18),
        .debug_reg19(r19),
        .debug_reg20(r20),
        .debug_reg21(r21),
        .debug_reg22(r22),
        .debug_reg23(r23),
        .debug_reg24(r24),
        .debug_reg25(r25),
        .debug_reg26(r26),
        .debug_reg27(r27),
        .debug_reg28(r28),
        .debug_reg29(r29),
        .debug_reg30(r30),
        .debug_reg31(r31),
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
        .debug_dmem31(mem31)
    );

    wire [1:0] sel = KEY[1:0];
    wire [31:0] shown =
        (sel == 2'b00) ? r5 :
        (sel == 2'b01) ? r6 :
        (sel == 2'b10) ? r7 : r8;

    seg7_display disp (
        .clk(clk),
        .hex_value(shown[15:0]),
        .cout(1'b0),
        .seg(SEG),
        .an(DIG)
    );

    //--------------------------------------------------------------
    // ISSP #1: PC + registers $1-$15  (485 bits)
    //   probe[6:0]    = PC (widened to 7 bits, supports up to 128 instructions)
    //   probe[38:7]   = $1
    //   probe[70:39]  = $2
    //   ... increasing by 32 bits per register, up to ...
    //   probe[486:455]= $15
    //--------------------------------------------------------------
    wire [486:0] probe_bus_lo = {r15, r14, r13, r12, r11, r10, r9, r8, r7, r6, r5, r4, r3, r2, r1, pc_debug};

    cpu_issp_lo inst_issp_lo (
        .source (),
        .probe  (probe_bus_lo)
    );

    //--------------------------------------------------------------
    // ISSP #2: registers $16-$30  (480 bits - $31 moved to ISSP #3,
    // since 16 full registers = 512 bits, exceeding the real 511-bit
    // hardware limit by exactly 1 bit)
    //   probe[31:0]    = $16
    //   probe[63:32]   = $17
    //   ... increasing by 32 bits per register, up to ...
    //   probe[479:448] = $30
    //--------------------------------------------------------------
    wire [479:0] probe_bus_hi = {r30, r29, r28, r27, r26, r25, r24, r23, r22, r21, r20, r19, r18, r17, r16};

    cpu_issp_hi inst_issp_hi (
        .source (),
        .probe  (probe_bus_hi)
    );

    //--------------------------------------------------------------
    // ISSP #3: register $31, current instruction, live memory
    // transaction, and permanent snapshot of memory[0..10] (486 bits)
    //   probe[31:0]    = $31
    //   probe[63:32]   = current instruction
    //   probe[95:64]   = dmem write data
    //   probe[100:96]  = dmem address
    //   probe[101]     = dmem write enable
    //   probe[133:102] = dmem read data
    //   probe[165:134] = memory[0]
    //   probe[197:166] = memory[1]
    //   probe[229:198] = memory[2]
    //   probe[261:230] = memory[3]
    //   probe[293:262] = memory[4]
    //   probe[325:294] = memory[5]
    //   probe[357:326] = memory[6]
    //   probe[389:358] = memory[7]
    //   probe[421:390] = memory[8]
    //   probe[453:422] = memory[9]
    //   probe[485:454] = memory[10]
    //   (25 bits of headroom left below the 511-bit ISSP ceiling)
    //--------------------------------------------------------------
    wire [485:0] probe_bus_mem = {
        mem10, mem9, mem8, mem7, mem6, mem5, mem4,
        mem3, mem2, mem1, mem0,
        dmem_rdata, dmem_we, dmem_addr, dmem_wdata,
        cur_instr, r31
    };

    cpu_issp_mem inst_issp_mem (
        .source (),
        .probe  (probe_bus_mem)
    );

    //--------------------------------------------------------------
    // ISSP #4 (NEW - must be generated in Quartus's IP Catalog before
    // this compiles - see project notes): memory[11..25] (480 bits)
    //   probe[31:0]    = memory[11]
    //   probe[63:32]   = memory[12]
    //   ... increasing by 32 bits per word, up to ...
    //   probe[479:448] = memory[25]
    //--------------------------------------------------------------
    wire [479:0] probe_bus_dmem2 = {
        mem25, mem24, mem23, mem22, mem21, mem20, mem19, mem18, mem17, mem16,
        mem15, mem14, mem13, mem12, mem11
    };

    cpu_issp_dmem2 inst_issp_dmem2 (
        .source (),
        .probe  (probe_bus_dmem2)
    );

    //--------------------------------------------------------------
    // ISSP #5 (NEW - must be generated in Quartus's IP Catalog before
    // this compiles - see project notes): memory[26..31] (192 bits)
    //   probe[31:0]    = memory[26]
    //   probe[63:32]   = memory[27]
    //   ... increasing by 32 bits per word, up to ...
    //   probe[191:160] = memory[31]
    //--------------------------------------------------------------
    wire [191:0] probe_bus_dmem3 = {
        mem31, mem30, mem29, mem28, mem27, mem26
    };

    cpu_issp_dmem3 inst_issp_dmem3 (
        .source (),
        .probe  (probe_bus_dmem3)
    );

endmodule