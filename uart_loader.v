//====================================================================
// uart_loader.v  (byte -> instruction-word assembly + imem write)
//
// Sits between uart_rx.v and imem.v's write port. Every time uart_rx
// signals byte_ready, this module shifts that byte into a 32-bit
// assembly register (big-endian: first byte received = most
// significant byte of the word). Every 4th byte, it pulses a
// one-clock write into imem at the current word address, then
// advances to the next address.
//
// Always expects the full 4,096-word image (16,384 bytes) - matching
// assembler.py's zero-padded program.hex output exactly, so there's
// no header/length byte to parse: you just send the whole padded
// image every time.
//====================================================================

module uart_loader (
    input        clk,          // same fast clock as uart_rx
    input        byte_ready,   // one-clk pulse from uart_rx
    input  [7:0] byte_in,      // the received byte, valid when byte_ready is high

    output       wr_en,        // one-clk pulse: write word_addr/word_data into imem
    output [11:0] wr_addr,  // 12 bits (4,096-word imem)
    output [31:0] wr_data,

    output       loading,      // high from the first byte received until the last
    output       load_done     // one-clk pulse: just finished receiving all 4,096 words
);

    reg [31:0] assemble_reg = 32'd0;
    reg [1:0]  byte_count   = 2'd0;   // 0..3, which byte of the current word
    reg [11:0] word_addr    = 12'd0;
    reg        loading_reg  = 1'b0;
    reg        wr_en_reg    = 1'b0;
    reg        done_reg     = 1'b0;

    assign wr_en     = wr_en_reg;
    assign wr_addr   = word_addr;
    assign wr_data   = assemble_reg;
    assign loading   = loading_reg;
    assign load_done = done_reg;

    always @(posedge clk) begin
        wr_en_reg <= 1'b0;  // default: pulses high for exactly 1 cycle
        done_reg  <= 1'b0;

        if (byte_ready) begin
            loading_reg <= 1'b1;
            // shift the new byte in as the LEAST significant not-yet-
            // filled byte - big-endian assembly (1st byte = MSB)
            case (byte_count)
                2'd0: assemble_reg[31:24] <= byte_in;
                2'd1: assemble_reg[23:16] <= byte_in;
                2'd2: assemble_reg[15:8]  <= byte_in;
                2'd3: assemble_reg[7:0]   <= byte_in;
            endcase

            if (byte_count == 2'd3) begin
                // 4th byte just arrived - this clock's assemble_reg
                // update (byte 3) won't be visible until NEXT edge, so
                // the write pulse fires one cycle later (see below)
                byte_count <= 2'd0;
            end else begin
                byte_count <= byte_count + 2'd1;
            end
        end

        if (word_write_pending)
            wr_en_reg <= 1'b1;

        // IMPORTANT: advance word_addr based on wr_en_reg's CURRENT
        // (pre-edge) value - i.e., "wr_en_reg was ALREADY high entering
        // this cycle", meaning the actual imem write is committing
        // RIGHT NOW using word_addr's still-unincremented value. This
        // must NOT be gated on word_write_pending (that's the cycle
        // BEFORE wr_en_reg becomes visible) - doing so caused every
        // word to land one address ahead of where it should.
        if (wr_en_reg) begin
            if (word_addr == 12'd4095) begin // at 4096 words, a full UART load takes ~17s at 9600 baud (still on hold, not currently in use)
                done_reg    <= 1'b1;
                loading_reg <= 1'b0;
                word_addr   <= 12'd0; // ready for a fresh load next time
            end else begin
                word_addr <= word_addr + 12'd1;
            end
        end
    end

    // word_write_pending: true for exactly the cycle right after the
    // 4th byte's data landed in assemble_reg
    reg word_write_pending_reg = 1'b0;
    wire word_write_pending = word_write_pending_reg;
    always @(posedge clk)
        word_write_pending_reg <= byte_ready && (byte_count == 2'd3);

endmodule