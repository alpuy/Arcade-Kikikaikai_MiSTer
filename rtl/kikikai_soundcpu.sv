// Sound CPU and everything only it touches: program ROM, private RAM, the
// YM2203 window at C000-C001, and the vblank interrupt. Pulled out of
// kikikai_core.sv so testbenches instantiate this exact wiring instead of
// copying it (see kikikai_maincpu.sv for the same reasoning).
module kikikai_soundcpu (
    input  logic         clk_sys,
    input  logic         reset,        // already includes the main CPU's reset line for this CPU
    input  logic         cen,          // 6 MHz CPU enable
    input  logic         cen_3m,       // 3 MHz chip enable

    input  logic         ioctl_wr,
    input  logic         ioctl_download,
    input  logic [15:0]  ioctl_index,
    input  logic [26:0]  ioctl_addr,
    input  logic [7:0]   ioctl_dout,

    input  logic         vblank,
    input  logic [15:0]  dip_sw,       // DSW0 in 7:0, DSW1 in 15:8

    output logic [15:0]  snd_a,
    output logic         snd_m1_n,
    output logic         snd_mreq_n,
    output logic         snd_iorq_n,
    output logic         snd_rd_n,
    output logic         snd_wr_n,
    output logic [7:0]   snd_dout,
    input  logic [7:0]   snd_ram_din,  // shared mainram window, from the arbiter
    input  logic         snd_wait_n,

    output logic signed [15:0] snd
);

    reg [7:0] soundrom [0:15'h7fff];

    always @(posedge clk_sys)
        if (ioctl_wr && ioctl_download && ioctl_index == 8'd1 && ioctl_addr < 16'h8000)
            soundrom[ioctl_addr[14:0]] <= ioctl_dout;

    reg [7:0] snd_din;
    reg       snd_int_n = 1;

    tv80s #(.Mode(0)) u_snd_cpu (
        .m1_n(snd_m1_n), .mreq_n(snd_mreq_n), .iorq_n(snd_iorq_n),
        .rd_n(snd_rd_n), .wr_n(snd_wr_n), .rfsh_n(), .halt_n(), .busak_n(),
        .A(snd_a), .dout(snd_dout),
        .reset_n(~reset), .clk(clk_sys), .cen(cen), .wait_n(snd_wait_n),
        .int_n(snd_int_n), .nmi_n(1'b1), .busrq_n(1'b1), .di(snd_din)
    );

    wire [7:0] jt03_dout;
    wire       jt03_cs_n = ~(snd_a[15:1] == 15'h6000);   // C000-C001

    // A800-BFFF private RAM, indexed by snd_a[12:0] (0x800-0x1FFF), the low
    // 2K unused.
    wire [7:0] snd_ram_q;
    sdpram #(.AW(13), .DW(8)) u_snd_ram (
        .clk(clk_sys),
        .wr_en(~snd_mreq_n && ~snd_wr_n && snd_a >= 16'ha800 && snd_a <= 16'hbfff),
        .wr_addr(snd_a[12:0]), .wr_data(snd_dout),
        .rd_addr(snd_a[12:0]), .rd_data(snd_ram_q)
    );

    // Same dedicated-register-per-array shape as fixed_rom_q/banked_rom_q in
    // kikikai_maincpu, for the same reason.
    reg [7:0] soundrom_q;
    always @(posedge clk_sys) soundrom_q <= soundrom[snd_a[14:0]];

    // Latched for the same reason as main_din in kikikai_maincpu. Nothing
    // drives the sound CPU's data bus during an interrupt acknowledge, so its
    // IM0 vector reads 0xff (RST 38h), not whatever snd_din last held.
    always @(posedge clk_sys) begin
        if (~snd_m1_n && ~snd_iorq_n) begin
            snd_din <= 8'hff;
        end else if (~snd_mreq_n && ~snd_rd_n) begin
            if (snd_a <= 16'h7fff)      snd_din <= soundrom_q;
            else if (snd_a <= 16'ha7ff) snd_din <= snd_ram_din;
            else if (snd_a <= 16'hbfff) snd_din <= snd_ram_q;
            else if (~jt03_cs_n)        snd_din <= jt03_dout;
            // Nothing is mapped past c001; unmapped reads return 0x00.
            else                        snd_din <= 8'h00;
        end
    end

    reg snd_vblank_q;
    always @(posedge clk_sys) begin
        snd_vblank_q <= vblank;
        if (reset) snd_int_n <= 1;
        else begin
            if (vblank && !snd_vblank_q) snd_int_n <= 0;
            if (!snd_m1_n && !snd_iorq_n) snd_int_n <= 1;
        end
    end

    wire irq_n_unused;

    wire signed [15:0] fm_snd;
    wire        [7:0]  psg_a, psg_b, psg_c;

    // SSG channel level: 8-bit compressed jt49 output -> 0.3 x the YM2203 amplitude table
    function [12:0] ssg_lvl(input [7:0] lin);
        case (lin)
            8'd7: ssg_lvl = 13'd10; 8'd8: ssg_lvl = 13'd23; 8'd10: ssg_lvl = 13'd42;
            8'd11: ssg_lvl = 13'd53; 8'd12: ssg_lvl = 13'd67; 8'd14: ssg_lvl = 13'd79;
            8'd15: ssg_lvl = 13'd92; 8'd17: ssg_lvl = 13'd111; 8'd20: ssg_lvl = 13'd132;
            8'd22: ssg_lvl = 13'd153; 8'd25: ssg_lvl = 13'd176; 8'd28: ssg_lvl = 13'd210;
            8'd31: ssg_lvl = 13'd251; 8'd35: ssg_lvl = 13'd290; 8'd40: ssg_lvl = 13'd334;
            8'd45: ssg_lvl = 13'd400; 8'd50: ssg_lvl = 13'd479; 8'd56: ssg_lvl = 13'd556;
            8'd63: ssg_lvl = 13'd644; 8'd71: ssg_lvl = 13'd773; 8'd80: ssg_lvl = 13'd924;
            8'd90: ssg_lvl = 13'd1073; 8'd101: ssg_lvl = 13'd1241; 8'd113: ssg_lvl = 13'd1500;
            8'd127: ssg_lvl = 13'd1802; 8'd143: ssg_lvl = 13'd2107; 8'd160: ssg_lvl = 13'd2447;
            8'd180: ssg_lvl = 13'd2989; 8'd202: ssg_lvl = 13'd3593; 8'd227: ssg_lvl = 13'd4240;
            8'd255: ssg_lvl = 13'd4915;
            default: ssg_lvl = 13'd0;
        endcase
    endfunction

    jt03 u_jt03 (
        .rst(reset), .clk(clk_sys), .cen(cen_3m),
        .din(snd_dout), .addr(snd_a[0]), .cs_n(jt03_cs_n), .wr_n(snd_wr_n),
        .dout(jt03_dout), .irq_n(irq_n_unused),
        .IOA_in(dip_sw[7:0]), .IOB_in(dip_sw[15:8]),   // DSW0/SWA, DSW1/SWB
        .psg_A(psg_a), .psg_B(psg_b), .psg_C(psg_c),
        .fm_snd(fm_snd), .psg_snd(), .snd(), .snd_sample(), .debug_view()
    );

    // jt03's FM output is 2 bits down on the chip's scale
    wire signed [17:0] mix = ({{2{fm_snd[15]}}, fm_snd} << 2) + {5'd0, ssg_lvl(psg_a)}
                           + {5'd0, ssg_lvl(psg_b)} + {5'd0, ssg_lvl(psg_c)};
    assign snd = (mix > 18'sd32767) ? 16'sh7fff : (mix < -18'sd32768) ? 16'sh8000 : mix[15:0];

endmodule
