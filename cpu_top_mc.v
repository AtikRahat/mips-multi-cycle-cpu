//====================================================================
// cpu_top_mc.v  (multi-cycle datapath)
//
// Same idea as cpu_top.v, but the datapath is now reused across
// several clock cycles per instruction instead of doing everything
// in one shot. The extra registers below (ir_reg, pc_plus1_reg, a_reg,
// b_reg, branch_target_reg, alu_out_reg, mdr_reg) are what let the
// datapath "remember" values between cycles - control_unit_mc.v
// decides which of these load on any given clock edge.
//
// KEY[2] behavior: one press runs the WHOLE program - the FSM auto-runs
// IF/ID/EX/MEM/WB/... back-to-back on clk until HALT or TRAP, with no
// further button presses.
//====================================================================

module cpu_top_mc (
    input        clk,
    input        rst,       // NEW: level-held reset - PC and FSM state
                             // both return to 0/IDLE while held
    input        start,     // one-cycle pulse: begin next instruction

    // debug: architectural registers (same names/shape as cpu_top.v)
    output [31:0] debug_reg1,  output [31:0] debug_reg2,  output [31:0] debug_reg3,
    output [31:0] debug_reg4,  output [31:0] debug_reg5,  output [31:0] debug_reg6,
    output [31:0] debug_reg7,  output [31:0] debug_reg8,  output [31:0] debug_reg9,
    output [31:0] debug_reg10, output [31:0] debug_reg11, output [31:0] debug_reg12,
    output [31:0] debug_reg13, output [31:0] debug_reg14, output [31:0] debug_reg15,
    output [31:0] debug_reg16, output [31:0] debug_reg17, output [31:0] debug_reg18,
    output [31:0] debug_reg19, output [31:0] debug_reg20, output [31:0] debug_reg21,
    output [31:0] debug_reg22, output [31:0] debug_reg23, output [31:0] debug_reg24,
    output [31:0] debug_reg25, output [31:0] debug_reg26, output [31:0] debug_reg27,
    output [31:0] debug_reg28, output [31:0] debug_reg29, output [31:0] debug_reg30,
    output [31:0] debug_reg31,
    output [11:0] debug_pc,  // 12 bits = 4,096 instructions (16 M9K blocks, 14 spare on the 30-block budget)

    output [31:0] debug_instruction,
    output [4:0]  debug_dmem_addr,
    output [31:0] debug_dmem_write_data,
    output        debug_dmem_write_enable,
    output [31:0] debug_dmem_read_data,

    // NEW: which FSM state we're in right now - observable in simulation
    // via debug_state, doesn't exist in the single-cycle design
    // WIDENED from 3 to 4 bits to fit the new MULT/DIV states
    output [3:0]  debug_state,

    // NEW: sticky signed-overflow flag - set the first time ADD/SUB/
    // ADDI overflows, stays set until reset (KEY[3])
    output        debug_overflow,

    // NEW: sticky flag - set if the FSM ever halted on an unrecognized
    // instruction (see TRAP state in control_unit_mc.v)
    output        debug_illegal_opcode,

    // NEW: HI/LO registers, written by MULT/DIV, read by MFHI/MFLO
    output [31:0] debug_hi,
    output [31:0] debug_lo,

    // NEW: memory-mapped I/O. addr 510 (read) = the spare button,
    // addr 511 (write) = the 4 LEDs. Both are board-agnostic here -
    // top_cpu_mc.v maps them to actual KEY[4]/LEDG[] pins.
    input         mmio_btn_in,
    output [3:0]  mmio_led_out,

    // NEW: UART program-loader write port, passed straight through to
    // imem - the actual UART receiver hardware lives in top_cpu_mc.v,
    // this module just stays a plain pass-through, same as mmio_btn_in
    input         uart_wr_clk,
    input         uart_wr_en,
    input  [11:0] uart_wr_addr,
    input  [31:0] uart_wr_data
);

    //----------------------------------------------------------------
    // The "always-there" architectural PC. Frozen throughout
    // IF/ID/MEM/WB - only ever changes during the EX cycle.
    //----------------------------------------------------------------
    reg [11:0] pc = 12'd0;   // 12 bits (4,096 instructions)

    //----------------------------------------------------------------
    // Cross-cycle storage registers (the new part vs. single-cycle)
    //----------------------------------------------------------------
    reg [31:0] ir_reg;             // latched instruction
    reg [11:0] pc_plus1_reg;       // PC+1 at fetch time (return addr / fallthrough)
    reg [31:0] a_reg, b_reg;       // latched register-file read values
    reg [11:0] branch_target_reg;  // PC+1 + imm, computed in ID
    reg [31:0] alu_out_reg;        // latched ALU result (address or arithmetic result)
    reg [31:0] mdr_reg;            // latched memory read data

    // NEW: MULT/DIV registers
    reg [31:0] hi_reg, lo_reg;         // architectural HI/LO (MFHI/MFLO read these)
    reg [63:0] md_product_reg;         // MULT: 64-bit product accumulator.
                                        // DIV:  reused as the 64-bit
                                        // {remainder:quotient} working register
    reg [31:0] md_b_reg;               // MULT: abs(multiplicand). DIV: abs(divisor)
    reg        md_sign_reg;            // XOR of input signs - final negation flag
    reg [5:0]  md_counter;             // counts 0..31 (32 iterations)

    // NEW: memory-mapped I/O
    reg [3:0]  led_reg = 4'd0;         // holds current LED output state
    reg        btn_sync1 = 1'b0, btn_sync2 = 1'b0; // 2-FF synchronizer for
                                                    // the async button input

    //----------------------------------------------------------------
    // Instruction memory - only read during IF, address = pc (frozen
    // for the rest of the instruction, so this is safe to read anytime)
    //----------------------------------------------------------------
    wire [31:0] imem_instruction;
    imem instr_mem (
        .addr(pc), .instruction(imem_instruction),
        .wr_clk(uart_wr_clk), .wr_en(uart_wr_en),
        .wr_addr(uart_wr_addr), .wr_data(uart_wr_data)
    );

    //----------------------------------------------------------------
    // Field decode - done off the LATCHED ir_reg, since combinational
    // decode off imem_instruction would only be valid during IF, but
    // we need these fields all the way through ID/EX/MEM/WB
    //----------------------------------------------------------------
    wire [5:0]  opcode  = ir_reg[31:26];
    wire [4:0]  rs      = ir_reg[25:21];
    wire [4:0]  rt      = ir_reg[20:16];
    wire [4:0]  rd      = ir_reg[15:11];
    wire [5:0]  funct   = ir_reg[5:0];
    wire [15:0] imm16   = ir_reg[15:0];
    wire [31:0] imm_sext = {{16{imm16[15]}}, imm16};
    wire [11:0] jump_target = ir_reg[11:0]; // 12-bit range (4,096 words)

    //----------------------------------------------------------------
    // Control FSM
    //----------------------------------------------------------------
    wire [3:0] state;
    wire ir_write, pc_plus1_write, ab_write, branch_target_write;
    wire alu_out_write, pc_write, mdr_write;
    wire md_init, md_step, hi_write, lo_write;   // NEW
    wire is_mult_out, is_div_out;                 // NEW
    wire [3:0] alu_op;
    wire alu_src;
    wire [1:0] pc_source;
    wire reg_write;
    wire [1:0] reg_dst;
    wire [1:0] wb_sel;           // NEW (was 1-bit mem_to_reg)
    wire dmem_write;
    wire overflow;               // NEW: sticky overflow flag
    wire illegal_opcode;         // NEW: sticky illegal-opcode/TRAP flag
    wire regs_equal = (a_reg == b_reg);
    wire md_counter_done = (md_counter == 6'd31); // NEW

    control_unit_mc ctrl (
        .clk(clk), .rst(rst), .start(start), .ir(ir_reg), .regs_equal(regs_equal),
        .alu_ov(alu_ov), .md_counter_done(md_counter_done),
        .state(state),
        .ir_write(ir_write), .pc_plus1_write(pc_plus1_write),
        .ab_write(ab_write), .branch_target_write(branch_target_write),
        .alu_out_write(alu_out_write), .pc_write(pc_write), .mdr_write(mdr_write),
        .md_init(md_init), .md_step(md_step), .hi_write(hi_write), .lo_write(lo_write),
        .alu_op(alu_op), .alu_src(alu_src), .pc_source(pc_source),
        .reg_write(reg_write), .reg_dst(reg_dst), .wb_sel(wb_sel),
        .dmem_write(dmem_write), .overflow(overflow), .illegal_opcode(illegal_opcode),
        .is_mult_out(is_mult_out), .is_div_out(is_div_out)
    );

    //----------------------------------------------------------------
    // Register file
    //----------------------------------------------------------------
    wire [31:0] rf_read_data1, rf_read_data2;
    wire [4:0]  write_reg = (reg_dst == 2'd2) ? 5'd31 :
                             (reg_dst == 2'd1) ? rt   : rd;
    wire [31:0] write_data = (reg_dst == 2'd2) ? {25'b0, pc_plus1_reg} : // JAL: $31 = return addr
                              (wb_sel == 2'd1)   ? mdr_reg              : // LW: from memory
                              (wb_sel == 2'd2)   ? hi_reg               : // MFHI
                              (wb_sel == 2'd3)   ? lo_reg               : // MFLO
                                                    alu_out_reg;          // R-type/ADDI: from ALU

    regfile rf (
        .clk(clk),
        .rst(rst),
        .read_reg1(rs), .read_reg2(rt),
        .write_reg(write_reg), .write_data(write_data),
        .write_enable(reg_write),
        .read_data1(rf_read_data1), .read_data2(rf_read_data2),
        .dbg_r1(debug_reg1), .dbg_r2(debug_reg2), .dbg_r3(debug_reg3), .dbg_r4(debug_reg4),
        .dbg_r5(debug_reg5), .dbg_r6(debug_reg6), .dbg_r7(debug_reg7), .dbg_r8(debug_reg8),
        .dbg_r9(debug_reg9), .dbg_r10(debug_reg10), .dbg_r11(debug_reg11), .dbg_r12(debug_reg12),
        .dbg_r13(debug_reg13), .dbg_r14(debug_reg14), .dbg_r15(debug_reg15), .dbg_r16(debug_reg16),
        .dbg_r17(debug_reg17), .dbg_r18(debug_reg18), .dbg_r19(debug_reg19), .dbg_r20(debug_reg20),
        .dbg_r21(debug_reg21), .dbg_r22(debug_reg22), .dbg_r23(debug_reg23), .dbg_r24(debug_reg24),
        .dbg_r25(debug_reg25), .dbg_r26(debug_reg26), .dbg_r27(debug_reg27), .dbg_r28(debug_reg28),
        .dbg_r29(debug_reg29), .dbg_r30(debug_reg30), .dbg_r31(debug_reg31)
    );

    //----------------------------------------------------------------
    // ALU - operand A is always a_reg; operand B is either b_reg
    // (R-type) or the sign-extended immediate (ADDI/LW/SW address calc)
    //----------------------------------------------------------------
    wire [31:0] alu_b = alu_src ? imm_sext : b_reg;
    wire [31:0] alu_result;
    wire        alu_cout;
    wire        alu_ov;   // NEW: signed overflow, feeds control_unit_mc's sticky flag
    ALU_32_bit alu (
        .A(a_reg), .B(alu_b), .Op(alu_op),
        .Result(alu_result), .Cout(alu_cout), .Ov(alu_ov)
    );

    //----------------------------------------------------------------
    // Data memory - address/write-data come from the registers that
    // hold them by the time MEM state is reached
    //----------------------------------------------------------------
    // NEW: memory-mapped I/O address decode. The top two addresses
    // (510/511) are intercepted here, BEFORE reaching the real dmem
    // module - dmem.v itself stays a plain memory. The rest of the
    // 512-word space is ordinary data memory. This keeps the
    // already-verified memory module pristine and puts all the new
    // logic in this one place.
    wire is_led_addr = (alu_out_reg[8:0] == 9'd511); // SW here -> LEDs, not real memory
    wire is_btn_addr  = (alu_out_reg[8:0] == 9'd510); // LW here -> button, not real memory

    wire real_dmem_write = dmem_write && !is_led_addr; // suppress the real write for the LED address

    wire [31:0] dmem_read_data_raw;
    wire [31:0] dmem_read_data = is_btn_addr ? {31'b0, btn_sync2} : dmem_read_data_raw;

    dmem data_mem (
        .clk(clk),
        .addr(alu_out_reg[8:0]),
        .write_data(b_reg),
        .write_enable(real_dmem_write),
        .read_data(dmem_read_data_raw)
    );

    assign debug_instruction       = ir_reg;
    assign debug_dmem_addr         = alu_out_reg[4:0]; // low 5 bits only
    assign debug_dmem_write_data   = b_reg;
    assign debug_dmem_write_enable = dmem_write;
    assign debug_dmem_read_data    = dmem_read_data;

    //----------------------------------------------------------------
    // NEW: MULT/DIV datapath. Both use the SAME 64-bit working
    // register (md_product_reg) and 32-bit "other operand" register
    // (md_b_reg) - only one instruction type is ever mid-flight at a
    // time, so sharing storage is safe and saves registers.
    //
    // MULT: classic shift-add. Each of the 32 steps: if the current
    // LSB of the low half is 1, add the multiplicand into the upper
    // half; then shift the whole 64-bit register right by 1.
    //
    // DIV: classic restoring division. Each of the 32 steps: shift the
    // whole 64-bit {remainder:quotient} register left by 1, subtract
    // the divisor from the new upper half; if that went negative,
    // restore (keep the un-subtracted value) and shift in a 0 as the
    // new quotient bit, else keep the subtracted value and shift in a
    // 1. After 32 steps: quotient ends up in the LOW half, remainder
    // in the HIGH half - this matches real MIPS's LO=quotient,
    // HI=remainder convention exactly, so no extra reshuffling needed.
    //----------------------------------------------------------------
    wire [31:0] a_abs = a_reg[31] ? (~a_reg + 32'd1) : a_reg;
    wire [31:0] b_abs = b_reg[31] ? (~b_reg + 32'd1) : b_reg;

    // one MULT step
    wire        mult_lsb        = md_product_reg[0];
    wire [31:0] mult_added_hi   = md_product_reg[63:32] + md_b_reg;
    wire [63:0] mult_after_add  = mult_lsb ? {mult_added_hi, md_product_reg[31:0]}
                                            : md_product_reg;
    wire [63:0] mult_next       = mult_after_add >> 1;

    // one DIV step
    wire [63:0] div_shifted     = md_product_reg << 1;
    wire [32:0] div_rem_minus_b = {1'b0, div_shifted[63:32]} - {1'b0, md_b_reg};
    wire [63:0] div_next        = div_rem_minus_b[32] ?
                                     {div_shifted[63:32], div_shifted[31:1], 1'b0} : // restore, quotient bit=0
                                     {div_rem_minus_b[31:0], div_shifted[31:1], 1'b1}; // keep, quotient bit=1

    // final sign correction (MD_DONE)
    wire [63:0] mult_signed_result = md_sign_reg ? (~md_product_reg + 64'd1) : md_product_reg;
    wire [31:0] div_quot_mag       = md_product_reg[31:0];
    wire [31:0] div_rem_mag        = md_product_reg[63:32];
    wire [31:0] div_quot_signed    = md_sign_reg ? (~div_quot_mag + 32'd1) : div_quot_mag;
    wire [31:0] div_rem_signed     = a_reg[31]   ? (~div_rem_mag  + 32'd1) : div_rem_mag; // remainder follows DIVIDEND's sign
    assign debug_state             = state;
    assign debug_overflow          = overflow;
    assign debug_illegal_opcode    = illegal_opcode;
    assign debug_hi                = hi_reg;
    assign debug_lo                = lo_reg;
    assign mmio_led_out            = led_reg;

    //----------------------------------------------------------------
    // PC next-value mux (only sampled when pc_write is asserted, i.e.
    // during EX)
    //----------------------------------------------------------------
    wire [11:0] pc_next = (pc_source == 2'd0) ? pc_plus1_reg :
                          (pc_source == 2'd1) ? branch_target_reg :
                          (pc_source == 2'd2) ? jump_target :
                                                 a_reg[11:0]; // JR

    //----------------------------------------------------------------
    // All the cross-cycle register updates, gated by the FSM's
    // latch-enable pulses
    //----------------------------------------------------------------
    always @(posedge clk) begin
        if (ir_write)
            ir_reg <= imem_instruction;

        if (pc_plus1_write)
            pc_plus1_reg <= pc + 12'd1;

        if (ab_write) begin
            a_reg <= rf_read_data1;
            b_reg <= rf_read_data2;
        end

        if (branch_target_write)
            branch_target_reg <= pc_plus1_reg + imm_sext[11:0];

        if (alu_out_write)
            alu_out_reg <= alu_result;

        if (mdr_write)
            mdr_reg <= dmem_read_data;

        // NEW: MULT/DIV
        if (md_init) begin
            md_sign_reg <= a_reg[31] ^ b_reg[31];
            md_counter  <= 6'd0;
            if (is_mult_out) begin
                md_b_reg       <= a_abs;             // multiplicand
                md_product_reg <= {32'd0, b_abs};    // multiplier (magnitude) in low half
            end else begin // is_div
                md_b_reg       <= b_abs;             // divisor
                md_product_reg <= {32'd0, a_abs};    // dividend (magnitude) in low half
            end
        end

        if (md_step) begin
            md_product_reg <= is_mult_out ? mult_next : div_next;
            md_counter     <= md_counter + 6'd1;
        end

        if (hi_write)
            hi_reg <= is_mult_out ? mult_signed_result[63:32] : div_rem_signed;

        if (lo_write)
            lo_reg <= is_mult_out ? mult_signed_result[31:0] : div_quot_signed;

        // NEW: memory-mapped I/O
        if (dmem_write && is_led_addr)
            led_reg <= b_reg[3:0];

        btn_sync1 <= mmio_btn_in;
        btn_sync2 <= btn_sync1;

        if (rst)
            pc <= 12'd0;       // NEW: reset returns PC to the start of the program
        else if (pc_write)
            pc <= pc_next;
    end

    assign debug_pc = pc;

endmodule