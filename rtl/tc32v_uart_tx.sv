`timescale 1ns/1ps

module tc32v_uart_tx #(
) (
    output tx,
    output busy,
    input  clk,
    input  rst,
    input  start,
    input  [7:0] d
);

    typedef enum logic { IDLING, SENDING } fsm_t;
    fsm_t state;
    logic bit_end, last_bit;
    logic [9:0] packet;
    
    logic bit_counter_en;
    logic bit_counter_rst;
    logic [3:0]  bit_count;
    tc32v_counter #(.WIDTH(4)) bit_counter (.clk, .rst(bit_counter_rst), .en(bit_counter_en), .q(bit_count));
    
    logic baud_counter_en;
    logic baud_counter_rst;
    logic [7:0] baud_count;
    tc32v_counter #(.WIDTH(8)) baud_counter (.clk, .rst(baud_counter_rst), .en(baud_counter_en), .q(baud_count));
    
    // FSM State control
    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLING;
        end else begin
            case (state)
                IDLING : state <= start    ? SENDING : IDLING;
                SENDING: state <= last_bit ? IDLING  : SENDING;
            endcase
        end
    end

    // Datapath state control
    always_ff @(posedge clk) begin
        baud_counter_rst <= 0;
        bit_counter_rst  <= 0;

        if (rst) begin
            baud_counter_rst <= 1;
            bit_counter_rst  <= 1;
        end else if (state == IDLING && start == 1) begin
            packet <= {1'd1, d, 1'd0};

            baud_counter_en <= 1;
            bit_counter_en  <= 1;

            bit_end         <= 0;
            last_bit        <= 0;

        // 216 is number of clock cycles for a 115200 baud rate at 25mhz
        end else if (state == SENDING && baud_count == 8'd216) begin
            bit_end <= 1;
            baud_counter_rst <= 1;
        end else if (state == SENDING && bit_end) begin
            tx <= packet[0];
            packet <= {1'd1, packet[9:1]};
            
            bit_end <= 0;
        end else if (state == SENDING && bit_count == 9) begin
            last_bit <= 1;
        end
    end

    // Datapath signals
    assign last_bit = 
endmodule
