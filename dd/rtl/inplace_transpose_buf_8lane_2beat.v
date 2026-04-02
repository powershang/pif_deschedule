`timescale 1ns/1ps

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

    reg [DATA_W-1:0] phy_acc  [0:7][0:7];
    reg [DATA_W-1:0] vl_acc   [0:3][0:7];
    reg [DATA_W-1:0] fifo_mem [0:15][0:7];
    reg [DATA_W-1:0] cur_chunk [0:7];
    reg [DATA_W-1:0] din_r [0:7];
    reg [DATA_W-1:0] dout_top [0:3];
    reg [DATA_W-1:0] dout_bot [0:3];

    reg [3:0] wr_ptr, rd_ptr;
    reg [4:0] fifo_count;
    reg [2:0] phase_cnt;
    reg [1:0] state;
    reg       init_done_4vlane;
    reg       lane4_chunk_valid;
    reg       lane4_second_beat;
    integer   wr_tmp, rd_tmp, cnt_tmp, cnt_prev;
    integer   base_idx, row_idx, active_lanes, active_vlanes;
    reg [2:0] phase_next;
    reg [1:0] state_next;
    reg       init_done_4vlane_next;
    reg       lane4_chunk_valid_next;
    reg       lane4_second_beat_next;

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
            wr_ptr <= 4'd0; rd_ptr <= 4'd0; fifo_count <= 5'd0;
            phase_cnt <= 3'd0; state <= INIT_FILL;
            init_done_4vlane <= 1'b0;
            lane4_chunk_valid <= 1'b0; lane4_second_beat <= 1'b0;
            prev_valid <= 1'b0;
            valid_out <= 1'b0;
            for (i = 0; i < 4; i = i + 1) begin
                dout_top[i] <= 0; dout_bot[i] <= 0;
            end
            for (i = 0; i < 8; i = i + 1)
                cur_chunk[i] <= 0;
            for (i = 0; i < 8; i = i + 1) begin
                for (j = 0; j < 8; j = j + 1) begin
                    phy_acc[i][j] <= 0;
                    fifo_mem[i][j] <= 0;
                    if (i < 4) vl_acc[i][j] <= 0;
                end
            end
            for (i = 8; i < 16; i = i + 1)
                for (j = 0; j < 8; j = j + 1)
                    fifo_mem[i][j] <= 0;
        end else begin
            wr_tmp = wr_ptr; rd_tmp = rd_ptr;
            cnt_tmp = fifo_count; cnt_prev = fifo_count;
            phase_next = phase_cnt; state_next = state;
            init_done_4vlane_next = init_done_4vlane;
            lane4_chunk_valid_next = lane4_chunk_valid;
            lane4_second_beat_next = lane4_second_beat;
            active_lanes = (lane_cfg == LANE8) ? 8 : 4;
            active_vlanes = (lane_cfg == LANE8) ? 4 : 2;

            valid_out <= 1'b0;
            for (i = 0; i < 4; i = i + 1) begin
                dout_top[i] <= 0; dout_bot[i] <= 0;
            end

            if (valid_in && !prev_valid) begin
                // Fresh burst: soft reset
                phase_next = 3'd0;
                state_next = INIT_FILL;
                init_done_4vlane_next = 1'b0;
                lane4_chunk_valid_next = 1'b0;
                lane4_second_beat_next = 1'b0;
                wr_tmp = 0; rd_tmp = 0; cnt_tmp = 0; cnt_prev = 0;
            end

            if (valid_in) begin
                if (mode == MODE_PHY) begin
                    for (lane = 0; lane < 8; lane = lane + 1)
                        if (lane < active_lanes)
                            phy_acc[lane][phase_cnt] <= din_r[lane];
                    if (phase_cnt == 3'd7) begin
                        for (lane = 0; lane < 8; lane = lane + 1) begin
                            if (lane < active_lanes) begin
                                for (j = 0; j < 7; j = j + 1)
                                    fifo_mem[wr_tmp][j] <= phy_acc[lane][j];
                                fifo_mem[wr_tmp][7] <= din_r[lane];
                                wr_tmp = wr_tmp + 1;
                                cnt_tmp = cnt_tmp + 1;
                            end
                        end
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
                                    fifo_mem[wr_tmp][j] <= vl_acc[vlane][j];
                                fifo_mem[wr_tmp][6] <= din_r[2 * vlane];
                                fifo_mem[wr_tmp][7] <= din_r[2 * vlane + 1];
                                wr_tmp = wr_tmp + 1;
                                cnt_tmp = cnt_tmp + 1;
                            end
                        end
                        if (init_done_4vlane) state_next = STREAM;
                        init_done_4vlane_next = 1'b1;
                    end
                    phase_next = (phase_cnt[1:0] == 2'd3) ? 3'd0 : (phase_cnt + 3'd1);
                end
            end

            if (state == STREAM) begin
                if (lane_cfg == LANE8) begin
                    if (cnt_prev != 0) begin
                        row_idx = rd_tmp;
                        valid_out <= 1'b1;
                        for (i = 0; i < 4; i = i + 1) begin
                            dout_top[i] <= fifo_mem[row_idx][i];
                            dout_bot[i] <= fifo_mem[row_idx][4 + i];
                        end
                        rd_tmp = rd_tmp + 1;
                        cnt_tmp = cnt_tmp - 1;
                    end
                end else begin
                    if (!lane4_chunk_valid) begin
                        if (cnt_prev != 0) begin
                            row_idx = rd_tmp;
                            valid_out <= 1'b1;
                            for (i = 0; i < 8; i = i + 1)
                                cur_chunk[i] <= fifo_mem[row_idx][i];
                            for (i = 0; i < 4; i = i + 1) begin
                                dout_top[i] <= fifo_mem[row_idx][i];
                                dout_bot[i] <= 0;
                            end
                            rd_tmp = rd_tmp + 1;
                            cnt_tmp = cnt_tmp - 1;
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

            wr_ptr          <= wr_tmp[3:0];
            rd_ptr          <= rd_tmp[3:0];
            fifo_count      <= cnt_tmp[4:0];
            phase_cnt       <= phase_next;
            state           <= state_next;
            init_done_4vlane<= init_done_4vlane_next;
            lane4_chunk_valid <= lane4_chunk_valid_next;
            lane4_second_beat <= lane4_second_beat_next;
            prev_valid        <= valid_in;
        end
    end

endmodule
