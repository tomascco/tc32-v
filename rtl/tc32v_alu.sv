`timescale 1ns/1ps

module tc32v_alu
import tc32v_pkg::*;

(
    output word_t   result,
    output logic    zero_h,
    input  word_t   a,
    input  word_t   b,
    input  alu_op_t op
);
    
    always_comb begin
        case (op)
            ALU_ADD : result = 32'(a + b);
            ALU_SUB : result = 32'(a - b);
            ALU_AND : result = 32'(a & b);
            ALU_ORR : result = 32'(a | b);
            ALU_XOR : result = 32'(a ^ b);
            ALU_SLT : result = 32'($signed(a) < $signed(b));
            ALU_SLTU: result = 32'(a < b);
            ALU_SLL : result = a << b[0][4:0];
            ALU_SRL : result = a >> b[0][4:0];
            ALU_SRA : result = $signed(a) >>> b[0][4:0];
            // TODO: this should raise an exception.
            default: result = 32'(0);
        endcase
    end

    assign zero_h = result == '0;
endmodule
