`timescale 1ns/1ps

// tc32v_counter_sva: assertions for tc32v_counter, attached to it with `bind`.
//
// It is the template for the assertions of the other modules
// (sva/<module>_sva.sv). Why a separate module instead of assertions inside
// the RTL:
//
//   - the RTL stays clean, without `ifndef SYNTHESIS`;
//   - the `bind` at the end of this file instantiates this module inside
//     EVERY instance of tc32v_counter, without changing a line of
//     tc32v_counter.sv;
//   - the assertions hold in any testbench that uses the counter, not only in
//     tc32v_counter_tb.
//
// The Makefile compiles sva/ only in Verilator (lint and tests). Yosys never
// sees these files: assertions do not become hardware.
//
// Every port is an input: this module only watches the counter. The names are
// the same as the counter's, so the `.*` in the bind connects them by name.

module tc32v_counter_sva #(
    parameter int WIDTH = 8
) (
    input logic             clk,
    input logic             rst,
    input logic             en,
    input logic [WIDTH-1:0] q
);

    // A concurrent assertion is checked at every edge of clk. `a |=> b`
    // means "if a holds at this edge, b must hold at the next one".
    // `disable iff (rst)` turns the check off during reset.
    //
    // A failure prints the message and stops the simulation with a non-zero
    // exit code: the test fails, like an assert in the testbench.

    // After an edge with rst = 1, q is zero.
    reset_clears: assert property (@(posedge clk) rst |=> q == '0)
        else $error("q = %0d after reset, expected 0", q);

    // With en = 1, q goes up by one (and back to zero after the maximum: the
    // sum is done in WIDTH bits, so the overflow drops out by itself).
    en_increments: assert property (@(posedge clk) disable iff (rst)
        en |=> q == WIDTH'($past(q) + 1'b1))
        else $error("q = %0d with en = 1, expected %0d", q, WIDTH'($past(q) + 1'b1));

    // With en = 0, q does not change.
    no_en_holds: assert property (@(posedge clk) disable iff (rst)
        !en |=> $stable(q))
        else $error("q changed from %0d to %0d with en = 0", $past(q), q);

endmodule

// Puts a tc32v_counter_sva (instance u_sva) inside every tc32v_counter. WIDTH
// comes from the counter, so the assertions follow whatever width the parent
// picks.
bind tc32v_counter tc32v_counter_sva #(.WIDTH(WIDTH)) u_sva (.*);
