`timescale 1ns/1ps

module tc32v_uart_tx_tb;
    import tc32v_pkg::*;
    
    logic tx, busy, clk, rst, start;
    logic [7:0] d;

    tc32v_uart_tx dut(.*);

    initial begin
        string dump_file;
        if ($value$plusargs("dumpfile=%s", dump_file) != 0) begin
            $dumpfile(dump_file);
            $dumpvars(0, tc32v_uart_tx_tb);
        end
    end

    initial begin
        clk  = 0;
    end

    always #1 clk = ~clk;

    initial begin
        rst = 1;
        #1000;
        rst = 0;
        d = 8'b0101_0101;
        start = 1;
        #2;
        start = 0;
        #5340;

        $display("PASS");
        $finish;
    end
endmodule
