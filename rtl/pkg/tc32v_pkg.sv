`timescale 1ns/1ps

package tc32v_pkg;
    typedef logic [3:0][7:0] word_t;

    typedef enum logic [3:0] {
        ALU_ADD,
        ALU_SUB,
        ALU_AND,
        ALU_ORR,
        ALU_XOR,
        ALU_SLT,
        ALU_SLTU,
        ALU_SLL,
        ALU_SRL,
        ALU_SRA
    } alu_op_t;

    typedef logic [4:0] reg_index_t;

    typedef enum logic [2:0] {
        I_SIGNED_12_BITS,
        S_SIGNED_12_BITS,
        B_SIGNED_13_BITS,
        U_UPPER_20_BITS,
        J_SIGNED_21_BITS
    } imm_t;

endpackage
