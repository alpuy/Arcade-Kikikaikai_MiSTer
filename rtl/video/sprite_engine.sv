// Per-scanline object-list walk: one 192-entry pass per raster line.
// `sy = 256 - height*8 - ty` and the column-continuation `sx` wrap in the
// full 8-bit raster space.
//
// mainram and gfx1 are synchronous memories with 2 read ports each, the
// block RAM limit. Data is valid two states after its address is set; the
// S_WAIT_* states exist only for that.
module sprite_engine (
    input  logic        clk,
    input  logic         reset,
    input  logic         start,        // pulse: begin computing `line`
    input  logic [7:0]  line,         // raster line, 0-255 space
    output logic         done,         // pulses when the line buffer is ready

    output logic [13:0] mem_a_addr,
    input  logic [7:0]  mem_a_dout,
    output logic [13:0] mem_b_addr,
    input  logic [7:0]  mem_b_dout,

    output logic [17:0] gfx_a_addr,
    input  logic [7:0]  gfx_a_dout,
    output logic [17:0] gfx_b_addr,
    input  logic [7:0]  gfx_b_dout,

    output logic [7:0]  lb_pixel [0:255],
    output logic         lb_painted [0:255]
);

    localparam int OBJ_BASE = 16'h1500;
    localparam int OBJ_COUNT = 192;

    typedef enum logic [4:0] {
        S_IDLE,
        S_WAIT_TY_GN, S_CAP_TY_GN, S_WAIT_TX, S_CAP_TX,
        S_WAIT_CODE_L, S_CAP_CODE_L, S_WAIT_TILE_L0, S_CAP_TILE_L0,
        S_WAIT_TILE_L1, S_CAP_TILE_L1, S_WAIT_TILE_R0, S_CAP_TILE_R0,
        S_WAIT_TILE_R1, S_CAP_TILE_R1,
        S_DONE
    } state_t;
    state_t state;

    logic [7:0]  idx;
    logic [7:0]  sx;
    logic [7:0]  ty_r, gn_r;
    logic [2:0]  row_r;
    logic [2:0]  color_l_r, color_r_r;
    logic [13:0] goffs_r_r;
    logic [12:0] cur_code_r;
    logic         cur_xhalf_r;
    logic [15:0] pix_l0_r, pix_l1_r, pix_r0_r;

    wire [15:0] off      = 16'(OBJ_BASE) + {idx, 2'b00};
    wire [15:0] next_off = 16'(OBJ_BASE) + {(idx + 8'd1), 2'b00};

    // decode of the just-captured entry header (ty_r/gn_r latched in
    // S_CAP_TY_GN, tx live off mem_a_dout during S_CAP_TX) -- same formulas
    // the object-list walk always used, evaluated once per entry instead
    // of once per array element
    wire         is_column = gn_r[7];
    wire         skip      = is_column ? 1'b0 : ~(|ty_r & |mem_a_dout);
    wire [12:0] gfx_offs  = is_column ? {gn_r[5:0], 7'b0}
                                        : ({gn_r[4:0], 7'b0} + {5'd0, gn_r[6:5], 4'b0} + 13'd12);
    wire [5:0]  height_half = is_column ? 6'd32 : 6'd2;
    wire [7:0]  sx_next  = is_column ? (gn_r[6] ? (sx + 8'd16) : mem_a_dout) : mem_a_dout;
    wire [7:0]  sy        = is_column ? (8'd0 - ty_r) : (8'd240 - ty_r);

    wire [7:0] d    = line - sy;
    wire [4:0] band = d[7:3];
    wire [2:0] row_comb = d[2:0];
    wire        draw   = ~skip & ({3'd0, band} < {2'd0, height_half});
    wire [13:0] goffs_l = {1'b0, gfx_offs} + {8'd0, band, 1'b0};

    // same formula reused for both tiles -- whichever's code/attr bytes
    // are on the mem_a/mem_b bus this cycle (S_CAP_CODE_L or S_CAP_TILE_L1,
    // which doubles as "code_r ready")
    wire [12:0] code_now = {mem_b_dout[4:0], mem_a_dout};

    logic [15:0] gd_pixel;
    gfx_decode u_gfx (
        .code(cur_code_r), .row(row_r), .x_half(cur_xhalf_r),
        .addr_b(gfx_a_addr), .addr_c(gfx_b_addr),
        .rom_b(gfx_a_dout), .rom_c(gfx_b_dout),
        .pixel(gd_pixel)
    );

    task automatic paint_px(input logic [7:0] x, input logic [2:0] color, input logic [3:0] pv);
        if (pv != 4'hF) begin
            lb_pixel[x]   <= {color, pv};
            lb_painted[x] <= 1'b1;
        end
    endtask

    always_ff @(posedge clk) begin
        done <= 1'b0;
        case (state)
            S_IDLE: if (start) begin
                idx <= 8'd0;
                sx  <= 8'd0;
                for (int i = 0; i < 256; i++) begin
                    lb_pixel[i]   = 8'd0;
                    lb_painted[i] = 1'b0;
                end
                // OBJ_BASE directly, not `off` -- `off` is combinational from
                // the *current* idx (still whatever the previous line left
                // it at), one cycle before the idx<=0 above takes effect
                mem_a_addr <= 16'(OBJ_BASE);
                mem_b_addr <= 16'(OBJ_BASE) + 14'd1;
                state <= S_WAIT_TY_GN;
            end

            S_WAIT_TY_GN: state <= S_CAP_TY_GN;
            S_CAP_TY_GN: begin
                ty_r <= mem_a_dout;
                gn_r <= mem_b_dout;
                mem_a_addr <= off[13:0] + 14'd2;
                state <= S_WAIT_TX;
            end

            S_WAIT_TX: state <= S_CAP_TX;
            S_CAP_TX: begin
                if (!skip) sx <= sx_next;
                row_r <= row_comb;
                if (draw) begin
                    goffs_r_r  <= goffs_l + 14'h40;
                    mem_a_addr <= goffs_l;
                    mem_b_addr <= goffs_l + 14'd1;
                    state <= S_WAIT_CODE_L;
                end else if (idx == OBJ_COUNT - 1) begin
                    state <= S_DONE;
                end else begin
                    idx <= idx + 8'd1;
                    mem_a_addr <= next_off[13:0];
                    mem_b_addr <= next_off[13:0] + 14'd1;
                    state <= S_WAIT_TY_GN;
                end
            end

            S_WAIT_CODE_L: state <= S_CAP_CODE_L;
            S_CAP_CODE_L: begin
                color_l_r   <= mem_b_dout[7:5];
                cur_code_r  <= code_now;
                cur_xhalf_r <= 1'b0;
                state <= S_WAIT_TILE_L0;
            end

            S_WAIT_TILE_L0: state <= S_CAP_TILE_L0;
            S_CAP_TILE_L0: begin
                pix_l0_r    <= gd_pixel;
                cur_xhalf_r <= 1'b1;
                mem_a_addr  <= goffs_r_r;
                mem_b_addr  <= goffs_r_r + 14'd1;
                state <= S_WAIT_TILE_L1;
            end

            S_WAIT_TILE_L1: state <= S_CAP_TILE_L1;
            S_CAP_TILE_L1: begin
                pix_l1_r    <= gd_pixel;
                color_r_r   <= mem_b_dout[7:5];
                cur_code_r  <= code_now;
                cur_xhalf_r <= 1'b0;
                state <= S_WAIT_TILE_R0;
            end

            S_WAIT_TILE_R0: state <= S_CAP_TILE_R0;
            S_CAP_TILE_R0: begin
                pix_r0_r    <= gd_pixel;
                cur_xhalf_r <= 1'b1;
                state <= S_WAIT_TILE_R1;
            end

            S_WAIT_TILE_R1: state <= S_CAP_TILE_R1;
            S_CAP_TILE_R1: begin
                paint_px(sx + 8'd0,  color_l_r, pix_l0_r[3:0]);
                paint_px(sx + 8'd1,  color_l_r, pix_l0_r[7:4]);
                paint_px(sx + 8'd2,  color_l_r, pix_l0_r[11:8]);
                paint_px(sx + 8'd3,  color_l_r, pix_l0_r[15:12]);
                paint_px(sx + 8'd4,  color_l_r, pix_l1_r[3:0]);
                paint_px(sx + 8'd5,  color_l_r, pix_l1_r[7:4]);
                paint_px(sx + 8'd6,  color_l_r, pix_l1_r[11:8]);
                paint_px(sx + 8'd7,  color_l_r, pix_l1_r[15:12]);
                paint_px(sx + 8'd8,  color_r_r, pix_r0_r[3:0]);
                paint_px(sx + 8'd9,  color_r_r, pix_r0_r[7:4]);
                paint_px(sx + 8'd10, color_r_r, pix_r0_r[11:8]);
                paint_px(sx + 8'd11, color_r_r, pix_r0_r[15:12]);
                paint_px(sx + 8'd12, color_r_r, gd_pixel[3:0]);
                paint_px(sx + 8'd13, color_r_r, gd_pixel[7:4]);
                paint_px(sx + 8'd14, color_r_r, gd_pixel[11:8]);
                paint_px(sx + 8'd15, color_r_r, gd_pixel[15:12]);

                if (idx == OBJ_COUNT - 1) begin
                    state <= S_DONE;
                end else begin
                    idx <= idx + 8'd1;
                    mem_a_addr <= next_off[13:0];
                    mem_b_addr <= next_off[13:0] + 14'd1;
                    state <= S_WAIT_TY_GN;
                end
            end

            S_DONE: begin
                done  <= 1'b1;
                state <= S_IDLE;
            end

            default: state <= S_IDLE;
        endcase
        if (reset) begin
            state <= S_IDLE;
            done  <= 1'b0;
        end
    end

endmodule
