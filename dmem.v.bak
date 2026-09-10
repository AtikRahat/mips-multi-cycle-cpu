//====================================================================
// dmem.v  (full 32-word debug visibility + data.hex initial load)
// Data memory - a separate block of 32 storage words, distinct from
// the register file. This is what SW writes into and LW reads from.
//
// Reads happen instantly (combinational) - same idea as the register
// file's read ports. Writes only happen on a clock edge, and only
// when write_enable is asserted.
//
// Every one of the 32 words has a debug output, so the full memory
// can be viewed live via ISSP - same idea as regfile.v's dbg_r1..dbg_r31.
//
// mem[] is also given an initial value from data.hex (written by the
// assembler's .data section) at synthesis time, the same way imem.v
// loads program.hex. If a program has no .data section, data.hex is
// still generated (all zeros), so this file must always exist.
//====================================================================

module dmem (
    input         clk,
    input  [4:0]  addr,
    input  [31:0] write_data,
    input         write_enable,
    output [31:0] read_data,

    output [31:0] dbg_mem0,
    output [31:0] dbg_mem1,
    output [31:0] dbg_mem2,
    output [31:0] dbg_mem3,
    output [31:0] dbg_mem4,
    output [31:0] dbg_mem5,
    output [31:0] dbg_mem6,
    output [31:0] dbg_mem7,
    output [31:0] dbg_mem8,
    output [31:0] dbg_mem9,
    output [31:0] dbg_mem10,
    output [31:0] dbg_mem11,
    output [31:0] dbg_mem12,
    output [31:0] dbg_mem13,
    output [31:0] dbg_mem14,
    output [31:0] dbg_mem15,
    output [31:0] dbg_mem16,
    output [31:0] dbg_mem17,
    output [31:0] dbg_mem18,
    output [31:0] dbg_mem19,
    output [31:0] dbg_mem20,
    output [31:0] dbg_mem21,
    output [31:0] dbg_mem22,
    output [31:0] dbg_mem23,
    output [31:0] dbg_mem24,
    output [31:0] dbg_mem25,
    output [31:0] dbg_mem26,
    output [31:0] dbg_mem27,
    output [31:0] dbg_mem28,
    output [31:0] dbg_mem29,
    output [31:0] dbg_mem30,
    output [31:0] dbg_mem31
);
    reg [31:0] mem [0:31];

    initial $readmemh("data.hex", mem);

    assign read_data = mem[addr];

    assign dbg_mem0 = mem[0];
    assign dbg_mem1 = mem[1];
    assign dbg_mem2 = mem[2];
    assign dbg_mem3 = mem[3];
    assign dbg_mem4 = mem[4];
    assign dbg_mem5 = mem[5];
    assign dbg_mem6 = mem[6];
    assign dbg_mem7 = mem[7];
    assign dbg_mem8 = mem[8];
    assign dbg_mem9 = mem[9];
    assign dbg_mem10 = mem[10];
    assign dbg_mem11 = mem[11];
    assign dbg_mem12 = mem[12];
    assign dbg_mem13 = mem[13];
    assign dbg_mem14 = mem[14];
    assign dbg_mem15 = mem[15];
    assign dbg_mem16 = mem[16];
    assign dbg_mem17 = mem[17];
    assign dbg_mem18 = mem[18];
    assign dbg_mem19 = mem[19];
    assign dbg_mem20 = mem[20];
    assign dbg_mem21 = mem[21];
    assign dbg_mem22 = mem[22];
    assign dbg_mem23 = mem[23];
    assign dbg_mem24 = mem[24];
    assign dbg_mem25 = mem[25];
    assign dbg_mem26 = mem[26];
    assign dbg_mem27 = mem[27];
    assign dbg_mem28 = mem[28];
    assign dbg_mem29 = mem[29];
    assign dbg_mem30 = mem[30];
    assign dbg_mem31 = mem[31];

    always @(posedge clk)
        if (write_enable)
            mem[addr] <= write_data;

endmodule