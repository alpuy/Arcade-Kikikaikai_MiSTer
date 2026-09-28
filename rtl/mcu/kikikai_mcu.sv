// MC6801U4 register block: internal ROM/RAM and the port 1-4 peripheral
// registers, wrapped around the bare M6801_core kernel, which implements
// none of this itself. Chip-generic; the game's port 2-4 protocol lives in
// kikikai_handshake.sv.
//
// RAM is gated by the RAM Control Register's enable bit (register $14, bit
// 6) same as real silicon -- RAM is disabled until firmware turns it on,
// clear at reset.
//
// Port 3 latch-on-strobe (registers $06/$0f, the `is3` pulse): a
// rising edge latches the external port 3 input into the data register (only
// if LE is set and the previous latch was already consumed) and sets the
// status flag; reading the status register while the flag is set arms a
// clear that the next data register access performs -- two-step, not
// same-access, matching the real part.
module kikikai_mcu (
    input  logic        clk,
    input  logic        cen,       // one MCU clock cycle; the core freezes (hold) between them
    input  logic        reset,
    input  logic        irq,       // vblank, M6801_IRQ1_LINE

    input  logic [7:0]  p1_in,
    output logic [7:0]  p1_out,    // DDR-masked: 1s where DDR is input
    output logic [7:0]  p2_out,
    input  logic [7:0]  p3_in,
    output logic [7:0]  p3_out,
    output logic [7:0]  p4_out,
    input  logic        is3,

    output logic [15:0] rom_addr,
    input  logic [7:0]  rom_data
);

    wire [15:0] mpu_addr;
    wire  [7:0] mpu_dout;
    wire        mpu_rw;

    assign rom_addr = mpu_addr;

    logic [7:0] ram [0:191];   // $40-$ff, M6801U4's internal RAM window
    logic [7:0] ram_q;
    wire        rom_en = &mpu_addr[15:12];              // $f000-$ffff
    wire        ram_en = mpu_addr >= 16'h40 && mpu_addr < 16'h100;
    wire        io_en  = mpu_addr < 16'h1e;              // $00-$1d

    // port registers
    logic [7:0] ddr1, ddr2, ddr3, ddr4;
    logic [7:0] pd1, pd2, pd3, pd4;
    logic [7:0] p3csr;
    logic       port3_latched;
    logic       pending_isf_clear;

    // placeholder registers: firmware may probe/init these, no timer/SCI
    // behavior implemented (this game's handshake doesn't need it)
    logic [7:0] tcsr, ch, cl, ocrh, ocrl, rmcr, trcsr, tdr, rcr_reg;
    logic [7:0] u4_15, u4_16, u4_18, u4_1a, u4_1b, u4_1c, u4_1d;

    wire ram_enabled = rcr_reg[6];

    assign p1_out = (pd1 & ddr1) | ~ddr1;
    assign p4_out = (pd4 & ddr4) | ~ddr4;

    // write_port2(): 5-bit port, DDR-masked, ones where DDR selects input
    assign p2_out = {3'd0, (pd2[4:0] & ddr2[4:0]) | (~ddr2[4:0] & 5'h1f)};

    logic [7:0] io_rdata;
    always_comb begin
        io_rdata = 8'hff;
        case (mpu_addr[4:0])
            5'h00, 5'h01, 5'h04, 5'h05: io_rdata = 8'hff;               // DDRs read as ff
            5'h02: io_rdata = (ddr1 == 8'hff) ? pd1 : ((p1_in & ~ddr1) | (pd1 & ddr1));
            5'h03: io_rdata = (ddr2 == 8'hff) ? pd2 : (pd2 & ddr2) | ~ddr2;
            5'h06: io_rdata = (p3csr[3] || ddr3 == 8'hff) ? pd3 : ((p3_in & ~ddr3) | (pd3 & ddr3));
            5'h07: io_rdata = (ddr4 == 8'hff) ? pd4 : ((p4_out & ~ddr4) | (pd4 & ddr4));
            5'h08: io_rdata = tcsr;
            5'h09: io_rdata = ch;
            5'h0a: io_rdata = cl;
            5'h0b: io_rdata = ocrh;
            5'h0c: io_rdata = ocrl;
            5'h0d: io_rdata = 8'h00;   // ICRH, unimplemented timer
            5'h0e: io_rdata = 8'h00;   // ICRL
            5'h0f: io_rdata = p3csr;
            5'h10: io_rdata = rmcr;
            5'h11: io_rdata = trcsr;
            5'h12: io_rdata = 8'h00;   // RDR
            5'h14: io_rdata = rcr_reg | 8'h3f;
            5'h15: io_rdata = u4_15;
            5'h16: io_rdata = u4_16;
            5'h18: io_rdata = u4_18;
            5'h19: io_rdata = 8'h00;   // TSR
            5'h1a: io_rdata = u4_1a;
            5'h1b: io_rdata = u4_1b;
            5'h1c: io_rdata = u4_1c;
            5'h1d: io_rdata = u4_1d;
            default: io_rdata = 8'hff;
        endcase
    end

    assign ram_q = ram[mpu_addr[7:0] - 8'h40];
    wire [7:0] mpu_din = rom_en ? rom_data : ram_en ? ram_q : io_en ? io_rdata : 8'hff;

    // is3 latch: rising edge only, one pending latch at a time. The pin is
    // edge-sampled every clk, not just on cen, and held until the next MCU
    // cycle consumes it -- a strobe narrower than one MCU cycle still lands.
    logic is3_q, is3_rose;
    wire  is3_edge = is3_rose || (is3 && !is3_q);

    always_ff @(posedge clk) begin
        if (reset) begin
            ddr1 <= 8'd0; ddr2 <= 8'd0; ddr3 <= 8'd0; ddr4 <= 8'd0;
            pd1 <= 8'd0; pd2 <= 8'd0; pd3 <= 8'd0; pd4 <= 8'd0;
            p3csr <= 8'd0; pending_isf_clear <= 1'b0; is3_q <= 1'b0; is3_rose <= 1'b0;
            tcsr <= 8'd0; ch <= 8'd0; cl <= 8'd0; ocrh <= 8'hff; ocrl <= 8'hff;
            rmcr <= 8'd0; trcsr <= 8'h20; tdr <= 8'd0; rcr_reg <= 8'd0;
            u4_15 <= 8'd0; u4_16 <= 8'd0; u4_18 <= 8'd0;
            u4_1a <= 8'hff; u4_1b <= 8'hff; u4_1c <= 8'hff; u4_1d <= 8'hff;
        end else begin
            is3_q <= is3;
            if (is3 && !is3_q) is3_rose <= 1'b1;
        end

        if (!reset && cen) begin
            is3_rose <= 1'b0;
            if (is3_edge && !port3_latched && p3csr[3]) begin
                pd3           <= (p3_in & ~ddr3) | (pd3 & ddr3);
                port3_latched <= 1'b1;
                p3csr[7]      <= 1'b1;
            end

            // port 3 data register access (read or write) performs a
            // pending flag clear armed by a status-register read
            if (io_en && mpu_addr[4:0] == 5'h06) begin
                if (pending_isf_clear) begin
                    p3csr[7]           <= 1'b0;
                    pending_isf_clear  <= 1'b0;
                end
                port3_latched <= 1'b0;
            end

            if (io_en && ~mpu_rw) begin
                case (mpu_addr[4:0])
                    5'h00: ddr1 <= mpu_dout;
                    5'h01: ddr2 <= mpu_dout;
                    5'h02: pd1  <= mpu_dout;
                    5'h03: pd2  <= mpu_dout;
                    5'h04: ddr3 <= mpu_dout;
                    5'h05: ddr4 <= mpu_dout;
                    5'h06: pd3  <= mpu_dout;
                    5'h07: pd4  <= mpu_dout;
                    5'h08: tcsr <= mpu_dout;
                    5'h09: ch   <= mpu_dout;
                    5'h0a: cl   <= mpu_dout;
                    5'h0b: ocrh <= mpu_dout;
                    5'h0c: ocrl <= mpu_dout;
                    5'h0f: p3csr <= mpu_dout;
                    5'h10: rmcr  <= mpu_dout;
                    5'h11: trcsr <= (trcsr & 8'he0) | (mpu_dout & 8'h1f);
                    5'h13: tdr   <= mpu_dout;
                    5'h14: rcr_reg <= mpu_dout;
                    5'h15: u4_15 <= mpu_dout;
                    5'h16: u4_16 <= mpu_dout;
                    5'h18: u4_18 <= mpu_dout;
                    5'h1a: u4_1a <= mpu_dout;
                    5'h1b: u4_1b <= mpu_dout;
                    5'h1c: u4_1c <= mpu_dout;
                    5'h1d: u4_1d <= mpu_dout;
                    default: ;
                endcase
            end else if (io_en && mpu_addr[4:0] == 5'h0f && p3csr[7]) begin
                pending_isf_clear <= 1'b1;
            end

            if (ram_enabled && ram_en && ~mpu_rw)
                ram[mpu_addr[7:0] - 8'h40] <= mpu_dout;
        end
    end

    assign p3_out = (pd3 & ddr3) | ~ddr3;   // same DDR-masked out_port_func call as p1/p4

    M6801_core u_cpu (
        .clk      (clk),
        .rst      (reset),
        .rw       (mpu_rw),
        .vma      (),
        .address  (mpu_addr),
        .data_in  (mpu_din),
        .data_out (mpu_dout),
        .hold     (~cen),   // freezes all 13 of the core's clocked blocks; reset still wins
        .halt     (1'b0),
        .irq      (irq),
        .nmi      (1'b0),
        .irq_icf  (1'b0),
        .irq_ocf  (1'b0),
        .irq_tof  (1'b0),
        .irq_sci  (1'b0),
        .test_alu (),
        .test_cc  ()
    );

endmodule
