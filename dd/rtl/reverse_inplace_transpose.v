`timescale 1ns/1ps

// =============================================================================
// Module : reverse_inplace_transpose
// Description : Converts chunk format back to per-lane-per-cycle format using
//               two 8x8 ping-pong buffers. Write rows (one chunk per beat),
//               read columns (one sample per lane per cycle) = classic matrix
//               transpose.
//
//               Fixed latency: T0..T7 fill first buffer (INIT_FILL), T9 first
//               output. All modes (LANE8/LANE4, PHY/VLANE) share the same 9T
//               startup.
//
//               Two data formats are supported via the `mode` input:
//
//                 MODE_PHY   (mode==0): each chunk is one physical-lane row.
//                   LANE8 : 8 beats fill one row per beat (cols 0..7).
//                   LANE4 : 2 beats per row (first beat cols[0:3], second
//                           beat cols[4:7]); 4 rows total.
//
//                 MODE_VLANE (mode==1): each chunk carries 4 samples from
//                   one vlane (= pair of physical lanes).
//                   Chunk layout (per forward scheduler):
//                     chunk[0,2,4,6] = 4 cycles of physical lane 2*vlane
//                     chunk[1,3,5,7] = 4 cycles of physical lane 2*vlane+1
//                   Two chunks per vlane are needed to fill 8 output cycles
//                   (first chunk -> cols[0..3], second chunk -> cols[4..7]).
//                   LANE8 VLANE : 4 vlanes active, beat order is
//                                 {v0,v1,v2,v3,v0,v1,v2,v3} -> 8 beats fill
//                                 all 8 physical-lane rows.
//                   LANE4 VLANE : 2 vlanes active, beat order is
//                                 {v0,v1,v0,v1} -> 4 beats fill rows 0..3,
//                                 rows 4..7 are zero-filled.
//
// Target : FPGA / ASIC generic
// =============================================================================

module reverse_inplace_transpose (
    clk, rst_n, lane_cfg, mode, valid_in,
    din_top0, din_top1, din_top2, din_top3,
    din_bot0, din_bot1, din_bot2, din_bot3,
    valid_out,
    dout0, dout1, dout2, dout3, dout4, dout5, dout6, dout7
);

    parameter DATA_W = 32;

    // =========================================================================
    // Port declarations
    // =========================================================================
    input              clk, rst_n;
    input              lane_cfg;         // 0 = LANE8, 1 = LANE4
    input              mode;             // 0 = MODE_PHY, 1 = MODE_VLANE
    input              valid_in;
    input  [DATA_W-1:0] din_top0, din_top1, din_top2, din_top3;
    input  [DATA_W-1:0] din_bot0, din_bot1, din_bot2, din_bot3;
    output reg         valid_out;
    output [DATA_W-1:0] dout0, dout1, dout2, dout3, dout4, dout5, dout6, dout7;

    // =========================================================================
    // Local parameters
    // =========================================================================
    localparam LANE8     = 1'b0;
    localparam LANE4     = 1'b1;
    localparam MODE_PHY   = 1'b0;
    localparam MODE_VLANE = 1'b1;

    localparam [1:0] INIT_FILL = 2'd0;
    localparam [1:0] STREAM    = 2'd1;

    // =========================================================================
    // Ping-pong buffers: two 8-row x 8-col matrices
    // =========================================================================
    reg [DATA_W-1:0] buf_0 [0:7][0:7];
    reg [DATA_W-1:0] buf_1 [0:7][0:7];

    // =========================================================================
    // Write-path state (MODE_PHY uses wr_row + l4_beat; MODE_VLANE uses vl_beat)
    // =========================================================================
    reg [1:0]  state;
    reg        wr_sel;          // 0 = write buf_0, 1 = write buf_1
    reg [2:0]  wr_row;          // MODE_PHY LANE8/LANE4 row counter
    reg        l4_beat;         // MODE_PHY LANE4: 0 = first half, 1 = second half
    reg [2:0]  vl_beat;         // MODE_VLANE beat counter (0..7 LANE8 / 0..3 LANE4)
    reg        prev_valid;      // for fresh-burst detection

    // =========================================================================
    // Read-path state
    // =========================================================================
    reg        rd_sel;          // captured at read start
    reg        reading;         // read FSM active
    reg [2:0]  rd_col;          // current read column (0..7)
    reg        rd_start;        // pulse: trigger read next cycle

    // =========================================================================
    // Output data registers
    // =========================================================================
    reg [DATA_W-1:0] rd_data [0:7];

    integer i, j;

    // =========================================================================
    // VLANE beat decoding (combinational)
    // =========================================================================
    // LANE8 VLANE (8 beats per buffer, each beat = 1 vlane's 4 cycles, 8 samples):
    //   beat[2] = group (0: cycles 0-3 / cols 0-3,  1: cycles 4-7 / cols 4-7)
    //   beat[1:0] = vlane index (0..3)
    //   Each beat writes rows (2*vlane, 2*vlane+1), cols vl_col_base..base+3
    //   using din_top0..3 + din_bot0..3 (8 samples).
    //
    // LANE4 VLANE (8 beats per buffer, each beat = 1 vlane's 2 cycles, 4 samples):
    //   Upstream (u_buf_a LANE4 VLANE) splits each vlane chunk into 2 beats of
    //   4 samples (din_bot* are 0 in 4L mode). Beat layout:
    //     beat[2] = super-group (0: input cycles 0-3, 1: cycles 4-7)
    //     beat[1] = vlane index (0..1 -> rows 0,1 or 2,3)
    //     beat[0] = half within super-group (0: cycles c0/c1 or c4/c5,
    //                                        1: cycles c2/c3 or c6/c7)
    //   Each beat writes rows (2*vlane, 2*vlane+1) at col pair
    //     base_col = {beat[2], beat[0], 1'b0} in {0, 2, 4, 6}
    //   din_top0 -> buf[base_row  ][base_col  ]  (even lane, even cycle)
    //   din_top1 -> buf[base_row+1][base_col  ]  (odd  lane, even cycle)
    //   din_top2 -> buf[base_row  ][base_col+1]  (even lane, odd  cycle)
    //   din_top3 -> buf[base_row+1][base_col+1]  (odd  lane, odd  cycle)
    //   Rows 4..7 are zero-filled (only 2 vlanes active).
    reg        vl_half;         // LANE8 only: selects cols 0-3 vs 4-7
    reg [1:0]  vl_vlane;        // LANE8 only: vlane index
    reg [2:0]  vl_col_base;     // LANE8 only
    reg [2:0]  vl_row_lo;       // physical lane 2*vlane
    reg [2:0]  vl_row_hi;       // physical lane 2*vlane+1

    // LANE4 VLANE-specific decode
    reg [2:0]  vl4_base_row;    // 0 or 2
    reg [2:0]  vl4_base_col;    // 0, 2, 4, or 6

    always @(*) begin
        if (lane_cfg == LANE8) begin
            vl_half  = vl_beat[2];
            vl_vlane = vl_beat[1:0];
        end else begin
            vl_half  = 1'b0;           // unused in LANE4
            vl_vlane = 2'd0;           // unused in LANE4
        end
        vl_col_base = vl_half ? 3'd4 : 3'd0;
        vl_row_lo   = {vl_vlane, 1'b0};          // 2*vlane (LANE8)
        vl_row_hi   = {vl_vlane, 1'b0} | 3'd1;   // 2*vlane + 1 (LANE8)

        // LANE4 decode
        vl4_base_row = {vl_beat[1], 1'b0};               // 0 or 2
        vl4_base_col = {vl_beat[2], vl_beat[0], 1'b0};   // 0, 2, 4, 6
    end

    // =========================================================================
    // Fresh-burst edge detection
    // =========================================================================
    wire fresh_burst = valid_in & ~prev_valid;

    // Effective write address: on fresh_burst, force row=0, sel=0 because
    // the NBA for wr_row/wr_sel hasn't taken effect yet this cycle.
    wire [2:0] wr_row_eff = fresh_burst ? 3'd0 : wr_row;
    wire       wr_sel_eff = fresh_burst ? 1'b0 : wr_sel;

    // =========================================================================
    // Write completion detection
    // =========================================================================
    wire wr_last_phy_lane8   = (mode == MODE_PHY)   & ~lane_cfg & valid_in &
                               (wr_row == 3'd7) & ~fresh_burst;
    wire wr_last_phy_lane4   = (mode == MODE_PHY)   &  lane_cfg & valid_in &
                               l4_beat & (wr_row == 3'd3) & ~fresh_burst;
    wire wr_last_vlane_lane8 = (mode == MODE_VLANE) & ~lane_cfg & valid_in &
                               (vl_beat == 3'd7) & ~fresh_burst;
    wire wr_last_vlane_lane4 = (mode == MODE_VLANE) &  lane_cfg & valid_in &
                               (vl_beat == 3'd7) & ~fresh_burst;
    wire wr_last = wr_last_phy_lane8   | wr_last_phy_lane4 |
                   wr_last_vlane_lane8 | wr_last_vlane_lane4;

    // =========================================================================
    // prev_valid register
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prev_valid <= 1'b0;
        end else begin
            prev_valid <= valid_in;
        end
    end

    // =========================================================================
    // Write path + state machine
    //
    // INIT_FILL : collect first fill into buf_0, no output.
    //   When buffer is full -> transition to STREAM, flip wr_sel, pulse rd_start.
    //
    // STREAM : ping-pong. Write to wr_sel buffer while reading from other.
    //   When current write buffer is full -> flip wr_sel, pulse rd_start.
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= INIT_FILL;
            wr_sel   <= 1'b0;
            wr_row   <= 3'd0;
            l4_beat  <= 1'b0;
            vl_beat  <= 3'd0;
            rd_start <= 1'b0;
            for (i = 0; i < 8; i = i + 1) begin
                for (j = 0; j < 8; j = j + 1) begin
                    buf_0[i][j] <= {DATA_W{1'b0}};
                    buf_1[i][j] <= {DATA_W{1'b0}};
                end
            end
        end else begin
            rd_start <= 1'b0;   // default: one-cycle pulse

            // --- Fresh burst: reset to INIT_FILL ---
            if (fresh_burst) begin
                state   <= INIT_FILL;
                wr_sel  <= 1'b0;
                wr_row  <= 3'd0;
                l4_beat <= 1'b0;
                vl_beat <= 3'd0;
            end else begin
                state   <= state;
                wr_sel  <= wr_sel;
                wr_row  <= wr_row;
                l4_beat <= l4_beat;
                vl_beat <= vl_beat;
            end

            // --- Write data ---
            // On fresh_burst, wr_sel/wr_row NBA haven't taken effect yet.
            // Use wr_row_eff/wr_sel_eff so the first chunk lands at row 0, buf 0.
            if (valid_in) begin
                if (mode == MODE_PHY) begin
                    if (lane_cfg == LANE8) begin
                        // LANE8 PHY: write full row per beat
                        if (wr_sel_eff) begin
                            buf_1[wr_row_eff][0] <= din_top0;
                            buf_1[wr_row_eff][1] <= din_top1;
                            buf_1[wr_row_eff][2] <= din_top2;
                            buf_1[wr_row_eff][3] <= din_top3;
                            buf_1[wr_row_eff][4] <= din_bot0;
                            buf_1[wr_row_eff][5] <= din_bot1;
                            buf_1[wr_row_eff][6] <= din_bot2;
                            buf_1[wr_row_eff][7] <= din_bot3;
                        end else begin
                            buf_0[wr_row_eff][0] <= din_top0;
                            buf_0[wr_row_eff][1] <= din_top1;
                            buf_0[wr_row_eff][2] <= din_top2;
                            buf_0[wr_row_eff][3] <= din_top3;
                            buf_0[wr_row_eff][4] <= din_bot0;
                            buf_0[wr_row_eff][5] <= din_bot1;
                            buf_0[wr_row_eff][6] <= din_bot2;
                            buf_0[wr_row_eff][7] <= din_bot3;
                        end

                        if (fresh_burst) begin
                            wr_row <= 3'd1;
                        end else if (wr_row == 3'd7) begin
                            // Buffer full: flip and trigger read
                            wr_sel   <= ~wr_sel;
                            wr_row   <= 3'd0;
                            rd_start <= 1'b1;
                            if (state == INIT_FILL) begin
                                state <= STREAM;
                            end else begin
                                state <= state;  // hold
                            end
                        end else begin
                            wr_row <= wr_row + 3'd1;
                        end
                    end else begin
                        // LANE4 PHY: two beats per row (first half / second half)
                        if (fresh_burst) begin
                            // First beat of new burst: write top half of row 0
                            if (wr_sel_eff == 1'b0) begin
                                buf_0[0][0] <= din_top0;
                                buf_0[0][1] <= din_top1;
                                buf_0[0][2] <= din_top2;
                                buf_0[0][3] <= din_top3;
                            end else begin
                                buf_1[0][0] <= din_top0;
                                buf_1[0][1] <= din_top1;
                                buf_1[0][2] <= din_top2;
                                buf_1[0][3] <= din_top3;
                            end
                            l4_beat <= 1'b1;
                            wr_row  <= 3'd0;
                        end else if (l4_beat == 1'b0) begin
                            // First beat of row: write cols [0:3]
                            if (wr_sel_eff == 1'b0) begin
                                buf_0[wr_row_eff][0] <= din_top0;
                                buf_0[wr_row_eff][1] <= din_top1;
                                buf_0[wr_row_eff][2] <= din_top2;
                                buf_0[wr_row_eff][3] <= din_top3;
                            end else begin
                                buf_1[wr_row_eff][0] <= din_top0;
                                buf_1[wr_row_eff][1] <= din_top1;
                                buf_1[wr_row_eff][2] <= din_top2;
                                buf_1[wr_row_eff][3] <= din_top3;
                            end
                            l4_beat <= 1'b1;
                        end else begin
                            // Second beat of row: write cols [4:7]
                            if (wr_sel_eff == 1'b0) begin
                                buf_0[wr_row_eff][4] <= din_top0;
                                buf_0[wr_row_eff][5] <= din_top1;
                                buf_0[wr_row_eff][6] <= din_top2;
                                buf_0[wr_row_eff][7] <= din_top3;
                            end else begin
                                buf_1[wr_row_eff][4] <= din_top0;
                                buf_1[wr_row_eff][5] <= din_top1;
                                buf_1[wr_row_eff][6] <= din_top2;
                                buf_1[wr_row_eff][7] <= din_top3;
                            end
                            l4_beat <= 1'b0;
                            if (wr_row == 3'd3) begin
                                // Buffer full (4 rows): flip and trigger read
                                wr_sel   <= ~wr_sel;
                                wr_row   <= 3'd0;
                                rd_start <= 1'b1;
                                if (state == INIT_FILL) begin
                                    state <= STREAM;
                                end else begin
                                    state <= state;  // hold
                                end
                            end else begin
                                wr_row <= wr_row + 3'd1;
                            end
                        end
                    end
                end else if (lane_cfg == LANE8) begin
                    // ============================================================
                    // MODE_VLANE LANE8 write path (8 beats/buffer, 8 samples/beat)
                    //
                    // Chunk layout for current beat:
                    //   chunk[0] = din_top0   chunk[1] = din_top1
                    //   chunk[2] = din_top2   chunk[3] = din_top3
                    //   chunk[4] = din_bot0   chunk[5] = din_bot1
                    //   chunk[6] = din_bot2   chunk[7] = din_bot3
                    //
                    // Split into two physical lanes:
                    //   row 2*vlane    (=vl_row_lo) gets chunk[0,2,4,6]
                    //   row 2*vlane+1  (=vl_row_hi) gets chunk[1,3,5,7]
                    // Columns vl_col_base..vl_col_base+3.
                    // ============================================================
                    if (wr_sel_eff == 1'b0) begin
                        buf_0[vl_row_lo][vl_col_base + 3'd0] <= din_top0;  // chunk[0]
                        buf_0[vl_row_lo][vl_col_base + 3'd1] <= din_top2;  // chunk[2]
                        buf_0[vl_row_lo][vl_col_base + 3'd2] <= din_bot0;  // chunk[4]
                        buf_0[vl_row_lo][vl_col_base + 3'd3] <= din_bot2;  // chunk[6]
                        buf_0[vl_row_hi][vl_col_base + 3'd0] <= din_top1;  // chunk[1]
                        buf_0[vl_row_hi][vl_col_base + 3'd1] <= din_top3;  // chunk[3]
                        buf_0[vl_row_hi][vl_col_base + 3'd2] <= din_bot1;  // chunk[5]
                        buf_0[vl_row_hi][vl_col_base + 3'd3] <= din_bot3;  // chunk[7]
                    end else begin
                        buf_1[vl_row_lo][vl_col_base + 3'd0] <= din_top0;
                        buf_1[vl_row_lo][vl_col_base + 3'd1] <= din_top2;
                        buf_1[vl_row_lo][vl_col_base + 3'd2] <= din_bot0;
                        buf_1[vl_row_lo][vl_col_base + 3'd3] <= din_bot2;
                        buf_1[vl_row_hi][vl_col_base + 3'd0] <= din_top1;
                        buf_1[vl_row_hi][vl_col_base + 3'd1] <= din_top3;
                        buf_1[vl_row_hi][vl_col_base + 3'd2] <= din_bot1;
                        buf_1[vl_row_hi][vl_col_base + 3'd3] <= din_bot3;
                    end

                    // Advance beat counter / detect buffer full
                    if (fresh_burst) begin
                        vl_beat <= 3'd1;
                    end else if (vl_beat == 3'd7) begin
                        wr_sel   <= ~wr_sel;
                        vl_beat  <= 3'd0;
                        rd_start <= 1'b1;
                        if (state == INIT_FILL) begin
                            state <= STREAM;
                        end else begin
                            state <= state;
                        end
                    end else begin
                        vl_beat <= vl_beat + 3'd1;
                    end
                end else begin
                    // ============================================================
                    // MODE_VLANE LANE4 write path (8 beats/buffer, 4 samples/beat)
                    //
                    // Upstream emits each 4-cycle vlane chunk as 2 half-beats of
                    // 4 samples on din_top0..3 (din_bot* = 0, not used). Each beat
                    // carries data for one vlane across 2 input cycles:
                    //   din_top0 = L_even @ cycle_even  (lane 2*vlane,   cycle a)
                    //   din_top1 = L_odd  @ cycle_even  (lane 2*vlane+1, cycle a)
                    //   din_top2 = L_even @ cycle_odd   (lane 2*vlane,   cycle b)
                    //   din_top3 = L_odd  @ cycle_odd   (lane 2*vlane+1, cycle b)
                    //
                    // Beat ordering (8 beats per buffer, covers 8 input cycles):
                    //   beat[2] = super-group (0: input cycles 0-3,
                    //                          1: input cycles 4-7)
                    //   beat[1] = vlane (0 -> rows 0,1; 1 -> rows 2,3)
                    //   beat[0] = half  (0: cycles a,b = first pair;
                    //                    1: cycles a,b = second pair)
                    //
                    // Target cells:
                    //   buf[base_row  ][base_col  ] <= din_top0
                    //   buf[base_row+1][base_col  ] <= din_top1
                    //   buf[base_row  ][base_col+1] <= din_top2
                    //   buf[base_row+1][base_col+1] <= din_top3
                    //
                    // base_row = {beat[1], 1'b0}               (0 or 2)
                    // base_col = {beat[2], beat[0], 1'b0}      (0, 2, 4, 6)
                    //
                    // Rows 4..7 are zero-filled (only 2 vlanes are active).
                    // ============================================================
                    if (wr_sel_eff == 1'b0) begin
                        buf_0[vl4_base_row        ][vl4_base_col        ] <= din_top0;
                        buf_0[vl4_base_row | 3'd1 ][vl4_base_col        ] <= din_top1;
                        buf_0[vl4_base_row        ][vl4_base_col | 3'd1 ] <= din_top2;
                        buf_0[vl4_base_row | 3'd1 ][vl4_base_col | 3'd1 ] <= din_top3;
                    end else begin
                        buf_1[vl4_base_row        ][vl4_base_col        ] <= din_top0;
                        buf_1[vl4_base_row | 3'd1 ][vl4_base_col        ] <= din_top1;
                        buf_1[vl4_base_row        ][vl4_base_col | 3'd1 ] <= din_top2;
                        buf_1[vl4_base_row | 3'd1 ][vl4_base_col | 3'd1 ] <= din_top3;
                    end

                    // Zero-fill rows 4..7 on the first beat of each fill so that
                    // dout4..7 are 0 (only 4 physical lanes exist in LANE4).
                    if (vl_beat == 3'd0) begin
                        for (i = 4; i < 8; i = i + 1) begin
                            for (j = 0; j < 8; j = j + 1) begin
                                if (wr_sel_eff == 1'b0) begin
                                    buf_0[i][j] <= {DATA_W{1'b0}};
                                end else begin
                                    buf_1[i][j] <= {DATA_W{1'b0}};
                                end
                            end
                        end
                    end

                    // Advance beat counter / detect buffer full (8 beats per buf)
                    if (fresh_burst) begin
                        vl_beat <= 3'd1;
                    end else if (vl_beat == 3'd7) begin
                        wr_sel   <= ~wr_sel;
                        vl_beat  <= 3'd0;
                        rd_start <= 1'b1;
                        if (state == INIT_FILL) begin
                            state <= STREAM;
                        end else begin
                            state <= state;
                        end
                    end else begin
                        vl_beat <= vl_beat + 3'd1;
                    end
                end
            end

            // --- Partial flush: valid drops before buffer is full (STREAM only) ---
            if (state == STREAM && prev_valid && !valid_in &&
                ((mode == MODE_PHY   && (wr_row != 3'd0 || l4_beat)) ||
                 (mode == MODE_VLANE &&  vl_beat != 3'd0))) begin
                if (mode == MODE_PHY) begin
                    if (lane_cfg == LANE8) begin
                        // Zero-fill remaining rows
                        for (i = 0; i < 8; i = i + 1) begin
                            if (i[2:0] >= wr_row) begin
                                for (j = 0; j < 8; j = j + 1) begin
                                    if (wr_sel_eff == 1'b0) begin
                                        buf_0[i][j] <= {DATA_W{1'b0}};
                                    end else begin
                                        buf_1[i][j] <= {DATA_W{1'b0}};
                                    end
                                end
                            end else begin
                                // keep
                            end
                        end
                    end else begin
                        // LANE4 PHY: zero-fill remaining rows (rows >= wr_row or >= 4)
                        for (i = 0; i < 8; i = i + 1) begin
                            if (i[2:0] >= wr_row || i[2:0] >= 3'd4) begin
                                for (j = 0; j < 8; j = j + 1) begin
                                    if (wr_sel_eff == 1'b0) begin
                                        buf_0[i][j] <= {DATA_W{1'b0}};
                                    end else begin
                                        buf_1[i][j] <= {DATA_W{1'b0}};
                                    end
                                end
                            end else begin
                                // keep
                            end
                        end
                    end
                end else begin
                    // MODE_VLANE partial flush: simplest is to zero-fill the entire
                    // target buffer (we don't know which rows/cols were partially
                    // written). Safe because any unfilled position is undefined
                    // data anyway.
                    for (i = 0; i < 8; i = i + 1) begin
                        for (j = 0; j < 8; j = j + 1) begin
                            if (wr_sel_eff == 1'b0) begin
                                buf_0[i][j] <= {DATA_W{1'b0}};
                            end else begin
                                buf_1[i][j] <= {DATA_W{1'b0}};
                            end
                        end
                    end
                end
                wr_sel   <= ~wr_sel;
                wr_row   <= 3'd0;
                l4_beat  <= 1'b0;
                vl_beat  <= 3'd0;
                rd_start <= 1'b1;
            end else begin
                // no flush
            end
        end
    end

    // =========================================================================
    // Read path: column-wise read = transpose output
    //
    // Only active in STREAM state. Triggered by rd_start pulse.
    // Uses rd_sel to capture which buffer to read from.
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_sel    <= 1'b0;
            reading   <= 1'b0;
            rd_col    <= 3'd0;
            valid_out <= 1'b0;
            for (i = 0; i < 8; i = i + 1) begin
                rd_data[i] <= {DATA_W{1'b0}};
            end
        end else begin
            if (fresh_burst) begin
                // Fresh burst kills any ongoing read
                reading   <= 1'b0;
                valid_out <= 1'b0;
            end else if (rd_start) begin
                // Start reading the just-completed buffer
                rd_sel    <= ~wr_sel;
                reading   <= 1'b1;
                rd_col    <= 3'd0;
                valid_out <= 1'b1;
                // First column read (col 0)
                for (i = 0; i < 8; i = i + 1) begin
                    if (wr_sel == 1'b1) begin
                        rd_data[i] <= buf_0[i][0];
                    end else begin
                        rd_data[i] <= buf_1[i][0];
                    end
                end
            end else if (reading) begin
                if (rd_col == 3'd7) begin
                    // Last column done
                    reading   <= 1'b0;
                    valid_out <= 1'b0;
                end else begin
                    rd_col    <= rd_col + 3'd1;
                    valid_out <= 1'b1;
                    for (i = 0; i < 8; i = i + 1) begin
                        if (rd_sel == 1'b0) begin
                            rd_data[i] <= buf_0[i][rd_col + 1];
                        end else begin
                            rd_data[i] <= buf_1[i][rd_col + 1];
                        end
                    end
                end
            end else begin
                valid_out <= 1'b0;
            end
        end
    end

    // =========================================================================
    // Output assignments
    // =========================================================================
    assign dout0 = rd_data[0];
    assign dout1 = rd_data[1];
    assign dout2 = rd_data[2];
    assign dout3 = rd_data[3];
    assign dout4 = rd_data[4];
    assign dout5 = rd_data[5];
    assign dout6 = rd_data[6];
    assign dout7 = rd_data[7];

endmodule
