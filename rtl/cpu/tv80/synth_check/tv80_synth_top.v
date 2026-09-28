// Standalone synthesis-check top level for tv80, targeting the DE10-nano's
// actual Cyclone V (5CSEBA6U23I7) via Quartus 17.0.2. Not part of the core's
// real top-level -- exists purely to answer "does the vendored CPU
// synthesize on the real device, and how fast" (Phase 0, exit criterion 4;
// see rtl/cpu/tv80/PROVENANCE.md) in isolation from the rest of the design,
// which doesn't exist yet. Every tv80s port is passed straight through so
// nothing gets optimized away as unused.

module tv80_synth_top (
  input         CLK,
  input         RESET_N,
  input         CEN,
  input         WAIT_N,
  input         INT_N,
  input         NMI_N,
  input         BUSRQ_N,
  input  [7:0]  DI,
  output        M1_N,
  output        MREQ_N,
  output        IORQ_N,
  output        RD_N,
  output        WR_N,
  output        RFSH_N,
  output        HALT_N,
  output        BUSAK_N,
  output [15:0] A,
  output [7:0]  DOUT
);

  tv80s #(.Mode(0)) u_cpu (
    .m1_n(M1_N), .mreq_n(MREQ_N), .iorq_n(IORQ_N), .rd_n(RD_N), .wr_n(WR_N),
    .rfsh_n(RFSH_N), .halt_n(HALT_N), .busak_n(BUSAK_N), .A(A), .dout(DOUT),
    .reset_n(RESET_N), .clk(CLK), .cen(CEN), .wait_n(WAIT_N),
    .int_n(INT_N), .nmi_n(NMI_N), .busrq_n(BUSRQ_N), .di(DI)
  );

endmodule
