`timescale 1ns/1ps

module tc32v_extend_tb;
    import tc32v_pkg::*;

    word_t       out;
    logic [31:0] insn;
    imm_t imm_type;

    tc32v_extend dut(.imm_slice(insn[31:7]), .*);

    initial begin
        string dump_file;
        if ($value$plusargs("dumpfile=%s", dump_file) != 0) begin
            $dumpfile(dump_file);
            $dumpvars(0, tc32v_extend_tb);
        end
    end

    initial begin
        // addi x0, x1,  2047 = 32'h7ff08013
        insn     = 32'h7ff08013;
        imm_type = I_SIGNED_12_BITS;
        #1;
        assert (out == $signed(2047));
            else $fatal(1, "Assertion expected %d, got %d", 2047, out);

        // addi x0, x1, -2048 = 32'h80008013
        insn     = 32'h80008013;
        imm_type = I_SIGNED_12_BITS;
        #1;
        assert (out == $signed(-2048));
            else $fatal(1, "Assertion expected %d, got %d", -2048, out);

        // sw x0, 0(x1)       = 32'h0000a023
        insn     = 32'h0000a023;
        imm_type = S_SIGNED_12_BITS;
        #1;
        assert (out == $signed(0));
            else $fatal(1, "Assertion expected %d, got %d", 0, out);

        // beq x3, x4,   4094 = 32'h7e418fe3
        insn     = 32'h7e418fe3;
        imm_type = B_SIGNED_13_BITS;
        #1;
        assert (out == $signed(4094));
            else $fatal(1, "Assertion expected %d, got %d", 4094, out);

        // beq x3, x4,  -4096 = 32'h80418063
        insn     = 32'h80418063;
        imm_type = B_SIGNED_13_BITS;
        #1;
        assert (out == $signed(-4096));
            else $fatal(1, "Assertion expected %d, got %d", -4096, out);

        // lui x0,         -1 = 32'hfffff037
        insn     = 32'hfffff037;
        imm_type = U_UPPER_20_BITS;
        #1;
        assert (out == 4294963200);
            else $fatal(1, "Assertion expected %d, got %d", 4294963200, out);

        // jal x15,  -1048576 = 32'h800007ef
        insn     = 32'h800007ef;
        imm_type = J_SIGNED_21_BITS;
        #1;
        assert (out == $signed(-1048576));
            else $fatal(1, "Assertion expected %d, got %d", $signed(-1048576), out);

        $display("PASS");
        $finish;
    end
endmodule
