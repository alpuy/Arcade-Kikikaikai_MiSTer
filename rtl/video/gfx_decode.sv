// Kiki KaiKai charlayout tile pixel decode, kikikai.cpp:964-977.
//
// gfx1 is read as two 0x20000-byte halves: the low byte (plane3 = LSB in
// its low nibble, plane2 in its high nibble) and, 0x20000 bytes further in,
// the high byte (plane1 low nibble, plane0 high nibble). Final pixel value
// is assembled MSB-first over MAME's planeoffset array (plane0 -> bit 3),
// not LSB-first as the array order suggests -- see docs/LESSONS_LEARNED.md,
// [Kikikaikai], for how that was found. ROMREGION_INVERT means the raw
// EPROM bytes are inverted relative to the pixel data, so both bytes are
// inverted here, not at ROM-load time.
module gfx_decode (
    input  logic [12:0] code,
    input  logic [2:0]  row,       // 0-7, row within the 8x8 tile
    input  logic         x_half,    // 0 = pixels 0-3, 1 = pixels 4-7
    output logic [17:0] addr_b,    // gfx1[addr_b], low byte
    output logic [17:0] addr_c,    // gfx1[addr_b + 0x20000], high byte
    input  logic [7:0]  rom_b,
    input  logic [7:0]  rom_c,
    output logic [15:0] pixel   // 4 nibbles packed, pixel[4*xi +: 4] = pixel xi
);

    assign addr_b = (18'(code) << 4) + {14'd0, row, 1'b0} + {17'd0, x_half};
    assign addr_c = addr_b + 18'h20000;

    logic [7:0] inv_b, inv_c;
    assign inv_b = ~rom_b;
    assign inv_c = ~rom_c;

    genvar xi;
    generate
        for (xi = 0; xi < 4; xi = xi + 1) begin : g_pix
            assign pixel[4*xi +: 4] = {inv_c[4+xi], inv_c[xi], inv_b[4+xi], inv_b[xi]};
        end
    endgenerate

endmodule
