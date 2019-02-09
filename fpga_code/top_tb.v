`default_nettype none
`timescale 100 ns / 10 ns

module top_tb();

parameter DURATION = 20000;

reg clk = 0;
always #0.5 clk = ~clk;

// set frequency lower so we don't have to look at all those delay counters
top #(.CLK_FREQ(120_000)) the_top (
    .clk_12mhz(clk)
);

initial begin
    //-- File where to store the simulation
    $dumpfile("top_tb.vcd");
    $dumpvars(0, top_tb);

    #(DURATION) $display("END of the simulation");
    $finish;
end

endmodule
