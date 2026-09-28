
module mcu(
  input            reset,
  input            clk_sys,
  input      [7:0] mcu_p1,
  output reg [4:0] mcu_p2,
  input      [7:0] mcu_p3_i,
  output reg [7:0] mcu_p3_o,
  output reg [7:0] mcu_p4,
  input            mcu_irq,
  input            mcu_nmi,

  input            ioctl_download,
  input     [26:0] ioctl_addr,
  input     [15:0] ioctl_dout,
  input            ioctl_wr,

  input            vb
);

wire [15:0] mpu_addr;
wire  [7:0] mpu_dout;
wire        mpu_rw;

wire [7:0] ram_data;
wire [7:0] rom_data;
reg  [7:0] prt_data;

wire [7:0] mpu_din =
  rom_en ? rom_data :
  prt_en ? prt_data : ram_data;

reg [7:0] ddr1;
reg [7:0] ddr2;
reg [7:0] ddr3;
reg [7:0] ddr4;

always @(posedge clk_sys) begin
  if (reset) begin
    ddr1 <= 8'd0;
    ddr2 <= 8'd0;
    ddr3 <= 8'd0;
    ddr4 <= 8'd0;
  end
  else begin

    // no logic for DDR as they are all inputs

    case (mpu_addr)

      // port 1 DDR
      16'd0:
        if (~mpu_rw)
          ddr1 <= mpu_dout;
        else
          prt_data <= 8'hff;

      // port 2 DDR
      16'd1:
        if (~mpu_rw)
          ddr2 <= mpu_dout;
        else
          prt_data <= 8'hff;

      // port 1 DR
      16'd2:
        prt_data <= mcu_p1;

      // port 2 DR
      16'd3: begin
        if (~mpu_rw) begin
          mcu_p2 <= mpu_dout;
          prt_data <= mcu_p3_i; // latch p3
        end
        else
          prt_data <= mcu_p2;
      end

      // port 3 DDR
      16'd4:
        if (~mpu_rw)
          ddr3 <= mpu_dout;
        else
          prt_data <= 8'hff;

      // port 4 DDR
      16'd5:
        if (~mpu_rw)
          ddr4 <= mpu_dout;
        else
          prt_data <= 8'hff;

      // port 3 DR - read/write - ext data bus
      16'd6:begin
        if (~mpu_rw) mcu_p3_o <= mpu_dout;
      end

      // port 4 DR - write only - ext address bus
      16'd7:
        if (~mpu_rw) mcu_p4 <= mpu_dout;

    endcase
  end
end

wire [11:0] addr = ioctl_download ? ioctl_addr[11:0] : mpu_addr[11:0];
wire rom_wr      = ioctl_download && ioctl_addr >= 27'h20000 && ioctl_addr < 27'h21000 ? ioctl_wr : 1'b0;
wire rom_en      = &mpu_addr[15:12];
wire ram_en      = mpu_addr < 16'h100;
wire prt_en      = ~|mpu_addr[15:5]; // 00-1F

ram #(8,8) ram(
  .clk  ( clk_sys       ),
  .addr ( mpu_addr[7:0] ),
  .din  ( mpu_dout      ),
  .q    ( ram_data      ),
  .rd_n ( 1'b0          ),
  .wr_n ( mpu_rw        ),
  .ce_n ( ~ram_en       )
);

ram #(12,8) rom(
  .clk  ( clk_sys    ),
  .addr ( addr       ),
  .din  ( ioctl_dout ),
  .q    ( rom_data   ),
  .rd_n ( 1'b0       ),
  .wr_n ( ~rom_wr    ),
  .ce_n ( ~rom_en    )
);

wire cen;
clk_en #(CORE_CLK_1) cpu_clk_en(.ref_clk(clk_sys), .cen(cen), .clk());

M6801_core mpu(
  .clk      ( cen      ),
  .rst      ( reset    ),
  .rw       ( mpu_rw   ),
  .vma      (          ),
  .address  ( mpu_addr ),
  .data_in  ( mpu_din  ),
  .data_out ( mpu_dout ),
  .hold     (          ),
  .halt     (          ),
  .irq      ( vb       ),
  .nmi      (          ),
  .irq_icf  (          ),
  .irq_ocf  (          ),
  .irq_tof  (          ),
  .irq_sci  (          )
);

endmodule
