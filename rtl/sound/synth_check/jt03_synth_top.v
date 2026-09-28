// Standalone synthesis-check top level for jt03 (YM2203), targeting the
// DE10-nano's actual Cyclone V (5CSEBA6U23I7) via Quartus 17.0.2. Not part
// of the core's real top-level -- exists purely to answer "does the
// vendored sound core synthesize on the real device, and how fast"
// (Phase 0, exit criterion 4; see rtl/sound/jt03/PROVENANCE.md) in
// isolation. Every port is passed straight through so nothing gets
// optimized away as unused.

module jt03_synth_top (
  input               RST,
  input               CLK,
  input               CEN,
  input        [7:0]  DIN,
  input               ADDR,
  input               CS_N,
  input               WR_N,
  input        [7:0]  IOA_IN,
  input        [7:0]  IOB_IN,
  output       [7:0]  DOUT,
  output              IRQ_N,
  output       [7:0]  PSG_A,
  output       [7:0]  PSG_B,
  output       [7:0]  PSG_C,
  output signed [15:0] FM_SND,
  output       [9:0]  PSG_SND,
  output signed [15:0] SND,
  output              SND_SAMPLE,
  output       [7:0]  DEBUG_VIEW
);

  jt03 u_snd (
    .rst(RST), .clk(CLK), .cen(CEN), .din(DIN), .addr(ADDR), .cs_n(CS_N), .wr_n(WR_N),
    .dout(DOUT), .irq_n(IRQ_N),
    .IOA_in(IOA_IN), .IOB_in(IOB_IN),
    .psg_A(PSG_A), .psg_B(PSG_B), .psg_C(PSG_C), .fm_snd(FM_SND),
    .psg_snd(PSG_SND), .snd(SND), .snd_sample(SND_SAMPLE), .debug_view(DEBUG_VIEW)
  );

endmodule
