module
(
    output [7:0] q,
    input        clk,
    input        rst_n,
    input        serial_en,
    input  [1:0] sel,
    input        serial_in,
    input        parallel_en,
    input  [7:0] d
);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            q <= 8'd0;
        end else begin
            case (sel)
                2'00   : q <= d;
                2'10   : q <= {q[6:0], serial_in};
                2'01   : q <= {serial_in, q[7:1]};
            endcase
        end 
    end
endmodule
