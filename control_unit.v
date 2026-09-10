//====================================================================
// control_unit_mc.v  (multi-cycle control FSM - FULL VERSION)
//
// Replaces control_unit.v. Instead of computing every signal
// instantly (single-cycle style), this module remembers WHICH STEP
// of the current instruction it's on (the "state") and only asserts
// the signals that step needs.
//
// States (a common trunk, then it branches after EX):
//   IDLE -> IF -> ID -> EX -> (branches out from here) -> ... -> IDLE
//
//   R-type / ADDI : IDLE IF ID EX WB IDLE            (4 active cycles)
//   LW            : IDLE IF ID EX MEM WB IDLE        (5 active cycles)
//   SW            : IDLE IF ID EX MEM IDLE           (4 active cycles)
//   BEQ/BNE/JR    : IDLE IF ID EX IDLE                (3 active cycles)
//   JAL           : IDLE IF ID EX IDLE                (3 active cycles,
//                    writes $31 during EX itself)
//
// This module does NOT hold any of the actual data (PC, IR, A, B,
// etc.) - that all lives in cpu_top_mc.v. This module only decides
// "what state are we in" and "what should the datapath do this cycle."
//====================================================================

module control_unit_mc (
    input        clk,
    input        rst,          // NEW: synchronous reset, level-held
    input        start,        // one-cycle pulse: begin executing the
                                // next instruction (from debounced KEY[2])
    input [31:0] ir,           // the LATCHED instruction (valid from ID
                                // state onward - this module only reads
                                // opcode/funct out of it)
    input        regs_equal,   // datapath tells us: is A == B right now?
    input        alu_ov,       // NEW: ALU's raw (unlatched) overflow signal,
                                // only meaningful during EX
    input        md_counter_done, // NEW: datapath tells us: has the MULT/DIV
                                   // loop done its 32nd iteration yet?

    output [3:0] state,        // WIDENED from 3 to 4 bits - MULT/DIV needed
                                // 2 more state values than fit in 3 bits
    output       overflow,     // NEW: sticky signed-overflow flag
    output       illegal_opcode, // NEW: sticky flag, set if the FSM ever
                                  // halts on an unrecognized instruction

    // --- "this register updates now" latch-enable pulses ---
    output       ir_write,           // IF:  IR <= imem[PC]
    output       pc_plus1_write,     // IF:  PCPlus1Reg <= PC + 1
    output       ab_write,           // ID:  A <= rf[rs], B <= rf[rt]
    output       branch_target_write,// ID:  BranchTargetReg <= PCPlus1Reg + imm
    output       alu_out_write,      // EX:  ALUOut <= alu_result
    output       pc_write,           // EX:  PC <= (see pc_source mux)
    output       mdr_write,          // MEM: MDR <= dmem_read_data
    output       md_init,            // NEW EX: load MULT/DIV working regs
    output       md_step,            // NEW MD_LOOP: one shift-add/restoring-div step
    output       hi_write,           // NEW MD_DONE: HI <= final result
    output       lo_write,           // NEW MD_DONE: LO <= final result

    // --- datapath control/select signals ---
    output [3:0] alu_op,             // which ALU operation during EX
    output       alu_src,            // 0: ALU B = B_reg   1: ALU B = imm_sext
    output [1:0] pc_source,          // 0=PCPlus1Reg 1=BranchTargetReg
                                      // 2=jump literal (JAL)  3=A_reg (JR)
    output       reg_write,          // regfile write happening THIS cycle
    output [1:0] reg_dst,            // 0=rd 1=rt 2=$31  (which reg to write)
    output [1:0] wb_sel,             // NEW (was 1-bit mem_to_reg): regfile write
                                      // data source: 0=ALUOut 1=MDR 2=HI 3=LO
    output       dmem_write,         // dmem write happening THIS cycle (SW)
    output       is_mult_out,        // NEW: exposed so datapath knows which
    output       is_div_out          // MD_LOOP operation to perform
);

    // ---- state names ----
    localparam IDLE    = 4'd0;
    localparam IF      = 4'd1;
    localparam ID      = 4'd2;
    localparam EX      = 4'd3;
    localparam MEM     = 4'd4;
    localparam WB      = 4'd5;
    localparam TRAP    = 4'd6;   // halts here on an illegal instruction -
                                  // only rst can leave this state
    localparam MD_LOOP = 4'd7;   // NEW: MULT/DIV - 32 repeated shift/subtract
                                  // steps, shared by both (only one is
                                  // active per instruction, decided by
                                  // is_mult/is_div which stay constant
                                  // throughout since ir_reg is stable)
    localparam MD_DONE = 4'd8;   // NEW: MULT/DIV - one cycle to sign-correct
                                  // and write HI/LO

    reg [3:0] current_state = IDLE;
    assign state = current_state;

    // ---- decode the fields we need out of the latched instruction ----
    wire [5:0] opcode = ir[31:26];
    wire [5:0] funct  = ir[5:0];

    wire is_jr    = (opcode == 6'b000000) && (funct == 6'b001000);
    wire is_addi  = (opcode == 6'b001000);
    wire is_lw    = (opcode == 6'b100011);
    wire is_sw    = (opcode == 6'b101011);
    wire is_beq   = (opcode == 6'b000100);
    wire is_bne   = (opcode == 6'b000101);
    wire is_jal   = (opcode == 6'b000011);

    // NEW: is_rtype is now TIGHTENED to only the 5 functs the ALU
    // actually implements. Previously it matched "opcode==0 and funct
    // != JR" - meaning a genuinely unrecognized funct (a corrupted
    // instruction, or a typo in hand-assembled hex) silently executed
    // as if it were ADD (the alu_op case statement's default). That
    // was a real, if narrow, gap - this closes it.
    wire is_add = (opcode == 6'b000000) && (funct == 6'b100000);
    wire is_sub = (opcode == 6'b000000) && (funct == 6'b100010);
    wire is_and = (opcode == 6'b000000) && (funct == 6'b100100);
    wire is_or  = (opcode == 6'b000000) && (funct == 6'b100101);
    wire is_slt = (opcode == 6'b000000) && (funct == 6'b101010);
    wire is_rtype = is_add | is_sub | is_and | is_or | is_slt;

    // NEW: MULT/DIV/MFHI/MFLO - real MIPS encodings (opcode=0)
    wire is_mult = (opcode == 6'b000000) && (funct == 6'b011000);
    wire is_div  = (opcode == 6'b000000) && (funct == 6'b011010);
    wire is_mfhi = (opcode == 6'b000000) && (funct == 6'b010000);
    wire is_mflo = (opcode == 6'b000000) && (funct == 6'b010010);
    assign is_mult_out = is_mult;
    assign is_div_out  = is_div;

    wire check_overflow = is_addi | is_add | is_sub;

    // NEW: anything that isn't one of the now-16 real instructions.
    // opcode==0 (R-type/JR/MULT/DIV/MFHI/MFLO) but an unrecognized
    // funct -> illegal. any other opcode not in the known list -> illegal.
    wire is_illegal =
        (opcode == 6'b000000) ? !(is_add | is_sub | is_and | is_or | is_slt | is_jr
                                   | is_mult | is_div | is_mfhi | is_mflo) :
                                 !(is_addi | is_lw | is_sw | is_beq | is_bne | is_jal);

    wire branch_taken = (is_beq & regs_equal) | (is_bne & ~regs_equal);

    // ---- next-state logic ----
    reg [3:0] next_state;
    always @(*) begin
        case (current_state)
            IDLE: next_state = start ? IF : IDLE;
            IF:   next_state = ID;
            ID:   next_state = EX;
            EX: begin
                     if (is_illegal)                next_state = TRAP;   // halt on bad instruction
                else if (is_mult || is_div)         next_state = MD_LOOP; // NEW: 32-cycle loop
                else if (is_lw || is_sw)             next_state = MEM;    // needs a memory cycle
                else if (is_rtype || is_addi
                         || is_mfhi || is_mflo)      next_state = WB;     // needs a writeback cycle
                else                                  next_state = IDLE;  // BEQ/BNE/JAL/JR: done after EX
            end
            MEM:     next_state = is_lw ? WB : IDLE;
            WB:      next_state = IDLE;
            MD_LOOP: next_state = md_counter_done ? MD_DONE : MD_LOOP; // NEW: stay 32 cycles
            MD_DONE: next_state = IDLE;                                // NEW: one cycle, then done
            TRAP:    next_state = TRAP; // stuck here forever - only rst escapes
            default: next_state = IDLE;
        endcase
    end

    // --- AUTO-RUN MODE (back to "one press = one full instruction") ---
    // The state register updates on every clock tick once started, so
    // after a single KEY[2] press it free-runs through all of that
    // instruction's IF/ID/EX/MEM/WB states on its own and lands back
    // in IDLE, without needing more presses.
    //
    // NEW: rst held high forces IDLE immediately, overriding whatever
    // the FSM was doing - lets you abort/restart cleanly without
    // reflashing the board.
    always @(posedge clk)
        if (rst)
            current_state <= IDLE;
        else
            current_state <= next_state;

    // ---- latch-enable pulses: just "which state are we in" ----
    assign ir_write            = (current_state == IF);
    assign pc_plus1_write       = (current_state == IF);
    assign ab_write             = (current_state == ID);
    assign branch_target_write  = (current_state == ID);
    assign alu_out_write        = (current_state == EX);
    assign mdr_write             = (current_state == MEM);

    // NEW: MULT/DIV control
    assign md_init = (current_state == EX) && (is_mult | is_div);
    assign md_step = (current_state == MD_LOOP);
    assign hi_write = (current_state == MD_DONE);
    assign lo_write = (current_state == MD_DONE);

    // PC updates once, during EX, for every instruction type
    assign pc_write = (current_state == EX);

    // ---- ALU control (same op encoding as the original control_unit.v) ----
    reg [3:0] alu_op_r;
    always @(*) begin
        alu_op_r = 4'b0010; // default ADD (covers ADDI/LW/SW address calc)
        if (is_rtype) begin
            case (funct)
                6'b100000: alu_op_r = 4'b0010; // ADD
                6'b100010: alu_op_r = 4'b0110; // SUB
                6'b100100: alu_op_r = 4'b0000; // AND
                6'b100101: alu_op_r = 4'b0001; // OR
                6'b101010: alu_op_r = 4'b0111; // SLT
                default:   alu_op_r = 4'b0010;
            endcase
        end
    end
    assign alu_op  = alu_op_r;
    assign alu_src = is_addi | is_lw | is_sw; // 1 = use immediate as ALU B

    // ---- PC source mux select ----
    assign pc_source = is_jal            ? 2'd2 :
                        is_jr             ? 2'd3 :
                        (is_beq | is_bne) ? (branch_taken ? 2'd1 : 2'd0) :
                                            2'd0;

    // ---- register file write control ----
    // R-type/ADDI/LW/MFHI/MFLO write during WB. JAL writes $31 during EX
    // itself (no separate WB needed - the value, PC+1, is already available).
    assign reg_write = ((current_state == WB) && (is_rtype || is_addi || is_lw
                                                    || is_mfhi || is_mflo))
                      || ((current_state == EX) && is_jal);

    assign reg_dst = is_jal ? 2'd2 :               // $31
                      (is_addi || is_lw) ? 2'd1 :    // rt
                      2'd0;                          // rd (R-type, MFHI, MFLO)

    // NEW (was 1-bit mem_to_reg): 0=ALUOut 1=MDR 2=HI 3=LO
    assign wb_sel = is_mfhi ? 2'd2 :
                     is_mflo ? 2'd3 :
                     is_lw   ? 2'd1 :
                               2'd0;

    // ---- data memory write control ----
    assign dmem_write = (current_state == MEM) && is_sw;

    // ---- NEW: sticky overflow flag ----
    // Latches high the first time ADD/SUB/ADDI genuinely overflows.
    // Stays high across any number of later instructions - only rst
    // clears it. This is deliberate: a live (self-clearing) flag could
    // silently hide an overflow that happened a few instructions ago
    // if you weren't watching that exact cycle.
    reg overflow_flag = 1'b0;
    always @(posedge clk) begin
        if (rst)
            overflow_flag <= 1'b0;
        else if ((current_state == EX) && check_overflow && alu_ov)
            overflow_flag <= 1'b1;
    end
    assign overflow = overflow_flag;

    // ---- NEW: sticky illegal-opcode flag ----
    // Latches high the moment the FSM enters TRAP. Since TRAP itself
    // is permanent (only rst leaves it), this flag and "the FSM is
    // stuck" always agree - but the flag is what gives it a name you
    // can check, rather than just inferring it from PC/state freezing.
    reg illegal_opcode_flag = 1'b0;
    always @(posedge clk) begin
        if (rst)
            illegal_opcode_flag <= 1'b0;
        else if ((current_state == EX) && is_illegal)
            illegal_opcode_flag <= 1'b1;
    end
    assign illegal_opcode = illegal_opcode_flag;

endmodule