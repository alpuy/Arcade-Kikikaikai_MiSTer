// H/V counter chain for kikikai's raw screen timing (no CRTC):
// set_raw(6 MHz, htotal=384, hbend=0, hbstart=256, vtotal=264, vbend=16,
// vbstart=240). hpos/vpos are the counters sprite_engine and the palette
// output stage read directly; sync pulse position within blanking isn't
// given by the driver (no CRTC to read it from) and is a reasonable
// placeholder, not measured against real hardware.
module video_timing (
    input  logic        clk,
    input  logic        ce_pix,
    input  logic        reset,

    output logic [8:0] hpos,
    output logic [8:0] vpos,
    output logic         hblank,
    output logic         vblank,
    output logic         hsync,
    output logic         vsync
);

    localparam int HTOTAL = 384;
    localparam int HBSTART = 256;
    localparam int HSSTART = 280;
    localparam int HSEND   = 312;

    localparam int VTOTAL = 264;
    localparam int VBSTART = 240;
    localparam int VBEND   = 16;
    localparam int VSSTART = 244;
    localparam int VSEND   = 248;

    always_ff @(posedge clk) begin
        if (reset) begin
            hpos <= 9'd0;
            vpos <= 9'd0;
        end else if (ce_pix) begin
            if (hpos == HTOTAL - 1) begin
                hpos <= 9'd0;
                vpos <= (vpos == VTOTAL - 1) ? 9'd0 : vpos + 9'd1;
            end else begin
                hpos <= hpos + 9'd1;
            end
        end
    end

    assign hblank = (hpos >= HBSTART);
    assign vblank = (vpos >= VBSTART) || (vpos < VBEND);
    assign hsync  = (hpos >= HSSTART) && (hpos < HSEND);
    assign vsync  = (vpos >= VSSTART) && (vpos < VSEND);

endmodule
