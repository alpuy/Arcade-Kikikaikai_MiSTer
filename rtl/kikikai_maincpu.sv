// Main CPU and everything only it touches: fixed/banked program ROM,
// plainram, sharedram's main-side port, the bank/reset-line register, and
// the vblank interrupt. Pulled out of Kikikaikai.sv so this exact memory
// map can be instantiated a second time, in simulation, without
// hand-deriving it again.
module kikikai_maincpu (
    input  logic        clk_sys,
    input  logic         reset,
    input  logic         cen,

    input  logic         ioctl_wr,
    input  logic         ioctl_download,
    input  logic [15:0] ioctl_index,
    input  logic [26:0] ioctl_addr,
    input  logic [7:0]  ioctl_dout,

    output logic [15:0] main_a,
    output logic         main_m1_n,
    output logic         main_mreq_n,
    output logic         main_iorq_n,
    output logic         main_rd_n,
    output logic         main_wr_n,
    output logic [7:0]  main_dout,
    input  logic [7:0]  main_ram_din,
    input  logic         main_wait_n,

    input  logic [7:0]  IN3,
    input  logic         vblank,

    input  logic [7:0]  hs_addr,
    input  logic [7:0]  hs_wdata,
    input  logic         hs_we,
    output logic [7:0]  sharedram_hs_rdata,

    output logic [2:0]  reset_lines
);

    reg [7:0] fixed_rom  [0:16'h7fff];
    reg [7:0] banked_rom [0:17'h17fff];

    always @(posedge clk_sys) begin
        if (ioctl_wr && ioctl_download && ioctl_index == 8'd0 && ioctl_addr < 18'h28000) begin
            if (ioctl_addr < 16'h8000) fixed_rom[ioctl_addr[14:0]] <= ioctl_dout;
            else                       banked_rom[ioctl_addr[17:0] - 18'h8000] <= ioctl_dout;
        end
    end

    reg  [7:0] main_din;
    reg        main_int_n = 1;

    tv80s #(.Mode(0)) u_main_cpu (
        .m1_n(main_m1_n), .mreq_n(main_mreq_n), .iorq_n(main_iorq_n),
        .rd_n(main_rd_n), .wr_n(main_wr_n), .rfsh_n(), .halt_n(), .busak_n(),
        .A(main_a), .dout(main_dout),
        .reset_n(~reset), .clk(clk_sys), .cen(cen), .wait_n(main_wait_n),
        .int_n(main_int_n), .nmi_n(1'b1), .busrq_n(1'b1), .di(main_din)
    );

    reg [2:0] rombank = 0;
    reg       charbank = 0;   // tile code bit 12 -- not yet wired into sprite_engine's code
    reg [2:0] reset_lines_q = 3'b111;   // bit2 snd, bit1 mcu, active per main_f008_w
    assign reset_lines = reset_lines_q;

    wire [16:0] bank_off = {rombank, 14'd0};

    // E900-EFFF indexed by main_a[10:0] directly (0x100-0x7FF), the low 256
    // bytes unused.
    wire [7:0] plainram_q;
    sdpram #(.AW(11), .DW(8)) u_plainram (
        .clk(clk_sys),
        .wr_en(~main_mreq_n && ~main_wr_n && main_a >= 16'he900 && main_a <= 16'hefff),
        .wr_addr(main_a[10:0]), .wr_data(main_dout),
        .rd_addr(main_a[10:0]), .rd_data(plainram_q)
    );

    // One registered read per array: block RAM has no asynchronous read, and
    // inference needs each array's read in its own output register. cen
    // holds main_a for 4 clk_sys cycles, so the added cycle is invisible to tv80.
    reg [7:0] fixed_rom_q, banked_rom_q;
    always @(posedge clk_sys) begin
        fixed_rom_q  <= fixed_rom[main_a[14:0]];
        banked_rom_q <= banked_rom[bank_off + (main_a - 16'h8000)];
    end

    // Port A serves main's reads, address 0 standing in for the interrupt-ack
    // vector read (never the same cycle as a normal read); port B is the
    // handshake's.
    wire [7:0] sharedram_a_addr = (~main_m1_n && ~main_iorq_n) ? 8'd0 : main_a[7:0];
    wire [7:0] sharedram_a_dout;
    wire        sharedram_main_wr = ~main_mreq_n && ~main_wr_n &&
                                      main_a >= 16'he800 && main_a <= 16'he8ff;

    sharedram u_sharedram (
        .clk(clk_sys),
        .wr_addr(sharedram_main_wr ? main_a[7:0] : hs_addr),
        .wr_data(sharedram_main_wr ? main_dout : hs_wdata),
        .wr_en(sharedram_main_wr || hs_we),
        .a_addr(sharedram_a_addr), .a_dout(sharedram_a_dout),
        .b_addr(hs_addr), .b_dout(sharedram_hs_rdata)
    );

    // Latched: tv80 samples di only on cen, and a combinational mux would fall
    // back to 8'hff when the bus strobes drop between those points.
    always @(posedge clk_sys) begin
        if (~main_m1_n && ~main_iorq_n) begin
            // IM0 interrupt ack: the vector byte is sharedram[0].
            main_din <= sharedram_a_dout;
        end else if (~main_mreq_n && ~main_rd_n) begin
            if (main_a <= 16'h7fff)      main_din <= fixed_rom_q;
            else if (main_a <= 16'hbfff) main_din <= banked_rom_q;
            else if (main_a <= 16'he7ff) main_din <= main_ram_din;
            else if (main_a <= 16'he8ff) main_din <= sharedram_a_dout;
            else if (main_a <= 16'hefff) main_din <= plainram_q;
            else if (main_a == 16'hf010) main_din <= IN3;
            else if (main_a >= 16'hf800) main_din <= subram_q;
            // f000/f008/f018 are write-only and nothing else is mapped here;
            // unmapped reads return 0x00.
            else                         main_din <= 8'h00;
        end
    end

    always @(posedge clk_sys) begin
        if (~main_mreq_n && ~main_wr_n) begin
            if (main_a == 16'hf000) begin
                rombank  <= main_dout[2:0];
                charbank <= main_dout[5];
            end
            if (main_a == 16'hf008)
                reset_lines_q <= main_dout[2:0];
        end
    end

    // F800-FFFF: "subram", the 4-player sub-board comms RAM (main_map,
    // kikikai.cpp) -- unused by this game's own logic, but it's real,
    // readable/writable RAM on the address bus regardless, and a boot-time
    // sweep does walk through it.
    wire [7:0] subram_q;
    sdpram #(.AW(11), .DW(8)) u_subram (
        .clk(clk_sys),
        .wr_en(~main_mreq_n && ~main_wr_n && main_a >= 16'hf800),
        .wr_addr(main_a[10:0]), .wr_data(main_dout),
        .rd_addr(main_a[10:0]), .rd_data(subram_q)
    );

    // interrupt: level, vblank-set, cleared on the CPU's own ack cycle.
    reg vblank_q;
    always @(posedge clk_sys) begin
        vblank_q <= vblank;
        if (reset) main_int_n <= 1;
        else begin
            if (vblank && !vblank_q) main_int_n <= 0;
            if (!main_m1_n && !main_iorq_n) main_int_n <= 1;
        end
    end

endmodule
