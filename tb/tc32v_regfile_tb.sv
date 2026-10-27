`timescale 1ns/1ps

module tc32v_regfile_tb;
    import tc32v_pkg::*;

    word_t rd1, rd2;
    logic clk;

    reg_index_t a1, a2, a3;
    word_t wd;
    logic  we3;

    tc32v_regfile dut(.*);

    initial begin
        string dump_file;
        if ($value$plusargs("dumpfile=%s", dump_file) != 0) begin
            $dumpfile(dump_file);
            $dumpvars(0, tc32v_regfile_tb);
        end
    end

    initial begin
        clk  = 0;
    end

    always #1 clk = ~clk;

    // Reading and writing the same register
    initial begin
        // x0 is always zero
        a2 = '0;
        #1
        assert(rd2 == '0)
            else $fatal(1, "Expected x0 to be fixed in 0, got %d", rd2);

        // x1 = h7FFF_FFFF
        a3 = 5'd1;
        we3 = 1;
        wd = 32'h7FFF_FFFF;
        #2

        assert(dut.registers[1] == 32'h7FFF_FFFF)
            else $fatal(1, "Expected 32'h%h, received 32'h%h", 32'h7FFF_FFFF, dut.registers[1]);

        // x2 = h0000_0000
        a3 = 5'd2;
        wd = 32'd1;
        #2
        assert(dut.registers[2] == 32'd1)
            else $fatal(1, "Expected 32'h%h, received 32'h%h", 32'h0000_0001, dut.registers[2]);
        
        // x2 not changed, we3 disabled
        we3 = 0;
        a3 = 5'd2;
        wd = 32'd24;
        #2
        assert(dut.registers[2] == 32'd1)
            else $fatal(1, "Expected 32'h%h, received 32'h%h", 32'h0000_0001, dut.registers[2] == 32'd1);


        a1 = 5'd1;
        a2 = 5'd2;
        #1

        assert(rd1 == 32'h7FFF_FFFF)
            else $fatal(1, "Expected 32'h%h, received 32'h%h", 32'h7FFF_FFFF, rd1);

        assert(rd2 == 32'h0000_0001)
            else $fatal(1, "Expected 32'h%h, received 32'h%h", 32'h0000_0001, rd2);

        we3 = 1;
        a3  = '0;
        wd  = 32'd100;
        a1  = '0;
        #2

        assert(rd1 == '0)
            else $fatal(1, "Expected x0 to be fixed in 0, got %d", rd1);

        $display("PASS");
        $finish;
    end

endmodule
