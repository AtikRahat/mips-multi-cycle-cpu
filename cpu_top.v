//====================================================================
// cpu_top.v  (updated: exposes all 31 usable registers, plus the
// existing PC/instruction/data-memory debug outputs)
//====================================================================

module cpu_top (
    input        clk,
    input        step_enable,
    output [31:0] debug_reg1,
    output [31:0] debug_reg2,
    output [31:0] debug_reg3,
    output [31:0] debug_reg4,
    output [31:0] debug_reg5,
    output [31:0] debug_reg6,
    output [31:0] debug_reg7,
    output [31:0] debug_reg8,
    output [31:0] debug_reg9,
    output [31:0] debug_reg10,
    output [31:0] debug_reg11,
    output [31:0] debug_reg12,
    output [31:0] debug_reg13,
    output [31:0] debug_reg14,
    output [31:0] debug_reg15,
    output [31:0] debug_reg16,
    output [31:0] debug_reg17,
    output [31:0] debug_reg18,
    output [31:0] debug_reg19,
    output [31:0] debug_reg20,
    output [31:0] debug_reg21,
    output [31:0] debug_reg22,
    output [31:0] debug_reg23,
    output [31:0] debug_reg24,
    output [31:0] debug_reg25,
    output [31:0] debug_reg26,
    output [31:0] debug_reg27,
    output [31:0] debug_reg28,
    output [31:0] debug_reg29,
    output [31:0] debug_reg30,
    output [31:0] debug_reg31,
    output [6:0]  debug_pc,

    output [31:0] debug_instruction,
    output [4:0]  debug_dmem_addr,
    output [31:0] debug_dmem_write_data,
    output        debug_dmem_write_enable,
    output [31:0] debug_dmem_read_data,
    output [31:0] debug_dmem0,
    output [31:0] debug_dmem1,
    output [31:0] debug_dmem2,
    output [31:0] debug_dmem3,
    output [31:0] debug_dmem4,
    output [31:0] debug_dmem5,
    output [31:0] debug_dmem6,
    output [31:0] debug_dmem7,
    output [31:0] debug_dmem8,
    output [31:0] debug_dmem9,
    output [31:0] debug_dmem10,
    output [31:0] debug_dmem11,
    output [31:0] debug_dmem12,
    output [31:0] debug_dmem13,
    output [31:0] debug_dmem14,
    output [31:0] debug_dmem15,
    output [31:0] debug_dmem16,
    output [31:0] debug_dmem17,
    output [31:0] debug_dmem18,
    output [31:0] debug_dmem19,
    output [31:0] debug_dmem20,
    output [31:0] debug_dmem21,
    output [31:0] debug_dmem22,
    output [31:0] debug_dmem23,
    output [31:0] debug_dmem24,
    output [31:0] debug_dmem25,
    output [31:0] debug_dmem26,
    output [31:0] debug_dmem27,
    output [31:0] debug_dmem28,
    output [31:0] debug_dmem29,
    output [31:0] debug_dmem30,
    output [31:0] debug_dmem31
);

    reg [6:0] pc = 7'd0;
    wire [31:0] instruction;
    imem instr_mem (.addr(pc), .instruction(instruction));

    wire [5:0] opcode = instruction[31:26];
    wire [4:0] rs     = instruction[25:21];
    wire [4:0] rt     = instruction[20:16];
    wire [4:0] rd     = instruction[15:11];
    wire [5:0] funct  = instruction[5:0];
    wire [15:0] imm16 = instruction[15:0];
    wire [31:0] imm_sext = {{16{imm16[15]}}, imm16};

    wire [3:0] alu_op;
    wire       reg_write, branch_eq, branch_ne;
    wire       alu_src, mem_write, mem_to_reg, reg_dst_rt;
    wire       jump, jump_reg, link;
    control_unit ctrl (
        .opcode(opcode), .funct(funct),
        .alu_op(alu_op), .reg_write(reg_write),
        .branch_eq(branch_eq), .branch_ne(branch_ne),
        .alu_src(alu_src), .mem_write(mem_write),
        .mem_to_reg(mem_to_reg), .reg_dst_rt(reg_dst_rt),
        .jump(jump), .jump_reg(jump_reg), .link(link)
    );

    wire [31:0] read_data1, read_data2;
    wire [31:0] alu_result;
    wire [31:0] mem_read_data;

    wire [4:0]  normal_write_reg  = link ? 5'd31 : (reg_dst_rt ? rt : rd);
    wire [31:0] normal_write_data = link ? pc_plus1 : (mem_to_reg ? mem_read_data : alu_result);
    wire        normal_write_en   = step_enable && reg_write;

    regfile rf (
        .clk(clk),
        .read_reg1(rs), .read_reg2(rt),
        .write_reg(normal_write_reg), .write_data(normal_write_data),
        .write_enable(normal_write_en),
        .read_data1(read_data1), .read_data2(read_data2),
        .dbg_r1(debug_reg1), .dbg_r2(debug_reg2), .dbg_r3(debug_reg3), .dbg_r4(debug_reg4), .dbg_r5(debug_reg5), .dbg_r6(debug_reg6), .dbg_r7(debug_reg7), .dbg_r8(debug_reg8), .dbg_r9(debug_reg9), .dbg_r10(debug_reg10), .dbg_r11(debug_reg11), .dbg_r12(debug_reg12), .dbg_r13(debug_reg13), .dbg_r14(debug_reg14), .dbg_r15(debug_reg15), .dbg_r16(debug_reg16), .dbg_r17(debug_reg17), .dbg_r18(debug_reg18), .dbg_r19(debug_reg19), .dbg_r20(debug_reg20), .dbg_r21(debug_reg21), .dbg_r22(debug_reg22), .dbg_r23(debug_reg23), .dbg_r24(debug_reg24), .dbg_r25(debug_reg25), .dbg_r26(debug_reg26), .dbg_r27(debug_reg27), .dbg_r28(debug_reg28), .dbg_r29(debug_reg29), .dbg_r30(debug_reg30), .dbg_r31(debug_reg31)
    );

    wire [31:0] alu_b = alu_src ? imm_sext : read_data2;
    wire aluCout;
    ALU_32_bit alu (
        .A(read_data1), .B(alu_b), .Op(alu_op),
        .Result(alu_result), .Cout(aluCout)
    );

    wire dmem_we = step_enable && mem_write;

    dmem data_mem (
        .clk(clk),
        .addr(alu_result[4:0]),
        .write_data(read_data2),
        .write_enable(dmem_we),
        .read_data(mem_read_data),
        .dbg_mem0(debug_dmem0), .dbg_mem1(debug_dmem1), .dbg_mem2(debug_dmem2), .dbg_mem3(debug_dmem3),
        .dbg_mem4(debug_dmem4), .dbg_mem5(debug_dmem5), .dbg_mem6(debug_dmem6), .dbg_mem7(debug_dmem7),
        .dbg_mem8(debug_dmem8), .dbg_mem9(debug_dmem9), .dbg_mem10(debug_dmem10), .dbg_mem11(debug_dmem11),
        .dbg_mem12(debug_dmem12), .dbg_mem13(debug_dmem13), .dbg_mem14(debug_dmem14), .dbg_mem15(debug_dmem15),
        .dbg_mem16(debug_dmem16), .dbg_mem17(debug_dmem17), .dbg_mem18(debug_dmem18), .dbg_mem19(debug_dmem19),
        .dbg_mem20(debug_dmem20), .dbg_mem21(debug_dmem21), .dbg_mem22(debug_dmem22), .dbg_mem23(debug_dmem23),
        .dbg_mem24(debug_dmem24), .dbg_mem25(debug_dmem25), .dbg_mem26(debug_dmem26), .dbg_mem27(debug_dmem27),
        .dbg_mem28(debug_dmem28), .dbg_mem29(debug_dmem29), .dbg_mem30(debug_dmem30), .dbg_mem31(debug_dmem31)
    );

    assign debug_instruction       = instruction;
    assign debug_dmem_addr         = alu_result[4:0];
    assign debug_dmem_write_data   = read_data2;
    assign debug_dmem_write_enable = dmem_we;
    assign debug_dmem_read_data    = mem_read_data;

    wire regs_equal = (read_data1 == read_data2);
    wire branch_taken = (branch_eq & regs_equal) | (branch_ne & ~regs_equal);

    wire [31:0] pc_plus1        = {25'b0, pc} + 32'd1;
    wire [31:0] branch_target32 = pc_plus1 + imm_sext;
    wire [6:0]  jump_target     = instruction[6:0]; // J-type address field (only low 7 bits needed - 128-word imem)

    wire [6:0]  pc_next = jump        ? jump_target :
                          jump_reg    ? read_data1[6:0] :
                          branch_taken ? branch_target32[6:0] :
                                         pc_plus1[6:0];

    always @(posedge clk)
        if (step_enable)
            pc <= pc_next;

    assign debug_pc = pc;

endmodule