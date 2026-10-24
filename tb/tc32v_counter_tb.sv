// tc32v_counter_tb: testbench for tc32v_counter.
//
// It is the template for the other testbenches. It has three parts:
//
//   1. Directed tests: hand-picked cases, checked with assert.
//   2. Random test: a transaction class with rand fields and a constraint
//      generates stimulus; a reference model (an SV function) says what the
//      output should be, cycle by cycle.
//   3. Functional coverage: a covergroup counts which interesting situations
//      were exercised, and the result is printed at the end.
//
// How to run:
//   make test tc32v_counter            (seed 1)
//   SEED=7 make test tc32v_counter     (another seed)
//   make waves tc32v_counter           (writes build/tc32v_counter.fst)
//
// Timing convention: inputs change 1 time unit after the rising clock edge
// and are sampled by the DUT on the next edge. This way there is never a race
// between the testbench and the DUT's always_ff.

module tc32v_counter_tb;

    // Small width on purpose: with 4 bits the counter wraps every 16
    // increments, so overflow also shows up in the random test.
    localparam int WIDTH = 4;
    localparam logic [WIDTH-1:0] MAX = '1;  // all bits set to 1

    // Number of cycles in the random test.
    localparam int N_CYCLES = 2000;

    // -----------------------------------------------------------------------
    // Clock, signals and DUT
    // -----------------------------------------------------------------------

    logic             clk = 1'b0;
    logic             rst;
    logic             en;
    logic [WIDTH-1:0] q;

    always #5 clk = ~clk;  // period of 10 time units

    tc32v_counter #(
        .WIDTH(WIDTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .en (en),
        .q  (q)
    );

    // Waves: only written when the simulator gets +dumpfile=<file>
    // (`make waves tc32v_counter` does that).
    initial begin
        string dump_file;
        if ($value$plusargs("dumpfile=%s", dump_file) != 0) begin
            $dumpfile(dump_file);
            $dumpvars(0, tc32v_counter_tb);
        end
    end

    // -----------------------------------------------------------------------
    // Part 3 (declared here because step() samples it): coverage
    // -----------------------------------------------------------------------

    // True in the cycle where the counter is at its maximum and is about to
    // increment, that is, the cycle where overflow happens.
    logic overflow;
    assign overflow = en && !rst && (q == MAX);

    covergroup counter_cg;
        cp_en: coverpoint en;
        cp_rst: coverpoint rst;
        cp_overflow: coverpoint overflow {
            bins happened = {1'b1};
        }
        // Every combination of en and rst (including rst and en together, to
        // see that rst has priority).
        cx_en_rst: cross cp_en, cp_rst;
    endgroup

    counter_cg cg;

    // -----------------------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------------------

    // Applies rst/en, samples coverage and waits for the DUT to react.
    task automatic step(input logic rst_i, input logic en_i);
        rst = rst_i;
        en  = en_i;
        cg.sample();  // samples this cycle's inputs and overflow
        @(posedge clk);
        #1;  // flip-flop output already stable
    endtask

    // Checks the output against the expected value.
    task automatic check(input logic [WIDTH-1:0] expected, input string context_msg);
        assert (q == expected)
        else $fatal(1, "%s: expected q=%0d, got q=%0d (t=%0t)", context_msg, expected, q, $time);
    endtask

    // -----------------------------------------------------------------------
    // Part 1: directed tests
    // -----------------------------------------------------------------------

    task automatic directed_tests();
        $display("[part 1] directed tests");

        // Reset: after one cycle with rst=1, q is 0.
        step(1'b1, 1'b0);
        check('0, "reset");

        // Increment: each cycle with en=1 adds 1.
        for (int i = 1; i <= 5; i++) begin
            step(1'b0, 1'b1);
            check(WIDTH'(i), "increment");
        end

        // en=0 holds the value.
        for (int i = 0; i < 3; i++) begin
            step(1'b0, 1'b0);
            check(WIDTH'(5), "en=0 holds the value");
        end

        // rst has priority over en.
        step(1'b1, 1'b1);
        check('0, "rst with en=1");

        // Overflow: count up to the maximum and check that the next add gives 0.
        for (int i = 1; i <= int'(MAX); i++) begin
            step(1'b0, 1'b1);
        end
        check(MAX, "counted up to the maximum");
        step(1'b0, 1'b1);
        check('0, "overflow wraps to zero");
    endtask

    // -----------------------------------------------------------------------
    // Part 2: random test with a reference model
    // -----------------------------------------------------------------------

    // One transaction = the input values for one cycle.
    class counter_txn;
        rand bit rst;
        rand bit en;

        // Rare rst (1 in 20 cycles, on average), so the counter has time to
        // count and reach overflow between one reset and the next.
        constraint c_rare_rst {
            rst dist {
                1'b1 := 1,
                1'b0 := 19
            };
        }
    endclass

    // Reference model: what the counter should do, written as directly as
    // possible, without thinking about hardware.
    function automatic logic [WIDTH-1:0] ref_model(input logic [WIDTH-1:0] current, input bit rst_i,
                                                   input bit en_i);
        if (rst_i) return '0;
        if (en_i) return current + WIDTH'(1);
        return current;
    endfunction

    task automatic random_test();
        counter_txn       txn;
        logic [WIDTH-1:0] expected;
        int               n_rst;

        $display("[part 2] random test: %0d cycles", N_CYCLES);
        txn      = new();
        expected = q;  // continue from where part 1 stopped
        n_rst    = 0;

        for (int cycle = 0; cycle < N_CYCLES; cycle++) begin
            assert (txn.randomize() == 1)
            else $fatal(1, "randomize() failed in cycle %0d", cycle);

            expected = ref_model(expected, txn.rst, txn.en);
            step(txn.rst, txn.en);
            check(expected, $sformatf("random, cycle %0d (rst=%0b en=%0b)", cycle, txn.rst, txn.en));
            n_rst += int'(txn.rst);
        end
        $display("[part 2] %0d resets in %0d cycles", n_rst, N_CYCLES);
    endtask

    // -----------------------------------------------------------------------
    // Main sequence
    // -----------------------------------------------------------------------

    initial begin
        int seed;

        // The seed comes from +verilator+seed+N (the Makefile passes SEED).
        // Printing the seed lets you reproduce a failure exactly.
        if ($value$plusargs("verilator+seed+%d", seed) == 0) seed = 0;
        $display("seed: %0d", seed);

        cg  = new();
        rst = 1'b1;
        en  = 1'b0;
        @(posedge clk);
        #1;

        directed_tests();
        random_test();

        $display("[part 3] total coverage: %0.1f%%", cg.get_coverage());

        // Coverage of each coverpoint on its own. Verilator 5.053 does not yet
        // accept get_coverage() on a coverpoint ("Unsupported: Member call on
        // object"), only on the whole covergroup. Disabled until it does; to
        // try it (in xsim, for example), define TC32V_COVERPOINT_REPORT.
`ifdef TC32V_COVERPOINT_REPORT
        $display("[part 3] en %0.1f%%, rst %0.1f%%, overflow %0.1f%%, en x rst %0.1f%%",
                 cg.cp_en.get_coverage(), cg.cp_rst.get_coverage(),
                 cg.cp_overflow.get_coverage(), cg.cx_en_rst.get_coverage());
`endif

        $display("PASS");
        $finish;
    end

endmodule
