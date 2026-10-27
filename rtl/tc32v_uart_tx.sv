`timescale 1ns/1ps

module tc32v_uart_tx #(
) (
    output logic tx,
    output logic busy,
    input  logic clk,
    input  logic rst,
    input  logic start,
    input  logic [7:0] d
);

    typedef enum logic { IDLING, SENDING } fsm_t;
    fsm_t state;
    logic bit_end, last_bit;
    logic [9:0] dataframe;
    
    logic bit_counter_en;
    logic bit_counter_rst;
    logic [3:0]  bit_count;
    tc32v_counter #(.WIDTH(4)) bit_counter (.clk, .rst(bit_counter_rst), .en(bit_counter_en), .q(bit_count));
    
    logic baud_counter_en;
    logic baud_counter_rst;
    logic [7:0] baud_count;
    tc32v_counter #(.WIDTH(8)) baud_counter (.clk, .rst(baud_counter_rst), .en(baud_counter_en), .q(baud_count));
    

    // FSM State control
    fsm_t next_state;
    always_comb begin
        case (state)
            IDLING : next_state = start ? SENDING : IDLING;
            SENDING: next_state = (last_bit && bit_end) ? IDLING : SENDING;
        endcase
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLING;
        end else begin
            state <= next_state;
        end
    end

    // Datapath shift register control
    always_ff @(posedge clk) begin
        if (rst) begin
            dataframe <= '1;
        end else if (state == IDLING && next_state == SENDING) begin
            dataframe <= {1'b1, d, 1'b0};
        end else if (state == SENDING && bit_end) begin
            dataframe <= {1'b1, dataframe[9:1]};
        end
    end

    // Datapath baud counter control
    always_comb begin
        baud_counter_rst = 0;
        baud_counter_en  = 0;

        if (rst) begin
            baud_counter_rst = 1;
        end else if (state == SENDING) begin
            baud_counter_en = 1;

            if (bit_end) begin
                baud_counter_rst = 1;
            end
        end
    end

    // Datapath bit counter control
    always_comb begin
        bit_counter_rst = 0;
        bit_counter_en  = 0;

        if (rst) begin
            bit_counter_rst = 1;
        end else if (state == SENDING && bit_end && ~last_bit) begin
            bit_counter_en = 1;
        end else if (state == IDLING && next_state == SENDING) begin
            bit_counter_rst = 1;
        end
    end

    // Datapath signals
    assign last_bit = bit_count == 9;
    assign bit_end  = baud_count == 216;
    assign tx       = dataframe[0];
    assign busy     = (state == SENDING) ? 1 : 0;
endmodule
