module tc32v_alu_tb;
    logic [32:0] a, b, result;
    logic [3: 0] op;
    logic        zero;

    tc32v_alu dut (
        .a(a),
        .b(b),
        .result(result),
        .op(op),
        .zero(zero)
    )


    task automatic check(input logic expected, input string context_msg);
        assert (q == expected)
        else $fatal(1, "%s: expected q=%0d, got q=%0d (t=%0t)", context_msg, expected, q, $time);
    endtask
endmodule
