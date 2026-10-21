module tc32v_alu (
    input  logic [31:0] a,
    input  logic [31:0] b,
    input  logic [3: 0] op,
    output logic [31:0] result,
    output logic        zero
);
    
    always_comb begin
        case (op)
            4'b0000: result = 32'(a + b);
            4'b0001: result = 32'(a - b);
            4'b0010: result = 32'(a & b);
            4'b0011: result = 32'(a | b);
            4'b0100: result = 32'(a ^ b);
            4'b0101: result = 32'($signed(a) < $signed(b));
            4'b0110: result = 32'(a < b);
            4'b0111: result = a << b[4:0];
            4'b1000: result = a >> b[4:0];
            4'b1001: result = $signed(a) >>> b[4:0];
            default: result = 32'(0);
        endcase
    end

    assign zero = result == '0;
endmodule
