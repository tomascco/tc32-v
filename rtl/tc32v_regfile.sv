module tc32v_regfile
import tc32v_pkg::*;
(
    output word_t      rd1,
    output word_t      rd2,
    input  logic       clk,
    input  reg_index_t  a1, 
    input  reg_index_t  a2,
    input  reg_index_t  a3,
    input  word_t      wd3,
    input  logic       we3
);
    
    // x0 == 0
    word_t registers [31:1];
    
    assign rd1 = a1 == '0 ? '0 : registers[a1];
    assign rd2 = a2 == '0 ? '0 : registers[a2];
    
    always_ff @(posedge clk) begin
        if (we3 && a3 != '0) begin
            registers[a3] <= wd3;
        end
    end
endmodule
