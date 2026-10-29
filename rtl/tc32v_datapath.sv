`timescale 1ns/1ps

module tc32v_alu
import tc32v_pkg::*;

(
    output logic        zero_h,
    input  logic        clk,
    input  logic [31:0] insn,
    input  logic        reg_write,
    input  logic        alu_src,
    input  alu_op_t     alu_op,
    input  imm_t        imm_type
);

    word_t rd1, rd2;
    word_t alu_result;

    tc32v_regfile regfile(
        .clk(clk),
        .a1(insn[19:15]),
        .a2(insn[24:20]),
        .a3(insn[11:7]),
        .rd1(rd1),
        .rd2(rd2),
        .we3(reg_write),
        .wd(result)
    );

    word_t immediate;

    tc32v_extend extend(
        .imm_slice(insn[31:7]),
        .imm_type(imm_type),
        .out(immediate)
    )

    word_t alu_b;

    // create typedef
    assign

    tc32v_alu alu(
        .a(rd1),

    );



endmodule
