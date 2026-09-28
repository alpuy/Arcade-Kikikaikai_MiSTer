// palette_device::palette_init_rgb_444_proms (src/emu/emupal.cpp): a
// weighted-resistor ladder per gun, not a linear 4-bit expansion --
// 0x0e/0x1f/0x43/0x8f per bit. Matches the real PCB's ladder (2.2k/1k/
// 470/220 ohm), not a naive DAC.
module palette_dac (
    input  logic [3:0] nibble,
    output logic [7:0] level
);

    assign level = 8'(14 * nibble[0]) + 8'(31 * nibble[1]) + 8'(67 * nibble[2]) + 8'(143 * nibble[3]);

endmodule
