// gfx1 as two 0x20000-byte halves, one read port each. gfx_decode's two
// addresses per tile row always fall one in each half (addr_b below
// 0x20000, addr_c = addr_b + 0x20000), so each half needs only one write
// and one read port. A single array with one write and two read ports was
// duplicated by Quartus into two full 2 Mbit copies -- ~512 of the
// device's 553 M10K blocks -- which starved everything else of block RAM.
module gfx1_rom (
    input  logic         clk,

    input  logic [7:0]  wr_data,
    input  logic [17:0] wr_addr,
    input  logic         wr_en,

    input  logic [17:0] a_addr,   // low half
    output logic [7:0]  a_dout,
    input  logic [17:0] b_addr,   // high half
    output logic [7:0]  b_dout
);

    sdpram #(.AW(17), .DW(8)) u_lo (
        .clk(clk),
        .wr_en(wr_en && !wr_addr[17]), .wr_addr(wr_addr[16:0]), .wr_data(wr_data),
        .rd_addr(a_addr[16:0]), .rd_data(a_dout)
    );

    sdpram #(.AW(17), .DW(8)) u_hi (
        .clk(clk),
        .wr_en(wr_en && wr_addr[17]), .wr_addr(wr_addr[16:0]), .wr_data(wr_data),
        .rd_addr(b_addr[16:0]), .rd_data(b_dout)
    );

endmodule
