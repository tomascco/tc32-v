// tc32v_counter: WIDTH-bit binary counter.
//
// - rst = 1: goes back to zero on the next rising edge of clk (synchronous reset).
// - en  = 1: increments by one each cycle.
// - en  = 0: holds the value.
// - Past the maximum value (all bits set to 1), it wraps around to zero.
//
// rst has priority over en.

module tc32v_counter #(
    parameter int WIDTH = 8
) (
    input  logic             clk,
    input  logic             rst,
    input  logic             en,
    output logic [WIDTH-1:0] q
);

    always_ff @(posedge clk) begin
        if (rst) begin
            q <= '0;
        end else if (en) begin
            // WIDTH'(1) is the constant 1 with WIDTH bits, so the sum has the
            // same width as q (Verilator warns when the widths differ).
            // The sum drops the carry, so overflow wraps to zero by itself.
            q <= q + WIDTH'(1);
        end
    end
endmodule
