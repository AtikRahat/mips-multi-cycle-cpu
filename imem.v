//====================================================================
// imem.v  (12-bit address, 4,096 instructions)
//
// 4,096 words needs 16 M9K blocks (256 words/block at 32-bit width),
// against the EP4CE6's total budget of 30 blocks - 14 blocks of
// margin. (8,192 words previously failed: needed 32 blocks, more than
// the entire chip's budget.)
//====================================================================

module imem (
    input  [11:0] addr,
    output [31:0] instruction,

    // write port (used only by the UART loader)
    input         wr_clk,
    input         wr_en,
    input  [11:0] wr_addr,
    input  [31:0] wr_data
);
    reg [31:0] mem [0:4095];

    initial begin
        $readmemh("program.hex", mem);
    end

    always @(posedge wr_clk) begin
        if (wr_en)
            mem[wr_addr] <= wr_data;
    end

    assign instruction = mem[addr];   // unchanged - still combinational

endmodule