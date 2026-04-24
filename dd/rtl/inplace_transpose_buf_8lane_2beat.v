`timescale 1ns/1ps

// Ping-pong rewrite (Step A):
//   External port list, widths, and cycle-by-cycle dout_top/dout_bot/valid_out
//   behavior are bit-identical to the legacy phy_acc+fifo_mem implementation.
//   Internally the 16-row fifo_mem is replaced by two banks of 8 rows each
//   (bank[2][8][8*DATA_W]); phy_acc/vl_acc stay because they accumulate the
//   current chunk column-by-column before it is committed into a bank row.
//
//   Storage before:  phy_acc 8x8 + vl_acc 4x8 + fifo_mem 16x8
//   Storage after :  phy_acc 8x8 + vl_acc 4x8 + bank    2x8x8
//
//   The bank pair acts as a 2-chunk ring buffer (produce/consume by chunk).
//   When a chunk is committed, bank_full[wr_bank] is SET; when the reader
//   finishes draining a bank, bank_full[rd_bank] is CLEARED. If a commit and
//   a drain-complete fire in the same cycle on the same bank (only possible
//   transiently when the reader is draining the current producer-target bank),
//   the SET wins - otherwise the newly committed chunk would be lost.

module inplace_transpose_buf_8lane_2beat (
    clk, rst_n, valid_in, lane_cfg, mode,
    din0, din1, din2, din3, din4, din5, din6, din7,
    valid_out,
    dout_top0, dout_top1, dout_top2, dout_top3,
    dout_bot0, dout_bot1, dout_bot2, dout_bot3
);

    parameter DATA_W = 8;

    input              clk, rst_n, valid_in;
    input              lane_cfg;
    input  [1:0]       mode;
    input  [DATA_W-1:0] din0, din1, din2, din3, din4, din5, din6, din7;
    output reg         valid_out;
    output [DATA_W-1:0] dout_top0, dout_top1, dout_top2, dout_top3;
    output [DATA_W-1:0] dout_bot0, dout_bot1, dout_bot2, dout_bot3;

    localparam LANE8      = 1'b0;
    localparam LANE4      = 1'b1;
    localparam [1:0] MODE_PHY   = 2'b00;
    localparam [1:0] MODE_VLANE = 2'b01;
    localparam [1:0] INIT_FILL  = 2'd0;
    localparam [1:0] STREAM     = 2'd1;

    // Per-column chunk accumulators (unchanged from legacy).
    reg [DATA_W-1:0] phy_acc  [0:7][0:7];
    reg [DATA_W-1:0] vl_acc   [0:3][0:7];

    // Ping-pong banks: 2 chunks x 8 rows x 8 lanes. Each committed chunk
    // occupies a contiguous region of one bank (rows 0..rows_used-1).
    reg [DATA_W-1:0] bank [0:1][0:7][0:7];

    // Bank-level producer/consumer state.
    reg        wr_bank;
    reg        rd_bank;
    reg [3:0]  bank_rows_used [0:1];
    reg [3:0]  bank_row_rd;
    reg        bank_full [0:1];

    reg [DATA_W-1:0] cur_chunk [0:7];
    reg [DATA_W-1:0] din_r [0:7];
    reg [DATA_W-1:0] dout_top [0:3];
    reg [DATA_W-1:0] dout_bot [0:3];

    reg [2:0] phase_cnt;
    reg [1:0] state;
    reg       init_done_4vlane;
    reg       lane4_chunk_valid;
    reg       lane4_second_beat;
    integer   base_idx, row_idx, active_lanes, active_vlanes;
    reg [2:0] phase_next;
    reg [1:0] state_next;
    reg       init_done_4vlane_next;
    reg       lane4_chunk_valid_next;
    reg       lane4_second_beat_next;

    // Scratch for same-cycle pointer updates.
    reg        wr_bank_tmp;
    reg        rd_bank_tmp;
    reg [3:0]  bank_row_rd_tmp;

    // Independent set/clear events per bank; set wins over clear.
    reg        wr_set [0:1];
    reg [3:0]  wr_rows_set [0:1];  // rows_used value written on set
    reg        rd_clr [0:1];

    reg       prev_valid;
    integer i, j, lane, vlane;

    always @(*) begin
        din_r[0] = din0; din_r[1] = din1; din_r[2] = din2; din_r[3] = din3;
        din_r[4] = din4; din_r[5] = din5; din_r[6] = din6; din_r[7] = din7;
    end
    assign dout_top0 = dout_top[0]; assign dout_top1 = dout_top[1];
    assign dout_top2 = dout_top[2]; assign dout_top3 = dout_top[3];
    assign dout_bot0 = dout_bot[0]; assign dout_bot1 = dout_bot[1];
    assign dout_bot2 = dout_bot[2]; assign dout_bot3 = dout_bot[3];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase_cnt <= 3'd0; state <= INIT_FILL;
            init_done_4vlane <= 1'b0;
            lane4_chunk_valid <= 1'b0; lane4_second_beat <= 1'b0;
            prev_valid <= 1'b0;
            valid_out <= 1'b0;
            wr_bank <= 1'b0; rd_bank <= 1'b0; bank_row_rd <= 4'd0;
            bank_rows_used[0] <= 4'd0; bank_rows_used[1] <= 4'd0;
            bank_full[0] <= 1'b0; bank_full[1] <= 1'b0;
            for (i = 0; i < 4; i = i + 1) begin
                dout_top[i] <= 0; dout_bot[i] <= 0;
            end
            for (i = 0; i < 8; i = i + 1)
                cur_chunk[i] <= 0;
            for (i = 0; i < 8; i = i + 1) begin
                for (j = 0; j < 8; j = j + 1) begin
                    phy_acc[i][j] <= 0;
                    bank[0][i][j] <= 0;
                    bank[1][i][j] <= 0;
                    if (i < 4) vl_acc[i][j] <= 0;
                end
            end
        end else begin
            phase_next = phase_cnt; state_next = state;
            init_done_4vlane_next = init_done_4vlane;
            lane4_chunk_valid_next = lane4_chunk_valid;
            lane4_second_beat_next = lane4_second_beat;
            active_lanes  = (lane_cfg == LANE8) ? 8 : 4;
            active_vlanes = (lane_cfg == LANE8) ? 4 : 2;

            wr_bank_tmp     = wr_bank;
            rd_bank_tmp     = rd_bank;
            bank_row_rd_tmp = bank_row_rd;
            wr_set[0] = 1'b0; wr_set[1] = 1'b0;
            rd_clr[0] = 1'b0; rd_clr[1] = 1'b0;
            wr_rows_set[0] = 4'd0;
            wr_rows_set[1] = 4'd0;

            valid_out <= 1'b0;
            for (i = 0; i < 4; i = i + 1) begin
                dout_top[i] <= 0; dout_bot[i] <= 0;
            end

            if (valid_in && !prev_valid) begin
                // Fresh burst: soft reset (matches legacy)
                phase_next = 3'd0;
                state_next = INIT_FILL;
                init_done_4vlane_next = 1'b0;
                lane4_chunk_valid_next = 1'b0;
                lane4_second_beat_next = 1'b0;
                wr_bank_tmp = 1'b0; rd_bank_tmp = 1'b0;
                bank_row_rd_tmp = 4'd0;
                bank_full[0] <= 1'b0;
                bank_full[1] <= 1'b0;
                bank_rows_used[0] <= 4'd0;
                bank_rows_used[1] <= 4'd0;
            end

            // --- Write side: accumulate chunk, commit to wr_bank on phase wrap ---
            if (valid_in) begin
                if (mode == MODE_PHY) begin
                    for (lane = 0; lane < 8; lane = lane + 1)
                        if (lane < active_lanes)
                            phy_acc[lane][phase_cnt] <= din_r[lane];
                    if (phase_cnt == 3'd7) begin
                        for (lane = 0; lane < 8; lane = lane + 1) begin
                            if (lane < active_lanes) begin
                                for (j = 0; j < 7; j = j + 1)
                                    bank[wr_bank_tmp][lane][j] <= phy_acc[lane][j];
                                bank[wr_bank_tmp][lane][7] <= din_r[lane];
                            end
                        end
                        wr_set[wr_bank_tmp]      = 1'b1;
                        wr_rows_set[wr_bank_tmp] = active_lanes[3:0];
                        wr_bank_tmp              = ~wr_bank_tmp;
                        state_next = STREAM;
                        phase_next = 3'd0;
                    end else begin
                        phase_next = phase_cnt + 3'd1;
                    end
                end else begin
                    base_idx = {phase_cnt[1:0], 1'b0};
                    for (vlane = 0; vlane < 4; vlane = vlane + 1) begin
                        if (vlane < active_vlanes) begin
                            vl_acc[vlane][base_idx]     <= din_r[2 * vlane];
                            vl_acc[vlane][base_idx + 1] <= din_r[2 * vlane + 1];
                        end
                    end
                    if (phase_cnt[1:0] == 2'd3) begin
                        for (vlane = 0; vlane < 4; vlane = vlane + 1) begin
                            if (vlane < active_vlanes) begin
                                for (j = 0; j < 6; j = j + 1)
                                    bank[wr_bank_tmp][vlane][j] <= vl_acc[vlane][j];
                                bank[wr_bank_tmp][vlane][6] <= din_r[2 * vlane];
                                bank[wr_bank_tmp][vlane][7] <= din_r[2 * vlane + 1];
                            end
                        end
                        wr_set[wr_bank_tmp]      = 1'b1;
                        wr_rows_set[wr_bank_tmp] = active_vlanes[3:0];
                        wr_bank_tmp              = ~wr_bank_tmp;
                        if (init_done_4vlane) state_next = STREAM;
                        init_done_4vlane_next = 1'b1;
                    end
                    phase_next = (phase_cnt[1:0] == 2'd3) ? 3'd0 : (phase_cnt + 3'd1);
                end
            end

            // --- Read side: drain current rd_bank row by row.
            //     Uses bank_full (previous-cycle value, like legacy cnt_prev).
            if (state == STREAM) begin
                if (lane_cfg == LANE8) begin
                    if (bank_full[rd_bank_tmp]) begin
                        row_idx = bank_row_rd_tmp;
                        valid_out <= 1'b1;
                        for (i = 0; i < 4; i = i + 1) begin
                            dout_top[i] <= bank[rd_bank_tmp][row_idx][i];
                            dout_bot[i] <= bank[rd_bank_tmp][row_idx][4 + i];
                        end
                        if (bank_row_rd_tmp + 4'd1 == bank_rows_used[rd_bank_tmp]) begin
                            rd_clr[rd_bank_tmp] = 1'b1;
                            bank_row_rd_tmp = 4'd0;
                            rd_bank_tmp = ~rd_bank_tmp;
                        end else begin
                            bank_row_rd_tmp = bank_row_rd_tmp + 4'd1;
                        end
                    end
                end else begin
                    if (!lane4_chunk_valid) begin
                        if (bank_full[rd_bank_tmp]) begin
                            row_idx = bank_row_rd_tmp;
                            valid_out <= 1'b1;
                            for (i = 0; i < 8; i = i + 1)
                                cur_chunk[i] <= bank[rd_bank_tmp][row_idx][i];
                            for (i = 0; i < 4; i = i + 1) begin
                                dout_top[i] <= bank[rd_bank_tmp][row_idx][i];
                                dout_bot[i] <= 0;
                            end
                            if (bank_row_rd_tmp + 4'd1 == bank_rows_used[rd_bank_tmp]) begin
                                rd_clr[rd_bank_tmp] = 1'b1;
                                bank_row_rd_tmp = 4'd0;
                                rd_bank_tmp = ~rd_bank_tmp;
                            end else begin
                                bank_row_rd_tmp = bank_row_rd_tmp + 4'd1;
                            end
                            lane4_chunk_valid_next = 1'b1;
                            lane4_second_beat_next = 1'b1;
                        end
                    end else if (lane4_second_beat) begin
                        valid_out <= 1'b1;
                        for (i = 0; i < 4; i = i + 1) begin
                            dout_top[i] <= cur_chunk[4 + i];
                            dout_bot[i] <= 0;
                        end
                        lane4_chunk_valid_next = 1'b0;
                        lane4_second_beat_next = 1'b0;
                    end
                end
            end

            // Commit bank_full / bank_rows_used with set-wins-over-clear.
            for (i = 0; i < 2; i = i + 1) begin
                if (wr_set[i]) begin
                    bank_full[i]      <= 1'b1;
                    bank_rows_used[i] <= wr_rows_set[i];
                end else if (rd_clr[i]) begin
                    bank_full[i]      <= 1'b0;
                    bank_rows_used[i] <= 4'd0;
                end
            end

            wr_bank           <= wr_bank_tmp;
            rd_bank           <= rd_bank_tmp;
            bank_row_rd       <= bank_row_rd_tmp;
            phase_cnt         <= phase_next;
            state             <= state_next;
            init_done_4vlane  <= init_done_4vlane_next;
            lane4_chunk_valid <= lane4_chunk_valid_next;
            lane4_second_beat <= lane4_second_beat_next;
            prev_valid        <= valid_in;
        end
    end

endmodule
