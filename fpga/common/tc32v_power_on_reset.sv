// tc32v_power_on_reset: generates rst for boards without a reset button.
//
// - rst = 1 during the first CYCLES rising edges of clk after the FPGA is
//   configured, then 0 forever.
//
// FPGA only: it relies on the bitstream loading the initial value of count
// ("= '0" below). An ASIC has no power-up value, which is why this module
// lives in fpga/ and not in rtl/ (see the RTL rules in CLAUDE.md).
//
// Usage in a board top:
//   logic rst;
//   tc32v_power_on_reset u_por (.clk(clk), .rst(rst));

module tc32v_power_on_reset #(
    parameter int unsigned CYCLES = 16
) (
    input  logic clk,
    output logic rst
);
    // Bits to hold the values 0 to CYCLES (count stops at CYCLES).
    localparam int unsigned WIDTH = $clog2(CYCLES + 1);

    logic [WIDTH-1:0] count = '0;

    always_ff @(posedge clk) begin
        if (rst) begin
            count <= count + WIDTH'(1'b1);
        end
    end

    assign rst = (count != WIDTH'(CYCLES));
endmodule
