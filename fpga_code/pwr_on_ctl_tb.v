`default_nettype none
`timescale 100 ns / 10 ns

module pwr_on_ctl_tb();

parameter DURATION = 20000;

reg clk = 0;
reg rst = 1;
always #0.5 clk = ~clk;

// set frequency lower so we don't have to look at all those delay counters
pwr_on_ctl_mem #(.CLK_FREQ(120000)) pwr_on (
    .clk(clk),
    .reset(rst)
);

initial begin
    //-- File where to store the simulation
    $dumpfile("pwr_on_ctl_tb.vcd");
    $dumpvars(0, pwr_on_ctl_tb);
    #1 rst = 0;
    //#2 data_ready = 1;

    #(DURATION) $display("END of the simulation");
    $finish;
end

endmodule
