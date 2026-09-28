// SPDX-License-Identifier: GPL-3.0-or-later

module emu
(
	`include "sys/emu_ports.vh"
);

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;
// DDRAM is driven by screen_rotate_two (HDMI rotation), below.

assign VGA_F1 = 0;
assign VGA_SCALER  = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;
assign FB_FORCE_BLANK = 0;

assign AUDIO_S = 1;
// Mono, None, 25%, 50% -> AUDIO_MIX 3, 0, 1, 2 (mono first, so status==0 default is mono)
assign AUDIO_MIX = (status[124:123] == 2'd0) ? 2'd3 : status[124:123] - 2'd1;

assign LED_DISK = 0;
assign LED_POWER = 0;
assign LED_USER = ioctl_download;
assign BUTTONS = 0;

// The cabinet is vertical (mounted CW); Auto follows that without reading
// a mod byte, since this core has only one game.
localparam [1:0] game_rot = 2'd1;   // 0 none, 1 CW, 2 CCW

wire [1:0] rot_sel    = status[64:63];
wire       rotate_en  = (rot_sel == 2'd0) ? (game_rot != 2'd0) : (rot_sel != 2'd1);
wire       rotate_ccw = (rot_sel == 2'd0) ? (game_rot == 2'd2) : (rot_sel == 2'd3);

wire [1:0] ar = status[122:121];
wire [11:0] base_arx = rotate_en ? 12'd3 : 12'd4;
wire [11:0] base_ary = rotate_en ? 12'd4 : 12'd3;
wire [11:0] osd_arx = (!ar) ? base_arx : (ar - 1'd1);
wire [11:0] osd_ary = (!ar) ? base_ary : 12'd0;

wire core_vga_de;
video_freak video_freak
(
	.CLK_VIDEO(CLK_VIDEO), .CE_PIXEL(CE_PIXEL), .VGA_VS(VGA_VS),
	.HDMI_WIDTH(HDMI_WIDTH), .HDMI_HEIGHT(HDMI_HEIGHT),
	.VGA_DE(VGA_DE), .VIDEO_ARX(VIDEO_ARX), .VIDEO_ARY(VIDEO_ARY),
	.VGA_DE_IN(core_vga_de),
	.ARX(osd_arx), .ARY(osd_ary),
	// 224 visible lines has no smaller clean cut; crop only trims the
	// native VTOTAL padding around them.
	.CROP_SIZE(status[69] ? 12'd224 : 12'd0), .CROP_OFF(status[75:71]),
	.SCALE(status[68:66])
);

`include "build_id.v"
localparam CONF_STR = {
	"Kikikaikai;;",
	"-;",
	"H5O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"H5O[64:63],Orientation,Auto,Off,CW,CCW;",
	"H5O[68:66],Scale,Normal,V-Integer,Narrower HV-Integer,Wider HV-Integer,HV-Integer;",
	"H5O[69],Crop,Off,224 lines;",
	"H5O[75:71],Crop offset,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
	"O[124:123],Audio mix,Mono,None,25%,50%;",
	"-;",
	"R0,Reset;",
	"J1,Ofuda,Oharai-bo,Start 1P,Start 2P,Coin,Coin 2,Service,Pause;",
	"V,v",`BUILD_DATE
};

wire [127:0] status;
wire [31:0]  joystick_0, joystick_1;
wire [10:0]  ps2_key;
wire         forced_scandoubler;
wire [21:0]  gamma_bus;
wire         direct_video;

wire         ioctl_download;
wire [15:0]  ioctl_index;
wire         ioctl_wr;
wire [26:0]  ioctl_addr;
wire [7:0]   ioctl_dout;
wire         ioctl_wait = 0;

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(gamma_bus),

	.forced_scandoubler(forced_scandoubler),
	.direct_video(direct_video),

	.joystick_0(joystick_0),
	.joystick_1(joystick_1),

	.buttons(),
	.status(status),
	.status_menumask({10'd0, direct_video, 5'd0}),   // H5: HDMI-only options hidden under direct video

	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wait(ioctl_wait),

	.ps2_key(ps2_key)
);

wire clk_sys, pll_locked;
pll pll (
	.refclk(CLK_50M),
	.rst(1'b0),
	.outclk_0(clk_sys),
	.locked(pll_locked)
);

wire reset = RESET || status[0] || ioctl_download || !pll_locked;

// Fake pause (the board has none): J1's Pause button toggles a latch that
// suspends the main CPU only -- video and sound keep running.
wire pause_btn = joystick_0[11] | joystick_1[11];
reg  pause_toggle = 0;
reg  pause_btn_q;
always @(posedge clk_sys) begin
	pause_btn_q <= pause_btn;
	if (pause_btn & ~pause_btn_q) pause_toggle <= ~pause_toggle;
end

kikikai_core u_core (
	.clk_sys(clk_sys), .reset(reset),
	.joystick_0(joystick_0), .joystick_1(joystick_1),
	.ioctl_download(ioctl_download), .ioctl_index(ioctl_index), .ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr), .ioctl_dout(ioctl_dout),
	.forced_scandoubler(forced_scandoubler), .gamma_bus(gamma_bus),
	.pause(pause_toggle),
	.CLK_VIDEO(CLK_VIDEO), .CE_PIXEL(CE_PIXEL),
	.VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B),
	.VGA_HS(VGA_HS), .VGA_VS(VGA_VS), .VGA_DE(core_vga_de), .VGA_SL(VGA_SL),
	.AUDIO_L(AUDIO_L), .AUDIO_R(AUDIO_R)
);

// HDMI rotation: a tap, not a filter. Analog output keeps the native
// raster; a rotated copy goes to DDR3 and out through the framework's
// framebuffer. No other DDR3 client exists here, so it owns DDRAM_* alone.
screen_rotate_two screen_rotate_two
(
	.CLK_VIDEO     (CLK_VIDEO),
	.CE_PIXEL      (CE_PIXEL),

	.VGA_R         (VGA_R),
	.VGA_G         (VGA_G),
	.VGA_B         (VGA_B),
	.VGA_HS        (VGA_HS),
	.VGA_VS        (VGA_VS),
	.VGA_DE        (VGA_DE),

	.rotate_ccw    (rotate_ccw),
	.no_rotate     (~rotate_en),
	.flip          (1'b0),
	.two_screen    (1'b0),
	.video_rotated (),

	.FB_EN         (FB_EN),
	.FB_FORMAT     (FB_FORMAT),
	.FB_WIDTH      (FB_WIDTH),
	.FB_HEIGHT     (FB_HEIGHT),
	.FB_BASE       (FB_BASE),
	.FB_STRIDE     (FB_STRIDE),
	.FB_VBL        (FB_VBL),
	.FB_LL         (FB_LL),

	.DDRAM_CLK     (DDRAM_CLK),
	.DDRAM_BUSY    (DDRAM_BUSY),
	.DDRAM_BURSTCNT(DDRAM_BURSTCNT),
	.DDRAM_ADDR    (DDRAM_ADDR),
	.DDRAM_DIN     (DDRAM_DIN),
	.DDRAM_BE      (DDRAM_BE),
	.DDRAM_WE      (DDRAM_WE),
	.DDRAM_RD      (DDRAM_RD)
);

endmodule
