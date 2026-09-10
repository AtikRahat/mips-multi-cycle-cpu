//====================================================================
// ALU_32_bit.v
// 32-bit ALU built from chained 1-bit ALU slices (Patterson & Hennessy
// style ALU control: Op = {Ainvert, Binvert, Op[1:0]})
//
// Op encoding (matches mux4x1 selection):
//   4'b0000 -> AND
//   4'b0001 -> OR
//   4'b0010 -> ADD
//   4'b0110 -> SUB   (A + (~B + 1))
//   4'b0111 -> SLT   (Set Less Than)
//   4'b1100 -> NOR   (using Ainvert=1, Binvert=1, Op=00 -> ~A & ~B)
//====================================================================

module ALU_32_bit (
    input  [31:0] A,
    input  [31:0] B,
    input  [3:0]  Op,
    output [31:0] Result,
    output        Cout,
    output        Ov            // NEW: signed overflow flag (was internal-only)
);

    wire [31:0] Carry;
    wire LT, Set;   // Ov is now a module output, declared in the port list

    // Bit 0: Less-input comes from LT (SLT feedback), Cin = Op[2] (needed for SUB)
    alu_1bit alu0  (A[0],  B[0],  Op[2],     LT,   Op[3], Op[2], Op[1:0], Result[0],  Carry[0]);

    alu_1bit alu1  (A[1],  B[1],  Carry[0],  1'b0, Op[3], Op[2], Op[1:0], Result[1],  Carry[1]);
    alu_1bit alu2  (A[2],  B[2],  Carry[1],  1'b0, Op[3], Op[2], Op[1:0], Result[2],  Carry[2]);
    alu_1bit alu3  (A[3],  B[3],  Carry[2],  1'b0, Op[3], Op[2], Op[1:0], Result[3],  Carry[3]);
    alu_1bit alu4  (A[4],  B[4],  Carry[3],  1'b0, Op[3], Op[2], Op[1:0], Result[4],  Carry[4]);
    alu_1bit alu5  (A[5],  B[5],  Carry[4],  1'b0, Op[3], Op[2], Op[1:0], Result[5],  Carry[5]);
    alu_1bit alu6  (A[6],  B[6],  Carry[5],  1'b0, Op[3], Op[2], Op[1:0], Result[6],  Carry[6]);
    alu_1bit alu7  (A[7],  B[7],  Carry[6],  1'b0, Op[3], Op[2], Op[1:0], Result[7],  Carry[7]);
    alu_1bit alu8  (A[8],  B[8],  Carry[7],  1'b0, Op[3], Op[2], Op[1:0], Result[8],  Carry[8]);
    alu_1bit alu9  (A[9],  B[9],  Carry[8],  1'b0, Op[3], Op[2], Op[1:0], Result[9],  Carry[9]);
    alu_1bit alu10 (A[10], B[10], Carry[9],  1'b0, Op[3], Op[2], Op[1:0], Result[10], Carry[10]);
    alu_1bit alu11 (A[11], B[11], Carry[10], 1'b0, Op[3], Op[2], Op[1:0], Result[11], Carry[11]);
    alu_1bit alu12 (A[12], B[12], Carry[11], 1'b0, Op[3], Op[2], Op[1:0], Result[12], Carry[12]);
    alu_1bit alu13 (A[13], B[13], Carry[12], 1'b0, Op[3], Op[2], Op[1:0], Result[13], Carry[13]);
    alu_1bit alu14 (A[14], B[14], Carry[13], 1'b0, Op[3], Op[2], Op[1:0], Result[14], Carry[14]);
    alu_1bit alu15 (A[15], B[15], Carry[14], 1'b0, Op[3], Op[2], Op[1:0], Result[15], Carry[15]);
    alu_1bit alu16 (A[16], B[16], Carry[15], 1'b0, Op[3], Op[2], Op[1:0], Result[16], Carry[16]);
    alu_1bit alu17 (A[17], B[17], Carry[16], 1'b0, Op[3], Op[2], Op[1:0], Result[17], Carry[17]);
    alu_1bit alu18 (A[18], B[18], Carry[17], 1'b0, Op[3], Op[2], Op[1:0], Result[18], Carry[18]);
    alu_1bit alu19 (A[19], B[19], Carry[18], 1'b0, Op[3], Op[2], Op[1:0], Result[19], Carry[19]);
    alu_1bit alu20 (A[20], B[20], Carry[19], 1'b0, Op[3], Op[2], Op[1:0], Result[20], Carry[20]);
    alu_1bit alu21 (A[21], B[21], Carry[20], 1'b0, Op[3], Op[2], Op[1:0], Result[21], Carry[21]);
    alu_1bit alu22 (A[22], B[22], Carry[21], 1'b0, Op[3], Op[2], Op[1:0], Result[22], Carry[22]);
    alu_1bit alu23 (A[23], B[23], Carry[22], 1'b0, Op[3], Op[2], Op[1:0], Result[23], Carry[23]);
    alu_1bit alu24 (A[24], B[24], Carry[23], 1'b0, Op[3], Op[2], Op[1:0], Result[24], Carry[24]);
    alu_1bit alu25 (A[25], B[25], Carry[24], 1'b0, Op[3], Op[2], Op[1:0], Result[25], Carry[25]);
    alu_1bit alu26 (A[26], B[26], Carry[25], 1'b0, Op[3], Op[2], Op[1:0], Result[26], Carry[26]);
    alu_1bit alu27 (A[27], B[27], Carry[26], 1'b0, Op[3], Op[2], Op[1:0], Result[27], Carry[27]);
    alu_1bit alu28 (A[28], B[28], Carry[27], 1'b0, Op[3], Op[2], Op[1:0], Result[28], Carry[28]);
    alu_1bit alu29 (A[29], B[29], Carry[28], 1'b0, Op[3], Op[2], Op[1:0], Result[29], Carry[29]);
    alu_1bit alu30 (A[30], B[30], Carry[29], 1'b0, Op[3], Op[2], Op[1:0], Result[30], Carry[30]);

    // Bit 31 (MSB, sign bit): needs the extra "Set" output for SLT
    alu_1Xbit alu31 (A[31], B[31], Carry[30], 1'b0, Op[3], Op[2], Op[1:0], Result[31], Set, Cout);

    // Overflow logic: XOR of carry into MSB and carry out of MSB
    assign Ov = Carry[30] ^ Cout;

    // Less Than (LT) logic: correct sign of result when overflow occurred
    assign LT = Ov ^ Set;

endmodule


//====================================================================
// alu_1Xbit: the MSB (bit 31) slice - same as alu_1bit but also
// exposes "Set" (the raw sum bit) so the top level can compute SLT
//====================================================================
module alu_1Xbit (
    input  A,
    input  B,
    input  Cin,
    input  Less,
    input  Ainvert,
    input  Binvert,
    input  [1:0] Op,
    output Result,
    output Set,
    output Cout
);

    wire Sum, andX, orX;
    wire N1, N2;

    assign N1 = Ainvert ? ~A : A;
    assign N2 = Binvert ? ~B : B;

    assign andX = N1 & N2;
    assign orX  = N1 | N2;

    full_adder fa (N1, N2, Cin, Sum, Cout);
    assign Set = Sum;

    mux4x1 m3 (andX, orX, Sum, Less, Op, Result);

endmodule


//====================================================================
// alu_1bit: one bit-slice of the ALU (bits 0..30)
//====================================================================
module alu_1bit (
    input  A,
    input  B,
    input  Cin,
    input  Less,
    input  Ainvert,
    input  Binvert,
    input  [1:0] Op,
    output Result,
    output Cout
);

    wire Sum, andX, orX;
    wire N1, N2;

    assign N1 = Ainvert ? ~A : A;
    assign N2 = Binvert ? ~B : B;

    assign andX = N1 & N2;
    assign orX  = N1 | N2;

    full_adder fa (N1, N2, Cin, Sum, Cout);

    mux4x1 m3 (andX, orX, Sum, Less, Op, Result);

endmodule


//====================================================================
// full_adder: basic 1-bit full adder
//====================================================================
module full_adder (
    input  A,
    input  B,
    input  Cin,
    output Sum,
    output Cout
);
    assign Sum  = (A ^ B) ^ Cin;
    assign Cout = (A & B) | (B & Cin) | (A & Cin);
endmodule


//====================================================================
// mux4x1: selects the ALU result based on Op[1:0]
//====================================================================
module mux4x1 (
    input        A,   // AND
    input        B,   // OR
    input        C,   // ADD/SUB (sum)
    input        D,   // LESS (SLT)
    input  [1:0] Sel,
    output reg   Q
);
    always @(*) begin
        case (Sel)
            2'b00: Q = A; // AND
            2'b01: Q = B; // OR
            2'b10: Q = C; // ADD
            2'b11: Q = D; // LESS (SLT)
            default: Q = A;
        endcase
    end
endmodule