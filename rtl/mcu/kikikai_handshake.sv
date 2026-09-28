// Kiki KaiKai's own protection/IO protocol, built on top of the MCU's
// generic ports 2-4 (kikikai_mcu.sv) -- transcribed directly from
// mcu_port1_w/mcu_port2_w/mcu_port3_r/mcu_port3_w/mcu_port4_w in the driver.
// Port 4 is the shared-RAM address, port 2 bit 2 is a clock: on its
// high-to-low edge, port 2 bits 4 and 0 (as they stand at that same edge)
// pick a shared-RAM write, a shared-RAM read, or a player-input read, and a
// read pulses `is3` to latch the result into the MCU's port 3.
module kikikai_handshake (
    input  logic        clk,
    input  logic        reset,

    input  logic [7:0]  p2,
    input  logic [7:0]  p3_out,
    input  logic [7:0]  p4,
    output logic [7:0]  p3_in,
    output logic        is3,

    output logic [7:0]  sharedram_addr,
    input  logic [7:0]  sharedram_rdata,
    output logic [7:0]  sharedram_wdata,
    output logic        sharedram_we,

    output logic        inputs_sel,   // p4 bit 0: IN1 (0) or IN2 (1)
    input  logic [7:0]  inputs_data
);

    assign sharedram_addr = p4;
    assign inputs_sel     = p4[0];

    logic [7:0] p2_q;

    always_ff @(posedge clk) begin
        sharedram_we <= 1'b0;
        is3          <= 1'b0;

        if (reset) begin
            p2_q <= 8'd0;
        end else begin
            if (p2_q[2] && !p2[2]) begin
                if (p2[4]) begin
                    p3_in <= p2[0] ? sharedram_rdata : inputs_data;
                    is3   <= 1'b1;
                end else begin
                    sharedram_wdata <= p3_out;
                    sharedram_we    <= 1'b1;
                end
            end
            p2_q <= p2;
        end
    end

endmodule
