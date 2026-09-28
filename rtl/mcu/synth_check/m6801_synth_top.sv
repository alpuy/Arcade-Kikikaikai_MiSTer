// Standalone synthesis-check top level for the vendored M6801 core,
// targeting the DE10-nano's actual Cyclone V (5CSEBA6U23I7) via Quartus
// 17.0.2. Not part of the core's real top-level -- exists purely to answer
// "does the vendored CPU synthesize on the real device, and how fast"
// (Phase 0, exit criterion 4; see rtl/mcu/vendor/PROVENANCE.md) in
// isolation. Every port is passed straight through so nothing gets
// optimized away as unused.

module m6801_synth_top (
  input               CLK,
  input               RST,
  input               HOLD,
  input               HALT,
  input               IRQ,
  input               NMI,
  input               IRQ_ICF,
  input               IRQ_OCF,
  input               IRQ_TOF,
  input               IRQ_SCI,
  input        [7:0]  DATA_IN,
  output              RW,
  output              VMA,
  output       [15:0] ADDRESS,
  output       [7:0]  DATA_OUT,
  output       [15:0] TEST_ALU,
  output       [7:0]  TEST_CC
);

  M6801_core u_cpu (
    .clk(CLK), .rst(RST), .rw(RW), .vma(VMA), .address(ADDRESS),
    .data_in(DATA_IN), .data_out(DATA_OUT), .hold(HOLD), .halt(HALT),
    .irq(IRQ), .nmi(NMI), .irq_icf(IRQ_ICF), .irq_ocf(IRQ_OCF),
    .irq_tof(IRQ_TOF), .irq_sci(IRQ_SCI),
    .test_alu(TEST_ALU), .test_cc(TEST_CC)
  );

endmodule
