`timescale 1ns/1ps

// selfcheck_fail_tb: a test that MUST fail.
//
// It exists to prove the flow works: a failing assert has to end the
// simulation with a non-zero exit code, and CI has to turn red.
// `make selfcheck` runs this test and only passes if it fails.
//
// It is not part of `make test <module>`: it is only called by `make selfcheck`
// (which `make test` includes).

module selfcheck_fail_tb;

    initial begin
        int expected;
        int actual;

        expected = 1;
        actual   = 2;
        assert (actual == expected)
        else $fatal(1, "intentional failure: expected %0d, got %0d", expected, actual);

        // Should never get here.
        $display("PASS");
        $finish;
    end

endmodule
