`timescale 1ns/1ps

// =============================================================================
// inplace_transpose_buf_8lane_2beat  (ping-pong rewrite, Step A)
// =============================================================================
// Externally bit-identical to the legacy phy_acc + fifo_mem implementation:
// port list, widths, and cycle-by-cycle dout_top/dout_bot/valid_out behavior
// are locked. Internally the 16-row fifo_mem is replaced by a 2x8-row
// ping-pong bank pair. phy_acc / vl_acc remain as per-column accumulators
// until the current chunk is committed into bank[wr_bank].
//
// Coding style (Verilog-2001):
//   - One always block per related signal group. No single mega-always.
//   - Two-process FSM: sequential always only does `reg <= reg_d`; all
//     decision logic lives in a comb always that drives `reg_d`.
//   - No leading default values inside a shared always; every branch
//     lists the value explicitly.
//   - For a signal that owns its own always, the always only enumerates
//     the conditions that actually update it (no forced else).
//   - Async-low reset on every sequential always.
//   - Block labels on every labeled always for waveform scope clarity.
// =============================================================================

module inplace_transpose_buf_8lane_2beat (
    clk, rst_n, valid_in, lane_cfg, mode,
    din0, din1, din2, din3, din4, din5, din6, din7,
    valid_out,
    dout_top0, dout_top1, dout_top2, dout_top3,
    dout_bot0, dout_bot1, dout_bot2, dout_bot3
);

    parameter DATA_W = 8;

    input                 clk;
    input                 rst_n;
    input                 valid_in;
    input                 lane_cfg;
    input  [1:0]          mode;
    input  [DATA_W-1:0]   din0, din1, din2, din3, din4, din5, din6, din7;
    output reg            valid_out;
    output [DATA_W-1:0]   dout_top0, dout_top1, dout_top2, dout_top3;
    output [DATA_W-1:0]   dout_bot0, dout_bot1, dout_bot2, dout_bot3;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    localparam       LANE8       = 1'b0;
    localparam       LANE4       = 1'b1;
    localparam [1:0] MODE_PHY    = 2'b00;
    localparam [1:0] MODE_VLANE  = 2'b01;

    // Read FSM encoding
    localparam [1:0] R_IDLE      = 2'd0;  // no bank ready to drain
    localparam [1:0] R_DRAIN     = 2'd1;  // LANE8: 1 row/cycle; LANE4 beat-0
    localparam [1:0] R_L4_BT1    = 2'd2;  // LANE4 only: emit beat 1 (bot half)

    // -------------------------------------------------------------------------
    // Input fan-out (combinational lane packing)
    // -------------------------------------------------------------------------
    reg [DATA_W-1:0] din_r [0:7];
    always @(*) begin : p_din_pack
        din_r[0] = din0;
        din_r[1] = din1;
        din_r[2] = din2;
        din_r[3] = din3;
        din_r[4] = din4;
        din_r[5] = din5;
        din_r[6] = din6;
        din_r[7] = din7;
    end

    // active lane/vlane counts (combinational, cheap)
    wire [3:0] active_lanes  = (lane_cfg == LANE8) ? 4'd8 : 4'd4;
    wire [3:0] active_vlanes = (lane_cfg == LANE8) ? 4'd4 : 4'd2;

    // -------------------------------------------------------------------------
    // Fresh-burst detection: prev_valid + fresh_burst pulse
    // -------------------------------------------------------------------------
    reg prev_valid;
    always @(posedge clk or negedge rst_n) begin : p_prev_valid
        if (!rst_n) prev_valid <= 1'b0;
        else        prev_valid <= valid_in;
    end
    wire fresh_burst = valid_in & ~prev_valid;

    // =========================================================================
    // WRITE SIDE
    // =========================================================================
    // Write side is a simple phase counter plus a VLANE warm-up flag. There
    // is no write FSM per se: phase_cnt wraps on its mode-dependent max and
    // that is when a chunk is committed into bank[wr_bank].
    // -------------------------------------------------------------------------

    reg [2:0] phase_cnt;
    reg [2:0] phase_cnt_d;
    reg       init_done_4vlane;
    reg       init_done_4vlane_d;

    wire phase_max_hit = (mode == MODE_PHY)
                       ? (phase_cnt == 3'd7)
                       : (phase_cnt[1:0] == 2'd3);
    wire chunk_commit  = valid_in & phase_max_hit;

    // phase_cnt next-state. No fresh_burst override: the last completed burst
    // leaves phase_cnt at 0 (chunks always end on phase wrap). A fresh burst
    // therefore begins with phase_cnt == 0 and advances normally from here.
    always @(*) begin : p_phase_cnt_d
        if (valid_in && mode == MODE_PHY) begin
            if (phase_cnt == 3'd7)                     phase_cnt_d = 3'd0;
            else                                       phase_cnt_d = phase_cnt + 3'd1;
        end
        else if (valid_in && mode == MODE_VLANE) begin
            if (phase_cnt[1:0] == 2'd3)                phase_cnt_d = 3'd0;
            else                                       phase_cnt_d = phase_cnt + 3'd1;
        end
        else                                           phase_cnt_d = phase_cnt;
    end

    always @(posedge clk or negedge rst_n) begin : p_phase_cnt
        if (!rst_n) phase_cnt <= 3'd0;
        else        phase_cnt <= phase_cnt_d;
    end

    // init_done_4vlane: VLANE warm-up flag. Set when first VLANE chunk
    // commits; stays set for the rest of the burst. Cleared on fresh burst.
    always @(*) begin : p_init_done_d
        if (fresh_burst)                                          init_done_4vlane_d = 1'b0;
        else if (chunk_commit && mode == MODE_VLANE)              init_done_4vlane_d = 1'b1;
        else                                                      init_done_4vlane_d = init_done_4vlane;
    end

    always @(posedge clk or negedge rst_n) begin : p_init_done
        if (!rst_n) init_done_4vlane <= 1'b0;
        else        init_done_4vlane <= init_done_4vlane_d;
    end

    // phy_acc[lane][phase]: column accumulator for PHY mode
    reg [DATA_W-1:0] phy_acc [0:7][0:7];
    integer i_phy, j_phy;
    always @(posedge clk or negedge rst_n) begin : p_phy_acc
        if (!rst_n) begin
            for (i_phy = 0; i_phy < 8; i_phy = i_phy + 1)
                for (j_phy = 0; j_phy < 8; j_phy = j_phy + 1)
                    phy_acc[i_phy][j_phy] <= {DATA_W{1'b0}};
        end else if (valid_in && mode == MODE_PHY) begin
            for (i_phy = 0; i_phy < 8; i_phy = i_phy + 1)
                if (i_phy < active_lanes)
                    phy_acc[i_phy][phase_cnt] <= din_r[i_phy];
        end
    end

    // vl_acc[vlane][slot]: column accumulator for VLANE mode
    reg [DATA_W-1:0] vl_acc [0:3][0:7];
    integer i_vl, j_vl;
    wire [2:0] vlane_base_idx = {phase_cnt[1:0], 1'b0};
    always @(posedge clk or negedge rst_n) begin : p_vl_acc
        if (!rst_n) begin
            for (i_vl = 0; i_vl < 4; i_vl = i_vl + 1)
                for (j_vl = 0; j_vl < 8; j_vl = j_vl + 1)
                    vl_acc[i_vl][j_vl] <= {DATA_W{1'b0}};
        end else if (valid_in && mode == MODE_VLANE) begin
            for (i_vl = 0; i_vl < 4; i_vl = i_vl + 1) begin
                if (i_vl < active_vlanes) begin
                    vl_acc[i_vl][vlane_base_idx]         <= din_r[2*i_vl];
                    vl_acc[i_vl][vlane_base_idx + 3'd1]  <= din_r[2*i_vl + 1];
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // Ping-pong banks: bank[sel][row][slot]
    // On chunk_commit, write active_lanes (PHY) or active_vlanes (VLANE)
    // rows into bank[wr_bank]. Each row combines the accumulator head
    // (first N-2 slots) with the current-cycle din_r at the tail slots.
    // -------------------------------------------------------------------------
    reg [DATA_W-1:0] bank [0:1][0:7][0:7];
    integer i_bk, j_bk, k_bk;

    reg wr_bank;
    reg wr_bank_d;

    always @(posedge clk or negedge rst_n) begin : p_bank_write
        if (!rst_n) begin
            for (i_bk = 0; i_bk < 2; i_bk = i_bk + 1)
                for (j_bk = 0; j_bk < 8; j_bk = j_bk + 1)
                    for (k_bk = 0; k_bk < 8; k_bk = k_bk + 1)
                        bank[i_bk][j_bk][k_bk] <= {DATA_W{1'b0}};
        end else if (chunk_commit && mode == MODE_PHY) begin
            for (i_bk = 0; i_bk < 8; i_bk = i_bk + 1) begin
                if (i_bk < active_lanes) begin
                    for (j_bk = 0; j_bk < 7; j_bk = j_bk + 1)
                        bank[wr_bank][i_bk][j_bk] <= phy_acc[i_bk][j_bk];
                    bank[wr_bank][i_bk][7] <= din_r[i_bk];
                end
            end
        end else if (chunk_commit && mode == MODE_VLANE) begin
            for (i_bk = 0; i_bk < 4; i_bk = i_bk + 1) begin
                if (i_bk < active_vlanes) begin
                    for (j_bk = 0; j_bk < 6; j_bk = j_bk + 1)
                        bank[wr_bank][i_bk][j_bk] <= vl_acc[i_bk][j_bk];
                    bank[wr_bank][i_bk][6] <= din_r[2*i_bk];
                    bank[wr_bank][i_bk][7] <= din_r[2*i_bk + 1];
                end
            end
        end
    end

    // wr_bank: toggles every chunk commit
    always @(*) begin : p_wr_bank_d
        if (fresh_burst)       wr_bank_d = 1'b0;
        else if (chunk_commit) wr_bank_d = ~wr_bank;
        else                   wr_bank_d = wr_bank;
    end

    always @(posedge clk or negedge rst_n) begin : p_wr_bank
        if (!rst_n) wr_bank <= 1'b0;
        else        wr_bank <= wr_bank_d;
    end

    // =========================================================================
    // READ SIDE
    // =========================================================================
    // Two-process FSM. Sequential always just does state <= r_state_d.
    // Read path issues 1 row/cycle on LANE8, 2 beats/row on LANE4. The
    // R_DRAIN state emits beat 0 (or the sole LANE8 beat); R_L4_BT1 emits
    // the LANE4 beat 1.
    // -------------------------------------------------------------------------

    reg [1:0] r_state;
    reg [1:0] r_state_d;

    reg       rd_bank;
    reg       rd_bank_d;
    reg [3:0] bank_row_rd;
    reg [3:0] bank_row_rd_d;

    // VLANE warm-up guard: in VLANE mode, reader cannot leave IDLE until the
    // second chunk's commit has fired (init_done_4vlane_d captures the "this
    // cycle saw the second commit" condition).
    wire read_allowed = (mode == MODE_PHY) | init_done_4vlane;

    // Whether the current row being emitted is the last row of rd_bank.
    wire last_row_of_bank = (bank_row_rd + 4'd1 == bank_rows_used[rd_bank]);

    // FSM next-state
    always @(*) begin : p_r_state_d
        case (r_state)
            R_IDLE: begin
                if (bank_full[rd_bank] & read_allowed) r_state_d = R_DRAIN;
                else                                   r_state_d = R_IDLE;
            end
            R_DRAIN: begin
                if (lane_cfg == LANE8) begin
                    // LANE8: stay in DRAIN as long as data remains
                    if (last_row_of_bank && !bank_full_after_drain_complete)
                                                       r_state_d = R_IDLE;
                    else                               r_state_d = R_DRAIN;
                end else begin
                    // LANE4: every DRAIN cycle hands off to BT1 next cycle
                                                       r_state_d = R_L4_BT1;
                end
            end
            R_L4_BT1: begin
                // After emitting beat 1, decide whether more rows follow
                if (l4_more_rows_available)            r_state_d = R_DRAIN;
                else                                   r_state_d = R_IDLE;
            end
            default:                                   r_state_d = R_IDLE;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin : p_r_state
        if (!rst_n) r_state <= R_IDLE;
        else        r_state <= r_state_d;
    end

    // -------------------------------------------------------------------------
    // Read pointers: rd_bank and bank_row_rd
    // rd_bank toggles when we finish draining the current bank; bank_row_rd
    // advances every accepted row on LANE8, and every R_L4_BT1 (row boundary)
    // on LANE4.
    // -------------------------------------------------------------------------
    wire row_advance_lane8 = (r_state == R_DRAIN) && (lane_cfg == LANE8);
    wire row_advance_lane4 = (r_state == R_L4_BT1);
    wire row_advance       = row_advance_lane8 | row_advance_lane4;

    wire bank_finish       = row_advance & last_row_of_bank;

    always @(*) begin : p_rd_bank_d
        if (fresh_burst)     rd_bank_d = 1'b0;
        else if (bank_finish) rd_bank_d = ~rd_bank;
        else                 rd_bank_d = rd_bank;
    end

    always @(posedge clk or negedge rst_n) begin : p_rd_bank
        if (!rst_n) rd_bank <= 1'b0;
        else        rd_bank <= rd_bank_d;
    end

    always @(*) begin : p_bank_row_rd_d
        if (fresh_burst)         bank_row_rd_d = 4'd0;
        else if (bank_finish)    bank_row_rd_d = 4'd0;
        else if (row_advance)    bank_row_rd_d = bank_row_rd + 4'd1;
        else                     bank_row_rd_d = bank_row_rd;
    end

    always @(posedge clk or negedge rst_n) begin : p_bank_row_rd
        if (!rst_n) bank_row_rd <= 4'd0;
        else        bank_row_rd <= bank_row_rd_d;
    end

    // -------------------------------------------------------------------------
    // bank_full[0..1] + bank_rows_used[0..1]
    // Writer SET fires on chunk_commit targeting wr_bank.
    // Reader CLR fires on bank_finish targeting rd_bank.
    // Same-cycle set-wins-over-clear (guarantees a freshly committed chunk
    // is never erased by a coincident drain-complete on the opposite bank).
    // -------------------------------------------------------------------------
    reg        bank_full      [0:1];
    reg [3:0]  bank_rows_used [0:1];

    wire       wr_set_b0      = chunk_commit & (wr_bank == 1'b0);
    wire       wr_set_b1      = chunk_commit & (wr_bank == 1'b1);
    wire [3:0] wr_rows_commit = (mode == MODE_PHY) ? active_lanes : active_vlanes;
    wire       rd_clr_b0      = bank_finish & (rd_bank == 1'b0);
    wire       rd_clr_b1      = bank_finish & (rd_bank == 1'b1);

    always @(posedge clk or negedge rst_n) begin : p_bank_full_0
        if (!rst_n)           bank_full[0] <= 1'b0;
        else if (fresh_burst) bank_full[0] <= 1'b0;
        else if (wr_set_b0)   bank_full[0] <= 1'b1;
        else if (rd_clr_b0)   bank_full[0] <= 1'b0;
    end

    always @(posedge clk or negedge rst_n) begin : p_bank_full_1
        if (!rst_n)           bank_full[1] <= 1'b0;
        else if (fresh_burst) bank_full[1] <= 1'b0;
        else if (wr_set_b1)   bank_full[1] <= 1'b1;
        else if (rd_clr_b1)   bank_full[1] <= 1'b0;
    end

    always @(posedge clk or negedge rst_n) begin : p_bank_rows_used_0
        if (!rst_n)           bank_rows_used[0] <= 4'd0;
        else if (fresh_burst) bank_rows_used[0] <= 4'd0;
        else if (wr_set_b0)   bank_rows_used[0] <= wr_rows_commit;
        else if (rd_clr_b0)   bank_rows_used[0] <= 4'd0;
    end

    always @(posedge clk or negedge rst_n) begin : p_bank_rows_used_1
        if (!rst_n)           bank_rows_used[1] <= 4'd0;
        else if (fresh_burst) bank_rows_used[1] <= 4'd0;
        else if (wr_set_b1)   bank_rows_used[1] <= wr_rows_commit;
        else if (rd_clr_b1)   bank_rows_used[1] <= 4'd0;
    end

    // Helper: does the other bank hold data the reader could continue with
    // after finishing the current bank? Used by FSM and LANE4 to decide
    // whether to return to IDLE or stay in DRAIN after a bank transition.
    wire bank_full_after_drain_complete = bank_full[~rd_bank];
    wire l4_more_rows_available         = (!last_row_of_bank)
                                          | bank_full_after_drain_complete;

    // =========================================================================
    // Output path: dout_top / dout_bot / valid_out / cur_chunk
    // =========================================================================
    // All output registers are produced in R_DRAIN (1st beat) and, for LANE4,
    // R_L4_BT1 (2nd beat). cur_chunk latches the current row on LANE4 so
    // beat 1 can emit the bottom half without re-reading bank[].
    // -------------------------------------------------------------------------
    reg [DATA_W-1:0] dout_top [0:3];
    reg [DATA_W-1:0] dout_bot [0:3];
    reg [DATA_W-1:0] cur_chunk [0:7];
    integer i_out;

    assign dout_top0 = dout_top[0];
    assign dout_top1 = dout_top[1];
    assign dout_top2 = dout_top[2];
    assign dout_top3 = dout_top[3];
    assign dout_bot0 = dout_bot[0];
    assign dout_bot1 = dout_bot[1];
    assign dout_bot2 = dout_bot[2];
    assign dout_bot3 = dout_bot[3];

    // valid_out: high for the beat that carries R_DRAIN/R_L4_BT1 data.
    // Uses current r_state (same timing as legacy: output register updates
    // on the same edge that sets valid_out).
    always @(posedge clk or negedge rst_n) begin : p_valid_out
        if (!rst_n)                     valid_out <= 1'b0;
        else if (r_state == R_DRAIN)    valid_out <= 1'b1;
        else if (r_state == R_L4_BT1)   valid_out <= 1'b1;
        else                            valid_out <= 1'b0;
    end

    // dout_top / dout_bot
    // LANE8: from bank[rd_bank][bank_row_rd] — top = lanes 0..3, bot = 4..7
    // LANE4 beat 0 (R_DRAIN):  top = bank[row][0..3], bot = 0
    // LANE4 beat 1 (R_L4_BT1): top = cur_chunk[4..7], bot = 0
    always @(posedge clk or negedge rst_n) begin : p_dout
        if (!rst_n) begin
            for (i_out = 0; i_out < 4; i_out = i_out + 1) begin
                dout_top[i_out] <= {DATA_W{1'b0}};
                dout_bot[i_out] <= {DATA_W{1'b0}};
            end
        end else if ((r_state == R_DRAIN) && (lane_cfg == LANE8)) begin
            for (i_out = 0; i_out < 4; i_out = i_out + 1) begin
                dout_top[i_out] <= bank[rd_bank][bank_row_rd][i_out];
                dout_bot[i_out] <= bank[rd_bank][bank_row_rd][4 + i_out];
            end
        end else if ((r_state == R_DRAIN) && (lane_cfg == LANE4)) begin
            for (i_out = 0; i_out < 4; i_out = i_out + 1) begin
                dout_top[i_out] <= bank[rd_bank][bank_row_rd][i_out];
                dout_bot[i_out] <= {DATA_W{1'b0}};
            end
        end else if (r_state == R_L4_BT1) begin
            for (i_out = 0; i_out < 4; i_out = i_out + 1) begin
                dout_top[i_out] <= cur_chunk[4 + i_out];
                dout_bot[i_out] <= {DATA_W{1'b0}};
            end
        end else begin
            for (i_out = 0; i_out < 4; i_out = i_out + 1) begin
                dout_top[i_out] <= {DATA_W{1'b0}};
                dout_bot[i_out] <= {DATA_W{1'b0}};
            end
        end
    end

    // cur_chunk: latch current row on LANE4 R_DRAIN for beat-1 reuse.
    integer i_cc;
    always @(posedge clk or negedge rst_n) begin : p_cur_chunk
        if (!rst_n) begin
            for (i_cc = 0; i_cc < 8; i_cc = i_cc + 1)
                cur_chunk[i_cc] <= {DATA_W{1'b0}};
        end else if ((r_state == R_DRAIN) && (lane_cfg == LANE4)) begin
            for (i_cc = 0; i_cc < 8; i_cc = i_cc + 1)
                cur_chunk[i_cc] <= bank[rd_bank][bank_row_rd][i_cc];
        end
    end

endmodule
