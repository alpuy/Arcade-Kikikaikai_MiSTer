// The 256-byte MCU<->main-CPU shared-RAM window (E800-E8FF). One write
// port, two independent synchronous read ports: main CPU (or its
// interrupt-ack read of byte 0) on one, kikikai_handshake on the other.
module sharedram (
    input  logic       clk,

    input  logic [7:0] wr_addr,
    input  logic [7:0] wr_data,
    input  logic        wr_en,

    input  logic [7:0] a_addr,
    output logic [7:0] a_dout,
    input  logic [7:0] b_addr,
    output logic [7:0] b_dout
);

    logic [7:0] mem [0:255];

    always_ff @(posedge clk) begin
        if (wr_en) mem[wr_addr] <= wr_data;
        a_dout <= mem[a_addr];
        b_dout <= mem[b_addr];
    end

endmodule
