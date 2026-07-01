// Code your design here
//===============================================================
// TOP MODULE : UART TX → UART RX LOOPBACK + BAUD GENERATOR
//===============================================================
module uart_top(
    input  wire clk,           // system clock (100 MHz)
    input  wire rst,           // reset
    input  wire tx_start,      // start transmission
    input  wire [7:0] tx_data, // data to send
    output wire tx,            // UART TX pin (also fed to RX)
    output wire tx_done,       // TX finished flag
    output wire [7:0] rx_data, // received byte
    output wire rx_done,       // RX finished flag
    output wire parity_error   // parity status
);

    //-----------------------------------------------------------
    // 16× Baud Clock Generator
    //-----------------------------------------------------------
    wire uart_clk;

    baud_gen #(
        .CLK_FREQ(100_000_000),
        .BAUD(9600)
    ) baud_inst (
        .clk(clk),
        .rst(rst),
        .tick(uart_clk)         // 16× baud clock
    );

    //-----------------------------------------------------------
    // UART TRANSMITTER
    //-----------------------------------------------------------
    uart_tx tx_inst (
        .clk(clk),
        .rst(rst),
        .uart_clk(uart_clk),
        .tx_start(tx_start),
        .din(tx_data),
        .tx(tx),                // TX pin
        .tx_done(tx_done)
    );

    //-----------------------------------------------------------
    // INTERNAL LOOPBACK: TX → RX
    //-----------------------------------------------------------
    wire rx_internal = tx;      // LOOPBACK CONNECTION

    //-----------------------------------------------------------
    // UART RECEIVER
    //-----------------------------------------------------------
    uart_rx rx_inst (
        .rst(rst),
        .clk(clk),
        .uart_clk(uart_clk),
        .rx(rx_internal),       // receiving from TX internally
        .dout(rx_data),
        .rx_done(rx_done),
        .parity_error(parity_error)
    );

endmodule
module baud_gen #(
    parameter CLK_FREQ = 100_000_000,
    parameter BAUD     = 9600
)(
    input  wire clk,
    input  wire rst,
    output reg  tick                  // 16× baud tick
); 

    localparam DIV = CLK_FREQ / (BAUD * 16);
    reg [15:0] count;

    always @(posedge clk) begin
        if (rst) begin
            count <= 0;
            tick  <= 0;
        end else begin
            if (count == DIV - 1) begin
                count <= 0;
                tick  <= 1;
            end else begin
                count <= count + 1;
                tick  <= 0;
            end
        end
    end
endmodule

//===============================================================
// UART TRANSMITTER (each bit repeated 16 times)
//===============================================================
module uart_tx(
    input  wire clk,
    input  wire rst,
    input  wire uart_clk,
    input  wire tx_start,
    input  wire [7:0] din,
    output reg  tx,
    output reg  tx_done
);

    parameter IDEAL = 2'b00,
              SHIFT = 2'b01,
              STOP  = 2'b10;

    reg [1:0]  state;
    reg [3:0]  bit_count;      // bit index (0..10)
    reg [3:0]  sample_cnt;     // repeats each bit 16 times (0..15)
    reg [10:0] shift_reg;      // start + data + parity + stop
    reg [7:0]  hold_reg;       // holds din temporarily
    reg        load_shift;     // signal to load shift_reg from hold_reg

    always @(posedge clk) begin
        if (rst) begin
            tx          <= 1;
            tx_done     <= 0;
            state       <= IDEAL;
            bit_count   <= 0;
            sample_cnt  <= 0;
            hold_reg    <= 0;
            shift_reg   <= 0;
            load_shift  <= 0;
        end else begin
            tx_done <= 0;

            case(state)

            // ----------------------------------------------------
            // IDLE STATE
            // ----------------------------------------------------
            IDEAL: begin
                if (tx_start) begin
                    hold_reg   <= din;        // store input in hold register
                    bit_count  <= 0;
                    sample_cnt <= 0;
                    load_shift <= 1;          // request shift register load
                    state      <= SHIFT;
                end
            end

            // ----------------------------------------------------
            // SHIFT STATE (repeat each bit 16 times)
            // ----------------------------------------------------
SHIFT: begin
    if (load_shift) begin
        // Load shift register from hold register on next clk
        shift_reg[0]   <= 0;           // start bit
        shift_reg[8:1] <= hold_reg;    // data bits
        shift_reg[9]   <= ^hold_reg;   // parity
        shift_reg[10]  <= 1;           // stop bit
        load_shift     <= 0;
        sample_cnt     <= 0;
      bit_count<=0;// reset sample counter
    end

    if (uart_clk) begin
        tx <= shift_reg[0];             // output LSB of shift register

        if (sample_cnt == 15) begin     // 16 samples per bit
            sample_cnt <= 0;
            // shift right, fill MSB with 1
            shift_reg <= {1'b1, shift_reg[10:1]};
          bit_count<=bit_count+1;
            // check if all bits sent (all 1’s)
          if (bit_count==10) begin
                state <= STOP;
            end
        end else begin
            sample_cnt <= sample_cnt + 1;
        end
    end
end

            // ----------------------------------------------------
            // STOP STATE
            // ----------------------------------------------------
            STOP: begin
                hold_reg<=0;
                tx      <= 1;
                tx_done <= 1;
                state   <= IDEAL;
            end

            endcase
        end
    end
endmodule
//===============================================================
// UART RECEIVER (each bit is received over 16 samples)
//===============================================================
module uart_rx(
    input  wire rst,
    input  wire clk,
    input  wire uart_clk,
    input  wire rx,
    output reg [7:0] dout,
    output reg rx_done,
    output reg parity_error
);

    parameter IDEAL = 2'b00,
              SHIFT = 2'b01,
              STOP  = 2'b10;

    reg [1:0] state;
    reg [3:0] uart_count;   // 0–15 oversampling counter
    reg [3:0] bit_count;    // 0–10 (11 bits total)
    reg [10:0] shift_data;  // start + data + parity + stop
    reg [7:0]buffer_reg;

    always @(posedge clk) begin
        if (rst) begin
            state        <= IDEAL;
            uart_count   <= 0;
            bit_count    <= 0;
            shift_data   <= 0;
            rx_done      <= 0;
            parity_error <= 0;
            dout<=0;
            buffer_reg<=0;
        end else begin
            rx_done <= 0;

            case(state)

            //-----------------------------------------------------
            // WAIT FOR START BIT (rx goes LOW)
            //-----------------------------------------------------
            IDEAL: begin
                if (rx == 0) begin
                    state      <= SHIFT;
                    uart_count <= 0;
                    bit_count  <= 0;
                end
            end

            //-----------------------------------------------------
            // RECEIVE 11 BITS (oversampled 16× each)
            //-----------------------------------------------------
            SHIFT: begin
                if (uart_clk) begin
                    uart_count <= uart_count + 1;

                    // Sample at middle of bit period
                    if (uart_count == 7)
                        shift_data[bit_count] <= rx;

                    // After 16 samples → move to next bit
                    if (uart_count == 15) begin
                        uart_count <= 0;

                        if (bit_count == 10)
                            state <= STOP;          // All bits received
                        else
                            bit_count <= bit_count + 1;
                    end
                end
            end

            //-----------------------------------------------------
            // CHECK PARITY AND OUTPUT DATA
            //-----------------------------------------------------
/*            STOP: begin
                dout <= shift_data[8:1];

                // parity check: stored parity should match XOR of data
                parity_error <= ((^shift_data[8:1]) != shift_data[9]);

                rx_done <= 1;
                state   <= IDEAL;
            end
*/
STOP: begin
    // Store received data in buffer
    buffer_reg <= shift_data[8:1];

    // Check parity
    parity_error <= ((^shift_data[8:1]) != shift_data[9]);

    // If parity is correct, output the buffered data to dout
    if ((^shift_data[8:1]) == shift_data[9])
        dout <= shift_data[8:1];  // use shift_data directly for immediate assignment
    else
        dout <= 8'b0;              // optional: clear dout on parity error

    rx_done <= 1;
    state   <= IDEAL;
end


            endcase
        end
    end
endmodule
