//====================================================================
// regfile.v  (updated: individual debug outputs for ALL 31 usable
// registers - $0 is excluded since it's hardwired to always read 0)
//
//   - 2 read ports (read_data1, read_data2): reads happen instantly,
//     no clock needed
//   - 1 write port: only updates ON a clock edge, and only if
//     write_enable is 1
//   - Register 0 is hardwired to always read as 0, per MIPS
//     convention
//   - NEW: rst (held from top_cpu_mc.v's KEY[3]) synchronously clears
//     all 32 registers to 0 - same reset signal that already zeroes
//     the PC and sticky flags in control_unit_mc.v/cpu_top_mc.v
//
// Registers start at 0 (and are cleared to 0 by rst); programs are
// responsible for initialising the registers they use.
//====================================================================

module regfile (
    input         clk,
    input         rst,          // NEW: synchronous reset - clears all 32
                                 // physical registers to 0 (including the
                                 // storage behind $0, which already reads
                                 // as 0 architecturally either way)
    input  [4:0]  read_reg1,
    input  [4:0]  read_reg2,
    input  [4:0]  write_reg,
    input  [31:0] write_data,
    input         write_enable,
    output [31:0] read_data1,
    output [31:0] read_data2,

    output [31:0] dbg_r1,
    output [31:0] dbg_r2,
    output [31:0] dbg_r3,
    output [31:0] dbg_r4,
    output [31:0] dbg_r5,
    output [31:0] dbg_r6,
    output [31:0] dbg_r7,
    output [31:0] dbg_r8,
    output [31:0] dbg_r9,
    output [31:0] dbg_r10,
    output [31:0] dbg_r11,
    output [31:0] dbg_r12,
    output [31:0] dbg_r13,
    output [31:0] dbg_r14,
    output [31:0] dbg_r15,
    output [31:0] dbg_r16,
    output [31:0] dbg_r17,
    output [31:0] dbg_r18,
    output [31:0] dbg_r19,
    output [31:0] dbg_r20,
    output [31:0] dbg_r21,
    output [31:0] dbg_r22,
    output [31:0] dbg_r23,
    output [31:0] dbg_r24,
    output [31:0] dbg_r25,
    output [31:0] dbg_r26,
    output [31:0] dbg_r27,
    output [31:0] dbg_r28,
    output [31:0] dbg_r29,
    output [31:0] dbg_r30,
    output [31:0] dbg_r31
);

    // ramstyle = "logic" tells Quartus not to attempt RAM-megafunction
    // inference on this array. It has 33 simultaneous read requirements
    // (read_reg1, read_reg2, plus 31 fixed debug taps), which exceeds
    // Cyclone IV M9K's 2-read-port limit and can never be a valid RAM
    // candidate anyway - forcing "logic" skips the failed inference
    // attempt (and the max_number_of_registers_from_uninferred_rams
    // error it can trigger) and goes straight to flip-flops, which is
    // what this array was always implemented as regardless.
    (* ramstyle = "logic" *) reg [31:0] registers [0:31];

    assign dbg_r1  = registers[1];
    assign dbg_r2  = registers[2];
    assign dbg_r3  = registers[3];
    assign dbg_r4  = registers[4];
    assign dbg_r5  = registers[5];
    assign dbg_r6  = registers[6];
    assign dbg_r7  = registers[7];
    assign dbg_r8  = registers[8];
    assign dbg_r9  = registers[9];
    assign dbg_r10  = registers[10];
    assign dbg_r11  = registers[11];
    assign dbg_r12  = registers[12];
    assign dbg_r13  = registers[13];
    assign dbg_r14  = registers[14];
    assign dbg_r15  = registers[15];
    assign dbg_r16  = registers[16];
    assign dbg_r17  = registers[17];
    assign dbg_r18  = registers[18];
    assign dbg_r19  = registers[19];
    assign dbg_r20  = registers[20];
    assign dbg_r21  = registers[21];
    assign dbg_r22  = registers[22];
    assign dbg_r23  = registers[23];
    assign dbg_r24  = registers[24];
    assign dbg_r25  = registers[25];
    assign dbg_r26  = registers[26];
    assign dbg_r27  = registers[27];
    assign dbg_r28  = registers[28];
    assign dbg_r29  = registers[29];
    assign dbg_r30  = registers[30];
    assign dbg_r31  = registers[31];

    // Reads are combinational (instant, no clock wait) - register 0
    // always reads as 0 regardless of what's stored there
    assign read_data1 = (read_reg1 == 5'd0) ? 32'd0 : registers[read_reg1];
    assign read_data2 = (read_reg2 == 5'd0) ? 32'd0 : registers[read_reg2];

    // Writes happen only on a clock edge, only if enabled, and never
    // to register 0. NEW: rst held high clears every register to 0,
    // taking priority over any write happening the same cycle.
    integer i;
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 32; i = i + 1)
                registers[i] <= 32'd0;
        end else if (write_enable && write_reg != 5'd0) begin
            registers[write_reg] <= write_data;
        end
    end

endmodule