//----------------------------------------------------------------------
//-- SSD1331 Display Power On and Init Controller
//--
//-- Serves the same purpose as pwr_on_ctl but with init FSM implemented
//-- as a simple instructions set
//----------------------------------------------------------------------
`default_nettype none

module pwr_on_ctl_mem #(
    parameter CLK_FREQ = 12_000_000,
    parameter DISPLAY_REMAP = 8'h72,//8'h72, // display remap and data format for A0h cmd
    parameter START_LINE = 8'h00, // display start line for A1h cmd
    parameter DISPLAY_OFFSET = 8'h00, // display offset for A2h cmd
    parameter DISPLAY_MODE = 8'hA4, // display mode: A4h - normal, A5h - all on, A6h - all off, A7h - inverse
    parameter MULTIPLEX_RATIO = 8'h3F, // for A8h cmd
    parameter POWER_MODE = 8'h0B, // power mode (B0h cmd): 0Bh - disable power save, 1Ah - enable power save (RESET)
    parameter PHASE_ADJUST = 8'h31, // phase 1 and phase 2 pixel (dis)charge length for B1h cmd
    parameter DISPLAY_CLOCK = 8'hF0, // B3h cmd, 7:4 = Oscillator Frequency, 3:0 = CLK Div Ratio (A[3:0]+1 = 1..16)
    parameter PRECHARGE_A = 8'h64, // second precharge speeds for channels A-B-C, 8Ah-8Ch commands
    parameter PRECHARGE_B = 8'h78,
    parameter PRECHARGE_C = 8'h64,
    parameter PRECHARGE_LEVEL = 8'h3A, // BBh cmd, Vp precharge level in ref to Vcc
    parameter VCOMH_LEVEL = 8'h3E, // BEh cmd, COM deselect voltage level (Vcomh)
    parameter MASTER_CURRENT_ATT = 8'h06, // 87h cmd, master current attenuation factor
    parameter CONTRAST_A = 8'h91, //contrast for channels A-B-C, 81h-83h commands
    parameter CONTRAST_B = 8'h50,
    parameter CONTRAST_C = 8'h7D
)(
    input wire clk,
    input wire reset,
    output reg sdata,
    output wire sclk,
    output reg cs,
    output wire d_cn,
    output wire pmoden,
    output wire vccen,
    output wire resn,
    output wire done
);

assign pmoden = !reset; // enable pmod power right after reset
assign d_cn = reset; // we only send commands and no data thus always 0

// command word is 12 bit wide and has the following fields:
// +--+--+--+--+----+
// |11|10| 9| 8|7..0| - bit number
// +--+--+--+--+----+
// | S| V| R| F|DATA| - field (see below)
// +--+--+--+--+----+
//
// Fields:
//  - (S)TOP:           Last command marker
//  - (V)CCEN:          Enable Vcc
//  - (R)ESN:           Pull resn low or high
//  - CMD/PAUSE (F)LAG: 1 if DATA bits represent command to be sent,
//                      0 if delay count pointer (see "Delays" below)
//  - DATA:             Byte with command (part of command for commands longer than 1 byte)
//                      or delay count pointer (see "Delays" below)

reg[11:0] command; // current command
reg[11:0] program[0:50]; // program storage
reg[5:0]  cmd_ptr; // current command pointer
reg[2:0]  shift_cnt; // shift counter for command data

assign done = command[11]; // done on STOP
assign vccen = command[10];
assign resn = command[9];
wire is_delay = ~command[8];
wire is_command = command[8];

// ------------------------------------------- Delays -------------------------------------------
// We need the following delays:
//  - 20 ms after Vdd pwr on (pmoden = 1) before pulling resn low
//  - 3 us to hold resn low
//  - another 3 us for resn high before enabling Vcc
//  - ... all other init commands go here, then enable Vcc
//  - 20 ms after Vcc enable before sending Display ON to let Vcc stabilize
//  - and finally, 100 ms after Display ON
//
// Naive approach would be to store delay counter directly in the command's byte payload
// and then combine pause commands as needed to get longer delays. However, with this approach to
// get to 20+100+20 = 140 ms combined delay at 12 MHz (12,000,000(1/s)*0.14(s) = 1,680,000 cycles)
// one would need 1,680,000/2^8 = 6,563 pause commands, which is equivalent to
// 6,563*12 = 78,756 bits of memory. This is way more than 64K BRAM bits
// available in Lattice HX1K device :(
//
// Alternative approach is to store counters for 3 us and 20 ms delays in LUTs and pass pointer to
// required counter in command's body. 100 ms delay is 5x20ms delay commands one after another

localparam Delay3usCnt  = (CLK_FREQ *  3) / 1_000_000;
localparam Delay3us     = 8'h01;
localparam Delay20msCnt = (CLK_FREQ * 20) / 1_000;
localparam Delay20ms    = 8'h02;
localparam DelayNone    = 8'h00;
reg [$clog2(Delay20msCnt)-1:0] delay;

function [$clog2(Delay20msCnt)-1:0] get_delay(
    input [11:0] cmd
);
    case (cmd[1:0])
        DelayNone: get_delay = 0;
        Delay3us:  get_delay = Delay3usCnt;
        Delay20ms: get_delay = Delay20msCnt;
        default:   get_delay = 0;
    endcase
endfunction

// init program
initial begin
    program[00] <= {4'b0010, Delay20ms}; // right after power on hold resn high for 20ms
    program[01] <= {4'b0000, Delay3us};  // then pull resn low for 3us
    program[02] <= {4'b0010, Delay3us};  // then high again for another 3us before sending commands (and keep high)
    
    program[03] <= {4'b0011, 8'hFD};     // enable oled driver, 0xFD12
    program[04] <= {4'b0011, 8'h12};
    program[05] <= {4'b0011, 8'hAE};     // display off
    program[06] <= {4'b0011, 8'hA0};     // set display remap
    program[07] <= {4'b0011, DISPLAY_REMAP};
    program[08] <= {4'b0011, 8'hA1};     // set display start line
    program[09] <= {4'b0011, START_LINE};
    program[10] <= {4'b0011, 8'hA2};     // set display offset
    program[11] <= {4'b0011, DISPLAY_OFFSET};
    program[12] <= {4'b0011, DISPLAY_MODE}; // set display mode
    program[13] <= {4'b0011, 8'hA8};     // set multiplex ratio
    program[14] <= {4'b0011, MULTIPLEX_RATIO};
    program[15] <= {4'b0011, 8'hAD};     // master config - ...
    program[16] <= {4'b0011, 8'h8E};     // ... - select external Vcc supply
    program[17] <= {4'b0011, 8'hB1};     // phase adjust cmd
    program[18] <= {4'b0011, PHASE_ADJUST};
    program[19] <= {4'b0011, 8'hB0};     // power mode cmd
    program[20] <= {4'b0011, POWER_MODE};
    program[21] <= {4'b0011, 8'hB3};     // display clock cmd
    program[22] <= {4'b0011, DISPLAY_CLOCK};
    program[23] <= {4'b0011, 8'h8A};     // set precharge for A, B & C channels
    program[24] <= {4'b0011, PRECHARGE_A};
    program[25] <= {4'b0011, 8'h8B};
    program[26] <= {4'b0011, PRECHARGE_B};
    program[27] <= {4'b0011, 8'h8C};
    program[28] <= {4'b0011, PRECHARGE_C};
    program[29] <= {4'b0011, 8'hBE};     // vcomm level cmd
    program[30] <= {4'b0011, VCOMH_LEVEL};
    program[31] <= {4'b0011, 8'h87};     // master current attenuation
    program[32] <= {4'b0011, MASTER_CURRENT_ATT};
    program[33] <= {4'b0011, 8'h81};     // contrast levels for A, B & C channels
    program[34] <= {4'b0011, CONTRAST_A};
    program[35] <= {4'b0011, 8'h82};
    program[36] <= {4'b0011, CONTRAST_B};
    program[37] <= {4'b0011, 8'h83};
    program[38] <= {4'b0011, CONTRAST_C};
    program[39] <= {4'b0011, 8'h25};     // clear screen cmd (5 bytes)
    program[40] <= {4'b0011, 8'h00};     // x1 = 0
    program[41] <= {4'b0011, 8'h00};     // y1 = 0
    program[42] <= {4'b0011, 8'h5F};     // x1 = 96
    program[43] <= {4'b0011, 8'h3F};     // x1 = 64
    program[44] <= {4'b0110, Delay20ms}; // Vcc enable and wait for 20ms
    program[45] <= {4'b0111, 8'hAF};     // display on cmd
    program[46] <= {4'b0110, Delay20ms}; // wait for 100ms for SEG/COM to get up (5x20ms delays)
    program[47] <= {4'b0110, Delay20ms};
    program[48] <= {4'b0110, Delay20ms};
    program[49] <= {4'b0110, Delay20ms};
    program[50] <= {4'b1110, Delay20ms}; // and we're done!
end

// SSD1331 datasheet says max freq is 6.6MHz yet 12MHz seem to work just fine, thus no freq divider.
// Also, mask clock with data availability.
assign sclk = clk & !cs;

// read current command
always @(posedge clk) begin
    if (reset) begin
        command <= {4'b0010, 8'h00};
        cmd_ptr <= 0;
    end else if (shift_cnt == 0 && delay == 0 && !done) begin
         // read next command if previous command shifted out and delay counted down
         command <= program[cmd_ptr];
         cmd_ptr <= cmd_ptr + 1;
    end
end

// command shifter
always @(negedge clk) begin
    if (reset) begin
        shift_cnt <= 0;
        cs <= 1;
    end else begin
        if (is_command && shift_cnt == 0) begin
            cs <= 0;
            sdata <= command[7];
            shift_cnt <= 7;
        end else if (shift_cnt > 0) begin
            sdata = command[shift_cnt-1];
            shift_cnt <= shift_cnt - 1;
        end else
            cs <= 1;
    end
end

// delay counter
always @(negedge clk) begin
    if (reset) delay <= 0;
    else begin
        if (is_delay && delay == 0)
            delay <= get_delay(command);
        else if (delay >0)
            delay <= delay - 1;
    end
end

endmodule