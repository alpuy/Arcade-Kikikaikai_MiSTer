// One clocked write port, one clocked read port (1 cycle latency).
// Synthesis instantiates altsyncram directly: RAM inference proved
// unreliable for these arrays and silently fell back to registers.
// Simulators have no altsyncram, so they get the equivalent behavioral model.
`ifdef VERILATOR
 `define SDPRAM_BEHAVIORAL
`endif
`ifdef __ICARUS__
 `define SDPRAM_BEHAVIORAL
`endif
`ifdef SIMULATION
 `define SDPRAM_BEHAVIORAL
`endif

module sdpram #(
    parameter int AW = 8,
    parameter int DW = 8
) (
    input  logic          clk,

    input  logic          wr_en,
    input  logic [AW-1:0] wr_addr,
    input  logic [DW-1:0] wr_data,

    input  logic [AW-1:0] rd_addr,
    output logic [DW-1:0] rd_data
);

`ifdef SDPRAM_BEHAVIORAL
    logic [DW-1:0] mem [0:(1<<AW)-1];

    always_ff @(posedge clk) begin
        if (wr_en) mem[wr_addr] <= wr_data;
        rd_data <= mem[rd_addr];
    end
`else
    altsyncram #(
        .operation_mode                    ("DUAL_PORT"),
        .width_a                           (DW),
        .widthad_a                         (AW),
        .numwords_a                        (1 << AW),
        .width_b                           (DW),
        .widthad_b                         (AW),
        .numwords_b                        (1 << AW),
        .address_reg_b                     ("CLOCK0"),
        .outdata_reg_b                     ("UNREGISTERED"),
        .clock_enable_input_a              ("BYPASS"),
        .clock_enable_input_b              ("BYPASS"),
        .clock_enable_output_b             ("BYPASS"),
        .read_during_write_mode_mixed_ports("DONT_CARE"),
        .power_up_uninitialized            ("FALSE"),
        .ram_block_type                    ("M10K"),
        .intended_device_family            ("Cyclone V"),
        .lpm_type                          ("altsyncram")
    ) u_ram (
        .clock0        (clk),
        .wren_a        (wr_en),
        .address_a     (wr_addr),
        .data_a        (wr_data),
        .address_b     (rd_addr),
        .q_b           (rd_data),
        .aclr0         (1'b0),
        .aclr1         (1'b0),
        .addressstall_a(1'b0),
        .addressstall_b(1'b0),
        .byteena_a     (1'b1),
        .byteena_b     (1'b1),
        .clock1        (1'b1),
        .clocken0      (1'b1),
        .clocken1      (1'b1),
        .clocken2      (1'b1),
        .clocken3      (1'b1),
        .data_b        ({DW{1'b1}}),
        .eccstatus     (),
        .q_a           (),
        .rden_a        (1'b1),
        .rden_b        (1'b1),
        .wren_b        (1'b0)
    );
`endif

endmodule
