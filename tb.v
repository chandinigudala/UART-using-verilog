`timescale 1ns/1ps

module tb;

    // Testbench signals
    reg clk;
    reg rst;
    reg tx_start;
    reg [7:0] tx_data;

    wire tx;
    wire tx_done;
    wire [7:0] rx_data;
    wire rx_done;
    wire parity_error;

    // ------------------------------------------
    // Instantiate the TOP module
    // ------------------------------------------
    uart_top uut(
        .clk(clk),
        .rst(rst),
        .tx_start(tx_start),
        .tx_data(tx_data),
        .tx(tx),                // TX is looped into RX inside top
        .tx_done(tx_done),
        .rx_data(rx_data),
        .rx_done(rx_done),
        .parity_error(parity_error)
    );

    // ------------------------------------------
    // Generate 100MHz clock
    // ------------------------------------------
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100 MHz clock → 10ns period
    end

    // ------------------------------------------
    // Test Sequence
    // ------------------------------------------
initial begin
    $monitor("time=%0t | state=%b | bit_count=%d | sample_cnt=%d | hold=%b | shift_reg=%b | tx=%b | tx_done=%b",
        $time,
        uut.tx_inst.state,
        uut.tx_inst.bit_count,
        uut.tx_inst.sample_cnt,
        uut.tx_inst.hold_reg,
        uut.tx_inst.shift_reg,
        uut.tx_inst.tx,
        uut.tx_inst.tx_done
    );
   /*
    $monitor("time=%0t | rx_state=%b | rx_uart_count=%d | rx_bit_count=%d | rx_shift_data=%b | rx_buffer=%b | rx_done=%b | rx_parity_error=%b | rx=%b | rx_data=%b",
    $time,
    uut.rx_inst.state,
    uut.rx_inst.uart_count,
    uut.rx_inst.bit_count,
    uut.rx_inst.shift_data,
    uut.rx_inst.buffer_reg,
    uut.rx_inst.rx_done,
    uut.rx_inst.parity_error,
    uut.rx_inst.rx,
    rx_data
);*/

end
    
       initial begin
        // Initial values
        rst = 1;
        tx_start = 0;
        tx_data = 8'b11110110;     // DATA = 0xF6

        // Apply reset
        #50;
        rst = 0;

        // Wait a little then start transmission
        #100;
        $display("Starting TX of data = %b", tx_data);

        tx_start = 1;
        #10;
        tx_start = 0;              // pulse only

        // Wait for TX to finish
        wait(tx_done == 1);
        $display("TX DONE at time %0t", $time);

        // Wait for RX to receive data
        wait(rx_done == 1);
        $display("RX DONE at time %0t", $time);
        $display("Received Data = %b", rx_data);

        // Check parity
        if (parity_error)
            $display("PARITY ERROR DETECTED!");
        else
            $display("Parity OK.");

        // Check data correctness
        if (rx_data == tx_data)
            $display("TEST PASSED ✓ Data received correctly");
        else
            $display("TEST FAILED ✗ Data mismatch");

        #1000;
        $finish;
    end

endmodule
