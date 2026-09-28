// Everything in Kikikaikai.sv except hps_io and the OSD/CONF_STR glue that
// talks to it -- pulled out so a testbench can drive the same ioctl_*/
// joystick_*/dip inputs hps_io normally produces, instead of hand-deriving
// this wiring a second time (see kikikai_maincpu.sv for the same reasoning).
module kikikai_core (
	input  logic        clk_sys,
	input  logic         reset,

	input  logic [31:0] joystick_0, joystick_1,

	input  logic         ioctl_download,
	input  logic [15:0] ioctl_index,
	input  logic         ioctl_wr,
	input  logic [26:0] ioctl_addr,
	input  logic [7:0]  ioctl_dout,

	input  logic         forced_scandoubler,
	inout  wire  [21:0] gamma_bus,

	input  logic         pause,          // suspends the main CPU only

	output logic         CLK_VIDEO,
	output logic         CE_PIXEL,
	output logic [7:0]  VGA_R, VGA_G, VGA_B,
	output logic         VGA_HS, VGA_VS, VGA_DE,
	output logic [1:0]  VGA_SL,

	output logic signed [15:0] AUDIO_L, AUDIO_R
);

	// 24 MHz matches the board's own master oscillator, so cen_6m/cen_3m
	// below are the same /4 and /8 the schematic actually uses.
	reg [1:0] clk_div = 0;
	always @(posedge clk_sys) clk_div <= clk_div + 2'd1;
	wire cen_6m = (clk_div == 2'd0);

	reg [2:0] clk_div8 = 0;
	always @(posedge clk_sys) clk_div8 <= clk_div8 + 3'd1;
	wire cen_3m = (clk_div8 == 3'd0);

	////////////////// ROM download //////////////////

	reg [3:0] prom_r     [0:255];
	reg [3:0] prom_g     [0:255];
	reg [3:0] prom_b     [0:255];

	wire gfx1_wr_en = ioctl_wr && ioctl_download && ioctl_index == 8'd3 && ioctl_addr < 19'h40000;

	// DSW0/DSW1 arrive on their own channel (mra_loader's arcade_sw_send),
	// index 254, not through status -- byte 0 is bits 7:0, byte 1 is 15:8.
	reg [15:0] dip_sw;
	always @(posedge clk_sys)
		if (ioctl_wr && ioctl_index == 8'd254 && ioctl_addr < 2)
			dip_sw[{ioctl_addr[0], 3'b000} +: 8] <= ioctl_dout;

	always @(posedge clk_sys) begin
		if (ioctl_wr && ioctl_download) begin
			case (ioctl_index)
				8'd4: case (ioctl_addr[9:8])
					2'd0: prom_r[ioctl_addr[7:0]] <= ioctl_dout[3:0];
					2'd1: prom_g[ioctl_addr[7:0]] <= ioctl_dout[3:0];
					2'd2: prom_b[ioctl_addr[7:0]] <= ioctl_dout[3:0];
					default: ;
				endcase
				default: ;
			endcase
		end
	end

	////////////////// main CPU, memory map //////////////////

	wire [15:0] main_a;
	wire        main_m1_n, main_mreq_n, main_iorq_n, main_rd_n, main_wr_n;
	wire [7:0]  main_dout;
	wire        main_wait_n;
	wire [2:0]  reset_lines;

	reg [7:0] IN3 = 8'hff;   // service1/tilt/start1/start2, active low
	reg [7:0] IN0 = 8'hff;   // coin1/coin2 raw, active low -- inverted for the MCU below

	wire snd_reset = reset || ~reset_lines[2];
	wire mcu_reset = reset || ~reset_lines[1];

	kikikai_maincpu u_maincpu (
		.clk_sys(clk_sys), .reset(reset), .cen(cen_6m & ~pause),
		.ioctl_wr(ioctl_wr), .ioctl_download(ioctl_download),
		.ioctl_index(ioctl_index), .ioctl_addr(ioctl_addr), .ioctl_dout(ioctl_dout),
		.main_a(main_a), .main_m1_n(main_m1_n), .main_mreq_n(main_mreq_n),
		.main_iorq_n(main_iorq_n), .main_rd_n(main_rd_n), .main_wr_n(main_wr_n),
		.main_dout(main_dout), .main_ram_din(main_ram_din), .main_wait_n(main_wait_n),
		.IN3(IN3), .vblank(vblank),
		.hs_addr(hs_addr), .hs_wdata(hs_wdata), .hs_we(hs_we),
		.sharedram_hs_rdata(sharedram_hs_rdata),
		.reset_lines(reset_lines)
	);

	////////////////// sound CPU, memory map //////////////////

	wire [15:0] snd_a;
	wire        snd_m1_n, snd_mreq_n, snd_iorq_n, snd_rd_n, snd_wr_n;
	wire [7:0]  snd_dout;
	wire        snd_wait_n;
	wire [7:0]  main_ram_din, snd_ram_din;

	kikikai_soundcpu u_soundcpu (
		.clk_sys(clk_sys), .reset(snd_reset), .cen(cen_6m), .cen_3m(cen_3m),
		.ioctl_wr(ioctl_wr), .ioctl_download(ioctl_download),
		.ioctl_index(ioctl_index), .ioctl_addr(ioctl_addr), .ioctl_dout(ioctl_dout),
		.vblank(vblank), .dip_sw(dip_sw),
		.snd_a(snd_a), .snd_m1_n(snd_m1_n), .snd_mreq_n(snd_mreq_n),
		.snd_iorq_n(snd_iorq_n), .snd_rd_n(snd_rd_n), .snd_wr_n(snd_wr_n),
		.snd_dout(snd_dout), .snd_ram_din(snd_ram_din), .snd_wait_n(snd_wait_n),
		.snd(AUDIO_L)
	);

	assign AUDIO_R = AUDIO_L;

	////////////////// shared-RAM arbiter (main C000-E7FF / snd 8000-A7FF) //////////////////

	wire [13:0] eng_mem_a_addr, eng_mem_b_addr;
	wire [7:0]  eng_mem_a_dout, eng_mem_b_dout;

	shared_ram_arbiter u_arb (
		.clk(clk_sys), .cen(cen_6m),
		.main_a(main_a), .main_mreq_n(main_mreq_n), .main_rd_n(main_rd_n), .main_wr_n(main_wr_n),
		.main_dout(main_dout), .main_din(main_ram_din), .main_sel(), .main_wait_n(main_wait_n),
		.snd_a(snd_a), .snd_mreq_n(snd_mreq_n), .snd_rd_n(snd_rd_n), .snd_wr_n(snd_wr_n),
		.snd_dout(snd_dout), .snd_din(snd_ram_din), .snd_sel(), .snd_wait_n(snd_wait_n),
		.eng_a_addr(eng_mem_a_addr), .eng_a_dout(eng_mem_a_dout),
		.eng_b_addr(eng_mem_b_addr), .eng_b_dout(eng_mem_b_dout)
	);

	////////////////// MCU + handshake //////////////////

	wire [7:0]  mcu_p1_in = ~IN0;   // in_p1_cb().set_ioport("IN0").invert()
	wire [7:0]  mcu_p2_out, mcu_p3_out, mcu_p4_out;
	wire [7:0]  mcu_p3_in;
	wire        mcu_is3;
	wire [15:0] mcu_rom_a;

	// The core only samples data_in on cen_3m cycles, 8 clk_sys apart, so the
	// registered read has settled well before it's used.
	wire [7:0] mcu_rom_q;
	sdpram #(.AW(12), .DW(8)) u_mcu_rom (
		.clk(clk_sys),
		.wr_en(ioctl_wr && ioctl_download && ioctl_index == 8'd2 && ioctl_addr < 13'h1000),
		.wr_addr(ioctl_addr[11:0]), .wr_data(ioctl_dout),
		.rd_addr(mcu_rom_a[11:0]), .rd_data(mcu_rom_q)
	);

	// clk_sys with a 3 MHz enable, same as both Z80s: one clock domain, so
	// every MCU<->main path is timed as an ordinary clk_sys path.
	kikikai_mcu u_mcu (
		.clk(clk_sys), .cen(cen_3m), .reset(mcu_reset), .irq(mcu_irq),
		.p1_in(mcu_p1_in), .p1_out(),
		.p2_out(mcu_p2_out),
		.p3_in(mcu_p3_in), .p3_out(mcu_p3_out),
		.p4_out(mcu_p4_out),
		.is3(mcu_is3),
		.rom_addr(mcu_rom_a), .rom_data(mcu_rom_q)
	);

	// M6801_IRQ1_LINE: a level for the whole vblank. The core's IRQ is level
	// sensitive and only looks at it on an instruction boundary, so a one-cycle
	// pulse is almost always missed and the firmware's interrupt never runs.
	wire mcu_irq = vblank;

	wire [7:0] hs_addr, hs_wdata;
	wire       hs_we, hs_inputs_sel;
	wire [7:0] sharedram_hs_rdata;

	// IN1/IN2 bit order (kikikai.cpp INPUT_PORTS): up,down,left,right,ofuda,oharai.
	// joystick_0/1 fixed bits: 0=right,1=left,2=down,3=up,4=J1 button 1 (Ofuda),
	// 5=J1 button 2 (Oharai-bo).
	wire [7:0] in1 = ~{2'b00, joystick_0[5], joystick_0[4], joystick_0[0], joystick_0[1], joystick_0[2], joystick_0[3]};
	wire [7:0] in2 = ~{2'b00, joystick_1[5], joystick_1[4], joystick_1[0], joystick_1[1], joystick_1[2], joystick_1[3]};

	kikikai_handshake u_hs (
		.clk(clk_sys), .reset(mcu_reset),
		.p2(mcu_p2_out), .p3_out(mcu_p3_out), .p4(mcu_p4_out),
		.p3_in(mcu_p3_in), .is3(mcu_is3),
		.sharedram_addr(hs_addr), .sharedram_rdata(sharedram_hs_rdata),
		.sharedram_wdata(hs_wdata), .sharedram_we(hs_we),
		.inputs_sel(hs_inputs_sel), .inputs_data(hs_inputs_sel ? in2 : in1)
	);

	// IN0: coin1,coin2. IN3: service1,-,tilt,start1,start2,-,-,-. CONF_STR's J1
	// list puts start1/start2/coin/coin2/service at joystick_0[6:10]; no cabinet
	// input for tilt, tied permanently inactive.
	always @(posedge clk_sys) begin
		IN0 <= ~{6'b0, joystick_0[9], joystick_0[8]};
		IN3 <= ~{3'b0, joystick_0[7], joystick_0[6], 1'b0, 1'b0, joystick_0[10]};
	end

	////////////////// video //////////////////

	wire [8:0] hpos, vpos;
	wire       hblank, vblank, hsync, vsync;

	video_timing u_timing (
		.clk(clk_sys), .ce_pix(cen_6m), .reset(reset),
		.hpos(hpos), .vpos(vpos), .hblank(hblank), .vblank(vblank), .hsync(hsync), .vsync(vsync)
	);

	wire [8:0] next_vpos = (vpos == 9'd263) ? 9'd0 : vpos + 9'd1;
	reg        hpos0_q;
	wire       new_line = (hpos == 9'd0) && !hpos0_q;

	// One sprite_engine, computing the next line into its own line buffer while
	// the current line displays out of one of two captured copies -- two live
	// engines would each need their own 2 gfx1 read ports, 4 total into one
	// array, over this device's 2-port-per-block limit.
	reg        eng_start;
	reg  [7:0] compute_line;
	reg        buf_toggle;

	always @(posedge clk_sys) begin
		hpos0_q  <= (hpos == 9'd0);
		eng_start <= 0;
		if (new_line) begin
			compute_line <= next_vpos[7:0];
			eng_start    <= 1;
			buf_toggle   <= ~buf_toggle;
		end
	end

	wire [7:0] eng_pixel [0:255];
	wire       eng_painted [0:255];
	wire       eng_done;

	wire [17:0] gfx_a_addr, gfx_b_addr;
	wire [7:0]  gfx_a_dout, gfx_b_dout;
	gfx1_rom u_gfx1 (
		.clk(clk_sys),
		.wr_data(ioctl_dout), .wr_addr(ioctl_addr[17:0]), .wr_en(gfx1_wr_en),
		.a_addr(gfx_a_addr), .a_dout(gfx_a_dout),
		.b_addr(gfx_b_addr), .b_dout(gfx_b_dout)
	);

	sprite_engine u_sprite (
		.clk(clk_sys), .reset(reset), .start(eng_start), .line(compute_line), .done(eng_done),
		.mem_a_addr(eng_mem_a_addr), .mem_a_dout(eng_mem_a_dout),
		.mem_b_addr(eng_mem_b_addr), .mem_b_dout(eng_mem_b_dout),
		.gfx_a_addr(gfx_a_addr), .gfx_a_dout(gfx_a_dout),
		.gfx_b_addr(gfx_b_addr), .gfx_b_dout(gfx_b_dout),
		.lb_pixel(eng_pixel), .lb_painted(eng_painted)
	);

	reg [7:0] buf0_pixel [0:255], buf1_pixel [0:255];
	reg       buf0_painted [0:255], buf1_painted [0:255];

	always @(posedge clk_sys) if (eng_done) begin
		if (buf_toggle) begin
			buf1_pixel   <= eng_pixel;
			buf1_painted <= eng_painted;
		end else begin
			buf0_pixel   <= eng_pixel;
			buf0_painted <= eng_painted;
		end
	end

	wire [7:0] disp_pixel   = buf_toggle ? buf0_pixel[hpos[7:0]]   : buf1_pixel[hpos[7:0]];
	wire       disp_painted = buf_toggle ? buf0_painted[hpos[7:0]] : buf1_painted[hpos[7:0]];

	// One registered read per PROM, so each maps onto block RAM. disp_pixel
	// changes on cen_6m and arcade_video samples 4 clk_sys later, so the one
	// cycle this adds stays inside the pixel; disp_painted is delayed with it.
	reg [3:0] prom_r_q, prom_g_q, prom_b_q;
	reg       disp_painted_q;
	always @(posedge clk_sys) begin
		prom_r_q       <= prom_r[disp_pixel];
		prom_g_q       <= prom_g[disp_pixel];
		prom_b_q       <= prom_b[disp_pixel];
		disp_painted_q <= disp_painted;
	end

	wire [7:0] pal_r, pal_g, pal_b;
	palette_dac u_pal_r (.nibble(prom_r_q), .level(pal_r));
	palette_dac u_pal_g (.nibble(prom_g_q), .level(pal_g));
	palette_dac u_pal_b (.nibble(prom_b_q), .level(pal_b));

	wire [23:0] rgb = disp_painted_q ? {pal_r, pal_g, pal_b} : 24'd0;

	// gamma_corr's counter (blocking+nonblocking on the same variable) has
	// no simulator model; GAMMA doesn't affect anything upstream of it, so
	// simulation turns it off instead.
`ifdef SIMULATION
	arcade_video #(256, 24, 0) u_video (
`else
	arcade_video #(256, 24) u_video (
`endif
		.clk_video(clk_sys), .ce_pix(cen_6m),
		.RGB_in(rgb), .HBlank(hblank), .VBlank(vblank), .HSync(hsync), .VSync(vsync),
		.CLK_VIDEO(CLK_VIDEO), .CE_PIXEL(CE_PIXEL),
		.VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B), .VGA_HS(VGA_HS), .VGA_VS(VGA_VS), .VGA_DE(VGA_DE), .VGA_SL(VGA_SL),
		.fx(3'd0), .forced_scandoubler(forced_scandoubler), .gamma_bus(gamma_bus)
	);

endmodule
