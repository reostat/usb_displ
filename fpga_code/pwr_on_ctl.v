//--------------------------------------------------------------------
//-- SSD1331 Display Power On and Init Controller
//--------------------------------------------------------------------
`default_nettype none
`define BYTE_LEN(VAR) $bits(VAR)/8

module pwr_on_ctl #(
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
    output wire cs,
    output wire d_cn,
    output wire pmoden,
    output wire vccen,
    output wire resn,
    output wire done
);

// display commands
localparam EnableOledDriverCmd      = 16'hFD12;
localparam DisplayOffCmd            = 8'hAE;
localparam SetRemapCmd              = {8'hA0, DISPLAY_REMAP};
localparam SetStartLineCmd          = {8'hA1, START_LINE};
localparam SetOffsetCmd             = {8'hA2, DISPLAY_OFFSET};
localparam SetDisplayModeCmd        = DISPLAY_MODE;
localparam SetMultiplexRatioCmd     = {8'hA8, MULTIPLEX_RATIO};
localparam SetMasterConfCmd         = 16'hAD8E; // select external Vcc supply
localparam SetPhaseAdjustCmd        = {8'hB1, PHASE_ADJUST};
localparam SetPowerModeCmd          = {8'hB0, POWER_MODE};
localparam SetDisplayClockCmd       = {8'hB3, DISPLAY_CLOCK};
localparam SetPrechargeACmd         = {8'h8A, PRECHARGE_A};
localparam SetPrechargeBCmd         = {8'h8B, PRECHARGE_B};
localparam SetPrechargeCCmd         = {8'h8C, PRECHARGE_C};
localparam SetPrechargeLevelCmd     = {8'hBB, PRECHARGE_LEVEL};
localparam SetVcomhCmd              = {8'hBE, VCOMH_LEVEL};
localparam SetMasterCurrentCmd      = {8'h87, MASTER_CURRENT_ATT};
localparam SetContrastACmd          = {8'h81, CONTRAST_A};
localparam SetContrastBCmd          = {8'h82, CONTRAST_B};
localparam SetContrastCCmd          = {8'h83, CONTRAST_C};
localparam ClearScreenCmd           = 40'h2500005F3F;
localparam DisplayOnCmd             = 8'hAF;

localparam MaxCmdLen = $clog2($bits(ClearScreenCmd)+1); //use the longest command from the list above
reg [MaxCmdLen-1:0] cmd_bit_count; // 0 is reserved for done

// state delays
localparam PowerDelayCnt = (CLK_FREQ * 20) / 1000; // 20 ms after power on (Vdd, Vddio) till reset
localparam ResetLowDelayCnt = (CLK_FREQ * 3) / 1_000_000; // 3 us for reset low after Vdd
localparam ResetHighDelayCnt = ResetLowDelayCnt; // another 3 us for reset high before enabling Vcc
localparam VccEnDelayCnt = (CLK_FREQ * 20) / 1000; // 20 ms after Vcc enabling for Vcc to get stable
localparam StartupCompleteDelayCnt = (CLK_FREQ * 100) / 1000; // 100 ms after sending display on (AFh) for SEG/COM to turn on

localparam MaxDelayCnt = StartupCompleteDelayCnt;
reg [$clog2(MaxDelayCnt)-1:0] delay;

// power-on state machine (Gray code)
localparam VddPowerOn           = 5'b00000;
localparam Reset                = 5'b00001;
localparam ReleaseReset         = 5'b00011;
localparam EnableOledDriver     = 5'b00010;
localparam DisplayOff           = 5'b00110;
localparam SetRemap             = 5'b00111;
localparam SetStartLine         = 5'b00101;
localparam SetOffset            = 5'b00100;
localparam SetDisplayMode       = 5'b01100;
localparam SetMultiplexRatio    = 5'b01101;
localparam SetMasterConf        = 5'b01111;
localparam SetPhaseAdjust       = 5'b01110;
localparam SetPowerMode         = 5'b01010;
localparam SetDisplayClock      = 5'b01011;
localparam SetPrechargeA        = 5'b01001;
localparam SetPrechargeB        = 5'b01000;
localparam SetPrechargeC        = 5'b11000;
localparam SetPrechargeLevel    = 5'b11001;
localparam SetVcomh             = 5'b11011;
localparam SetMasterCurrent     = 5'b11010;
localparam SetContrastA         = 5'b11110;
localparam SetContrastB         = 5'b11111;
localparam SetContrastC         = 5'b11101;
localparam ClearScreen          = 5'b11100;
localparam VccEnable            = 5'b10100;
localparam DisplayOn            = 5'b10101;
localparam PowerOnDone          = 5'b10111;

localparam StateWidth = $bits(PowerOnDone); // can be any state variable since they all have the same length
(* fsm_encoding = "none" *) //yosys will try to recode FSM as "one-hot"; this attribute precludes that and saves some 30 cells
reg [StateWidth-1:0] state;
wire [StateWidth-1:0] next_state = fsm_next_state(state);

function [StateWidth-1:0] fsm_next_state (
    input [StateWidth-1:0] state
);
    case (state)
        VddPowerOn: fsm_next_state          = Reset;
        Reset: fsm_next_state               = ReleaseReset;
        ReleaseReset: fsm_next_state        = EnableOledDriver;
        EnableOledDriver: fsm_next_state    = DisplayOff;
        DisplayOff: fsm_next_state          = SetRemap;
        SetRemap: fsm_next_state            = SetStartLine;
        SetStartLine: fsm_next_state        = SetOffset;
        SetOffset: fsm_next_state           = SetDisplayMode;
        SetDisplayMode: fsm_next_state      = SetMultiplexRatio;
        SetMultiplexRatio: fsm_next_state   = SetMasterConf;
        SetMasterConf: fsm_next_state       = SetPhaseAdjust;
        SetPhaseAdjust: fsm_next_state      = SetPowerMode;
        SetPowerMode: fsm_next_state        = SetDisplayClock;
        SetDisplayClock: fsm_next_state     = SetPrechargeA;
        SetPrechargeA: fsm_next_state       = SetPrechargeB;
        SetPrechargeB: fsm_next_state       = SetPrechargeC;
        SetPrechargeC: fsm_next_state       = SetPrechargeLevel;
        SetPrechargeLevel: fsm_next_state   = SetVcomh;
        SetVcomh: fsm_next_state            = SetMasterCurrent;
        SetMasterCurrent: fsm_next_state    = SetContrastA;
        SetContrastA: fsm_next_state        = SetContrastB;
        SetContrastB: fsm_next_state        = SetContrastC;
        SetContrastC: fsm_next_state        = ClearScreen;
        ClearScreen: fsm_next_state         = VccEnable;
        VccEnable: fsm_next_state           = DisplayOn;
        DisplayOn: fsm_next_state           = PowerOnDone;
        PowerOnDone: fsm_next_state         = PowerOnDone;
    default:
        fsm_next_state = VddPowerOn;
    endcase
endfunction

assign done = state == PowerOnDone;
assign resn = state != Reset;
assign vccen = state == VccEnable || state == DisplayOn || state == PowerOnDone;
assign pmoden = !reset;
assign d_cn = reset; // we only send commands and no data thus always 0
assign cs = cmd_bit_count == 0; // hold cs low while there's data
// SSD1331 datasheet says max freq is 6.6Mhz yet 12MHz seem to work just fine, thus no freq divider
// mask clock with data availability.
assign sclk = clk & !cs;

always @* begin
    if (cmd_bit_count != 0) begin
        case (state)
            EnableOledDriver:       sdata = EnableOledDriverCmd[(cmd_bit_count-1)];
            DisplayOff:             sdata = DisplayOffCmd[(cmd_bit_count-1)];
            SetRemap:               sdata = SetRemapCmd[(cmd_bit_count-1)];
            SetStartLine:           sdata = SetStartLineCmd[(cmd_bit_count-1)];
            SetOffset:              sdata = SetOffsetCmd[(cmd_bit_count-1)];
            SetDisplayMode:         sdata = SetDisplayModeCmd[(cmd_bit_count-1)];
            SetMultiplexRatio:      sdata = SetMultiplexRatioCmd[(cmd_bit_count-1)];
            SetMasterConf:          sdata = SetMasterConfCmd[(cmd_bit_count-1)];
            SetPhaseAdjust:         sdata = SetPhaseAdjustCmd[(cmd_bit_count-1)];
            SetPowerMode:           sdata = SetPowerModeCmd[(cmd_bit_count-1)];
            SetDisplayClock:        sdata = SetDisplayClockCmd[(cmd_bit_count-1)];
            SetPrechargeA:          sdata = SetPrechargeACmd[(cmd_bit_count-1)];
            SetPrechargeB:          sdata = SetPrechargeBCmd[(cmd_bit_count-1)];
            SetPrechargeC:          sdata = SetPrechargeCCmd[(cmd_bit_count-1)];
            SetPrechargeLevel:      sdata = SetPrechargeLevelCmd[(cmd_bit_count-1)];
            SetVcomh:               sdata = SetVcomhCmd[(cmd_bit_count-1)];
            SetMasterCurrent:       sdata = SetMasterCurrentCmd[(cmd_bit_count-1)];
            SetContrastA:           sdata = SetContrastACmd[(cmd_bit_count-1)];
            SetContrastB:           sdata = SetContrastBCmd[(cmd_bit_count-1)];
            SetContrastC:           sdata = SetContrastCCmd[(cmd_bit_count-1)];
            ClearScreen:            sdata = ClearScreenCmd[(cmd_bit_count-1)];
            DisplayOn:              sdata = DisplayOnCmd[(cmd_bit_count-1)];
            default: sdata = 0;
        endcase
    end else begin 
        sdata = 0;
    end
end

always @(negedge clk) begin
    if (reset) begin
        cmd_bit_count <= 0;
        delay <= 0;
        state <= VddPowerOn;
    end else begin
        if (cmd_bit_count > 0) begin
            cmd_bit_count <= cmd_bit_count - 1;
        end else if (delay != 0 && cmd_bit_count == 0) begin
            delay <= delay - 1;
        end else  if (cmd_bit_count == 0 && delay == 0) begin
            state <= next_state;
            cmd_bit_count <= 0;
            delay <= 0;
            case (next_state)
                VddPowerOn:             delay <= PowerDelayCnt;
                Reset:                  delay <= ResetLowDelayCnt;
                ReleaseReset:           delay <= ResetHighDelayCnt;
                EnableOledDriver:       cmd_bit_count <= $bits(EnableOledDriverCmd);
                DisplayOff:             cmd_bit_count <= $bits(DisplayOffCmd);
                SetRemap:               cmd_bit_count <= $bits(SetRemapCmd);
                SetStartLine:           cmd_bit_count <= $bits(SetStartLineCmd);
                SetOffset:              cmd_bit_count <= $bits(SetOffsetCmd);
                SetDisplayMode:         cmd_bit_count <= $bits(SetDisplayModeCmd);
                SetMultiplexRatio:      cmd_bit_count <= $bits(SetMultiplexRatioCmd);
                SetMasterConf:          cmd_bit_count <= $bits(SetMasterConfCmd);
                SetPhaseAdjust:         cmd_bit_count <= $bits(SetPhaseAdjustCmd);
                SetPowerMode:           cmd_bit_count <= $bits(SetPowerModeCmd);
                SetDisplayClock:        cmd_bit_count <= $bits(SetDisplayClockCmd);
                SetPrechargeA:          cmd_bit_count <= $bits(SetPrechargeACmd);
                SetPrechargeB:          cmd_bit_count <= $bits(SetPrechargeBCmd);
                SetPrechargeC:          cmd_bit_count <= $bits(SetPrechargeCCmd);
                SetPrechargeLevel:      cmd_bit_count <= $bits(SetPrechargeLevelCmd);
                SetVcomh:               cmd_bit_count <= $bits(SetVcomhCmd);
                SetMasterCurrent:       cmd_bit_count <= $bits(SetMasterCurrentCmd);
                SetContrastA:           cmd_bit_count <= $bits(SetContrastACmd);
                SetContrastB:           cmd_bit_count <= $bits(SetContrastBCmd);
                SetContrastC:           cmd_bit_count <= $bits(SetContrastCCmd);
                ClearScreen:            cmd_bit_count <= $bits(ClearScreenCmd);
                VccEnable:              delay <= VccEnDelayCnt;
                DisplayOn: begin
                    cmd_bit_count <= $bits(DisplayOnCmd);
                    delay <= StartupCompleteDelayCnt;
                end
                default: begin
                    cmd_bit_count <= 0;
                    delay <= 0;
                end
            endcase
        end
    end
end

endmodule