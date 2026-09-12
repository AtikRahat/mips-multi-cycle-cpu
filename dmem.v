//====================================================================
// dmem.v  (512-word data memory, synchronous read for M9K inference)
//
// Data memory - a separate block of 512 storage words, distinct from
// the register file. This is what SW writes into and LW reads from.
// 512 x 32 bits = 2 M9K blocks, well inside the EP4CE6's 30-block
// budget.
//
// Reads are SYNCHRONOUS: the address is presented one cycle and the
// data appears after the next clock edge (one cycle of latency).
// This is required because Cyclone IV block RAM has no combinational
// (unregistered) read path that Quartus can infer - a purely
// combinational "assign read_data = mem[addr]" fails inference
// (Error 276003) and falls back to one flip-flop per bit (16,384
// registers for this array). The registered read below is the
// standard single-port-RAM template Quartus maps to M9K.
//
// The extra cycle is compensated in control_unit_mc.v: LW now flows
// IF ID EX MEM MEM2 WB, with MEM presenting the address and MEM2
// capturing the data (mdr_write). SW timing is unchanged (it writes
// during MEM and skips MEM2).
//
// mem[] is also given an initial value from data.hex (written by the
// assembler's .data section) at synthesis time, the same way imem.v
// loads program.hex. If a program has no .data section, data.hex is
// still generated (all zeros), so this file must always exist.
//====================================================================

module dmem (
    input         clk,
    input  [8:0]  addr,
    input  [31:0] write_data,
    input         write_enable,
    output reg [31:0] read_data
);
    (* ramstyle = "M9K" *) reg [31:0] mem [0:511];

    initial $readmemh("data.hex", mem);

    always @(posedge clk) begin
        if (write_enable)
            mem[addr] <= write_data;
        read_data <= mem[addr];
    end

endmodule