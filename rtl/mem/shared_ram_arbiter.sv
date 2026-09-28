// mainram (main CPU C000-E7FF, sound CPU 8000-A7FF -- two windows onto the
// same RAM) with real WAIT contention. The board has two 8Kx8 RAM
// devices on one 13-bit address bus (16 bits wide total) -- video reads a
// word (both chips) at once, either CPU only ever wants one byte, and a
// bus-owner latch asserts real WAIT on whichever CPU loses a same-cycle
// access. Two assumptions, unverified against real hardware:
//   - the contended resource is treated as the address bus itself, not the
//     individual byte lane -- any cycle both CPUs assert mreq into this
//     window conflicts, even if they'd land in different chips, since only
//     one CPU's address can reach the RAM's address pins at a time;
//   - the main CPU is given fixed priority on a contention collision
//     (never waits for the sound CPU); both CPUs wait one read's worth of
//     latency regardless, real silicon having no zero-latency path either.
//
// main_din/snd_din are synchronous block RAM reads (1 cycle latency).
// wait_n is held low from a read's first cycle through at least one `cen`
// pulse: tv80 only checks wait_n on cen, so a one-clk pulse could be missed.
module shared_ram_arbiter (
    input  logic         clk,
    input  logic         cen,          // cen_6m -- tv80's own bus-cycle clock enable

    // main CPU: raw Z80 bus, absolute address (window C000-E7FF)
    input  logic [15:0] main_a,
    input  logic         main_mreq_n,
    input  logic         main_rd_n,
    input  logic         main_wr_n,
    input  logic [7:0]  main_dout,
    output logic [7:0]  main_din,
    output logic         main_sel,     // this cycle's address is in this window
    output logic         main_wait_n,  // 0 = assert the main Z80's WAIT pin

    // sound CPU: raw Z80 bus, absolute address (window 8000-A7FF)
    input  logic [15:0] snd_a,
    input  logic         snd_mreq_n,
    input  logic         snd_rd_n,
    input  logic         snd_wr_n,
    input  logic [7:0]  snd_dout,
    output logic [7:0]  snd_din,
    output logic         snd_sel,
    output logic         snd_wait_n,   // 0 = assert the sound Z80's WAIT pin

    // sprite_engine's 2 synchronous read ports, one per mirrored copy
    input  logic [13:0] eng_a_addr,
    output logic [7:0]  eng_a_dout,
    input  logic [13:0] eng_b_addr,
    output logic [7:0]  eng_b_dout
);

    wire main_req = ~main_mreq_n && (~main_rd_n || ~main_wr_n) &&
                    main_a >= 16'hc000 && main_a <= 16'he7ff;
    wire snd_req  = ~snd_mreq_n && (~snd_rd_n || ~snd_wr_n) &&
                    snd_a >= 16'h8000 && snd_a <= 16'ha7ff;

    assign main_sel = main_req;
    assign snd_sel  = snd_req;

    // C000 and 8000 are both multiples of the 0x4000 window size, so
    // dropping the top two address bits is the same as subtracting the
    // window base -- no arithmetic needed, just a bit slice, for both CPUs.
    wire [13:0] main_idx = main_a[13:0];
    wire [13:0] snd_idx  = snd_a[13:0];

    // Two mirrored copies sharing one merged write, each with two read-only
    // ports. One port per CPU reading and writing the same address is true
    // dual-port with same-address read-during-write, which M10K can't infer.
    wire        wr_en   = (main_req && ~main_wr_n) || (snd_req && ~snd_wr_n && snd_wait_n);
    wire [13:0] wr_addr = (main_req && ~main_wr_n) ? main_idx : snd_idx;
    wire [7:0]  wr_data = (main_req && ~main_wr_n) ? main_dout : snd_dout;

    logic [7:0] ram_a [0:16'h27ff];   // serves main_din, eng_a_dout
    logic [7:0] ram_b [0:16'h27ff];   // serves snd_din, eng_b_dout

    always_ff @(posedge clk) begin
        if (wr_en) ram_a[wr_addr] <= wr_data;
        main_din   <= ram_a[main_idx];
        eng_a_dout <= ram_a[eng_a_addr];
    end

    always_ff @(posedge clk) begin
        if (wr_en) ram_b[wr_addr] <= wr_data;
        snd_din    <= ram_b[snd_idx];
        eng_b_dout <= ram_b[eng_b_addr];
    end

    // base read latency: hold wait from a read's first cycle through the
    // next cen pulse, whichever CPU it is
    wire main_rd_now = main_req && ~main_rd_n;
    wire snd_rd_now  = snd_req && ~snd_rd_n;
    reg  main_rd_q, snd_rd_q;
    reg  main_pending, snd_pending;

    always_ff @(posedge clk) begin
        main_rd_q <= main_rd_now;
        snd_rd_q  <= snd_rd_now;

        if (main_rd_now && !main_rd_q)     main_pending <= 1'b1;
        else if (main_pending && cen)      main_pending <= 1'b0;

        if (snd_rd_now && !snd_rd_q)   snd_pending <= 1'b1;
        else if (snd_pending && cen)   snd_pending <= 1'b0;
    end

    assign main_wait_n = ~main_pending;
    // contention: sound always yields to a same-cycle main access, on top
    // of its own base read latency above
    assign snd_wait_n  = ~(snd_pending || (main_req && snd_req));

endmodule
