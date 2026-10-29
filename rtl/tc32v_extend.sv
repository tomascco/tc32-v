`timescale 1ns/1ps

module tc32v_extend
import tc32v_pkg::*;

(
    output word_t out,
    input  logic [31:7] imm_slice,
    input  imm_t imm_type
);

    always_comb begin
        case (imm_type)
            I_SIGNED_12_BITS: out = {{20{imm_slice[31]}}, imm_slice[31:20]};
            S_SIGNED_12_BITS: out = {{20{imm_slice[31]}}, imm_slice[31:25], imm_slice[11:7]};
            B_SIGNED_13_BITS: out = {{20{imm_slice[31]}}, imm_slice[7], imm_slice[30:25], imm_slice[11:8], 1'b0};
            J_SIGNED_21_BITS: out = {{12{imm_slice[31]}}, imm_slice[19:12], imm_slice[20], imm_slice[30:21], 1'b0};
            U_UPPER_20_BITS : out = {imm_slice[31:12], 12'b0};
            default         : out = 'x;
        endcase
    end
endmodule
