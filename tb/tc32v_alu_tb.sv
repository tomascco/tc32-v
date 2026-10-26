`timescale 1ns/1ps

module tc32v_alu_tb;
    import tc32v_pkg::*;

    word_t   a, b, result;
    alu_op_t op;
    logic        zero_h;

    tc32v_alu dut(.a, .b, .op, .result, .zero_h); 

    task automatic assert_output(
        input word_t   test_a,
        input word_t   test_b,
        input alu_op_t test_op,
        input word_t   expected,
        input logic    expected_zero
    );
        a  = test_a;
        b  = test_b;
        op = test_op;
        #1;
        assert(result == expected) else
            $fatal(1, "Expected %d, received %d\nInputs: %d, %d, %s", expected, result, test_a, test_b, test_op);

        assert(zero_h == expected_zero) else
            $fatal(1, "Expected zero to be %d, received %d\nInputs: %d, %d, %s", expected_zero, zero_h, test_a, test_b, test_op);
    endtask

    localparam word_t MAX_U = '1;
    localparam word_t MAX_S = 32'h7FFF_FFFF;
    localparam word_t MIN_S = 32'h8000_0000;

    initial begin
        assert_output( -1,   1, ALU_ADD,   0, 1);
        assert_output( -1,  -1, ALU_ADD,  -2, 0);
        assert_output(100, 100, ALU_ADD, 200, 0);
        assert_output(100,  99, ALU_ADD, 199, 0);


        assert_output( 100, 100, ALU_SUB,    0, 1);
        assert_output(-100, -99, ALU_SUB,   -1, 0);
        assert_output(-100, 100, ALU_SUB, -200, 0);

        assert_output(-1,  0, ALU_SLT, 1, 0);
        assert_output(-1, -2, ALU_SLT, 0, 1);
        assert_output( 1,  2, ALU_SLT, 1, 0);
        assert_output( 0,  0, ALU_SLT, 0, 1);
        
        // -1 is hffffffff
        assert_output(-1,  0, ALU_SLTU, 0, 1);
        assert_output(-1, -2, ALU_SLTU, 0, 1);
        assert_output( 1,  2, ALU_SLTU, 1, 0);
        assert_output( 0,  0, ALU_SLTU, 0, 1);

        assert_output(16,  1, ALU_SLL, 32, 0);
        assert_output(16,  1, ALU_SRL,  8, 0);
        assert_output(-16, 1, ALU_SRA, -8, 0);

        assert_output(
            'b1010,
            'b1100,
            ALU_AND,
            'b1000,
            0
        );

        assert_output(
            'b1010,
            'b1100,
            ALU_ORR,
            'b1110,
            0
        );

        assert_output(
            'b1010,
            'b1100,
            ALU_XOR,
            'b0110,
            0
        );

        // TODO: I think underflow and overflows should
        // raise exceptions, see later in spec.
        assert_output(MIN_S,  1, ALU_SUB,  MAX_S, 0);
        assert_output(MAX_U,  1, ALU_ADD,      0, 1);

        $display("PASS");
        $finish;
    end    
endmodule
