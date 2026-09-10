//====================================================================
// uart_rx.v  (UART receiver, standard 8N1 format)
//
// Runs on the raw 50MHz board clock (clk), NOT the divided cpu_clk -
// baud-rate timing needs to be precise and doesn't benefit from
// running slower.
//
// Standard UART framing: 1 start bit (line goes low), 8 data bits
// (LSB first), 1 stop bit (line goes high). We sample each bit in
// the MIDDLE of its time slot (not at the edge) - this is the
// standard technique for tolerating small clock/timing mismatches
// between sender and receiver.
//====================================================================

module uart_rx #(
    parameter CLK_FREQ  = 50_000_000,
    parameter BAUD_RATE = 9600
) (
    input        clk,
    input        rx,          // the physical UART_RXD pin (already
                               // synchronized - see note in top-level)
    output reg [7:0] data_out,
    output reg       byte_ready  // one-clk-wide pulse: a full byte just arrived
);

    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE; // 50,000,000/9600 ~= 5208

    localparam IDLE  = 3'd0;
    localparam START = 3'd1;
    localparam DATA  = 3'd2;
    localparam STOP  = 3'd3;

    reg [2:0]  state = IDLE;
    reg [15:0] clk_count = 0;
    reg [2:0]  bit_index = 0;
    reg [7:0]  shift_reg = 0;

    always @(posedge clk) begin
        byte_ready <= 1'b0; // default: only pulses high for exactly 1 cycle

        case (state)
            IDLE: begin
                clk_count <= 0;
                bit_index <= 0;
                if (rx == 1'b0) // start bit detected (line went low)
                    state <= START;
            end

            START: begin
                // wait to the MIDDLE of the start bit to confirm it's
                // real (not just a glitch) before committing to it
                if (clk_count == (CLKS_PER_BIT/2)) begin
                    if (rx == 1'b0) begin // still low - genuine start bit
                        clk_count <= 0;
                        state <= DATA;
                    end else begin
                        state <= IDLE; // was just a glitch, abort
                    end
                end else begin
                    clk_count <= clk_count + 1;
                end
            end

            DATA: begin
                // sample each data bit at the middle of its slot
                if (clk_count < CLKS_PER_BIT - 1) begin
                    clk_count <= clk_count + 1;
                end else begin
                    clk_count <= 0;
                    shift_reg[bit_index] <= rx; // LSB first
                    if (bit_index < 7) begin
                        bit_index <= bit_index + 1;
                    end else begin
                        bit_index <= 0;
                        state <= STOP;
                    end
                end
            end

            STOP: begin
                if (clk_count < CLKS_PER_BIT - 1) begin
                    clk_count <= clk_count + 1;
                end else begin
                    data_out   <= shift_reg;
                    byte_ready <= 1'b1; // pulse high for exactly 1 clk
                    clk_count  <= 0;
                    state      <= IDLE;
                end
            end

            default: state <= IDLE;
        endcase
    end

endmodule