`timescale 1ns/1ps

// Reference-only / deprecated:
// Product integration should use inplace_transpose_buf_8lane_2beat
// with lane_cfg=LANE4.

module inplace_transpose_buf_4lane_2beat (
    clk, rst_n, valid_in, mode,
    din0, din1, din2, din3,
    valid_out, dout0, dout1, dout2, dout3
);

    parameter DATA_W = 8;

    input              clk, rst_n, valid_in;
    input              mode;
    input  [DATA_W-1:0] din0, din1, din2, din3;
    output reg         valid_out;
    output [DATA_W-1:0] dout0, dout1, dout2, dout3;

    localparam [1:0] INIT_FILL   = 2'd0;
    localparam [1:0] STREAM      = 2'd1;
    localparam       MODE_PHY4   = 1'b0;
    localparam       MODE_2VLANE = 1'b1;

    reg [DATA_W-1:0] buf_mem [0:7][0:7];
    reg [DATA_W-1:0] acc0 [0:7];
    reg [DATA_W-1:0] acc1 [0:7];
    reg [DATA_W-1:0] acc2 [0:7];
    reg [DATA_W-1:0] acc3 [0:7];
    reg [DATA_W-1:0] cur_chunk [0:7];
    reg [DATA_W-1:0] din_r [0:3];
    reg [DATA_W-1:0] dout_r [0:3];

    reg [2:0] phase_cnt;
    reg [1:0] state;
    reg [1:0] init_pair_count;
    reg [2:0] wr_ptr, rd_ptr;
    reg [3:0] row_count;
    reg       cur_valid, beat_sel;
    integer   wr_tmp, rd_tmp, cnt_tmp;
    reg [1:0] state_next, init_pair_count_next;
    reg       cur_valid_next, beat_sel_next;
    reg [2:0] phase_cnt_next;
    reg       pair_done;
    integer   base_idx, row_idx;
    reg       prev_valid;
    integer   i;

    always @(*) begin
        din_r[0] = din0; din_r[1] = din1; din_r[2] = din2; din_r[3] = din3;
    end
    assign dout0 = dout_r[0]; assign dout1 = dout_r[1];
    assign dout2 = dout_r[2]; assign dout3 = dout_r[3];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase_cnt       <= 3'd0;
            state           <= INIT_FILL;
            init_pair_count <= 2'd0;
            wr_ptr          <= 3'd0;
            rd_ptr          <= 3'd0;
            row_count       <= 4'd0;
            cur_valid       <= 1'b0;
            beat_sel        <= 1'b0;
            valid_out       <= 1'b0;
            prev_valid      <= 1'b0;
            for (i = 0; i < 8; i = i + 1) begin
                acc0[i] <= 0; acc1[i] <= 0; acc2[i] <= 0; acc3[i] <= 0;
                cur_chunk[i] <= 0;
            end
            for (i = 0; i < 4; i = i + 1)
                dout_r[i] <= 0;
        end else begin
            wr_tmp = wr_ptr;
            rd_tmp = rd_ptr;
            cnt_tmp = row_count;
            state_next = state;
            init_pair_count_next = init_pair_count;
            cur_valid_next = cur_valid;
            beat_sel_next = beat_sel;
            phase_cnt_next = phase_cnt;
            pair_done = 1'b0;

            if (valid_in && !prev_valid) begin
                // Fresh burst: soft reset
                phase_cnt_next = 3'd0;
                state_next = INIT_FILL;
                init_pair_count_next = 2'd0;
                cur_valid_next = 1'b0;
                beat_sel_next = 1'b0;
                wr_tmp = 0; rd_tmp = 0; cnt_tmp = 0;
            end

            if (valid_in) begin
                base_idx = {phase_cnt[1:0], 1'b0};
                if (mode == MODE_2VLANE && phase_cnt[1:0] != 2'd3) begin
                    acc0[base_idx]     <= din_r[0];
                    acc0[base_idx + 1] <= din_r[1];
                    acc1[base_idx]     <= din_r[2];
                    acc1[base_idx + 1] <= din_r[3];
                end else if (mode == MODE_PHY4 && phase_cnt != 3'd7) begin
                    acc0[phase_cnt] <= din_r[0];
                    acc1[phase_cnt] <= din_r[1];
                    acc2[phase_cnt] <= din_r[2];
                    acc3[phase_cnt] <= din_r[3];
                end else begin
                    pair_done = 1'b1;
                    if (mode == MODE_2VLANE) begin
                        acc0[base_idx]     <= din_r[0];
                        buf_mem[wr_tmp][0] <= acc0[0]; buf_mem[wr_tmp][1] <= acc0[1];
                        buf_mem[wr_tmp][2] <= acc0[2]; buf_mem[wr_tmp][3] <= acc0[3];
                        buf_mem[wr_tmp][4] <= acc0[4]; buf_mem[wr_tmp][5] <= acc0[5];
                        buf_mem[wr_tmp][6] <= din_r[0]; buf_mem[wr_tmp][7] <= din_r[1];
                        wr_tmp = (wr_tmp == 7) ? 0 : (wr_tmp + 1);
                        cnt_tmp = cnt_tmp + 1;
                        buf_mem[wr_tmp][0] <= acc1[0]; buf_mem[wr_tmp][1] <= acc1[1];
                        buf_mem[wr_tmp][2] <= acc1[2]; buf_mem[wr_tmp][3] <= acc1[3];
                        buf_mem[wr_tmp][4] <= acc1[4]; buf_mem[wr_tmp][5] <= acc1[5];
                        buf_mem[wr_tmp][6] <= din_r[2]; buf_mem[wr_tmp][7] <= din_r[3];
                        wr_tmp = (wr_tmp == 7) ? 0 : (wr_tmp + 1);
                        cnt_tmp = cnt_tmp + 1;
                        if (state == INIT_FILL) begin
                            if (init_pair_count == 2'd1) state_next = STREAM;
                            init_pair_count_next = init_pair_count + 2'd1;
                        end
                    end else begin
                        for (i = 0; i < 4; i = i + 1) begin
                            buf_mem[wr_tmp][0] <= (i==0)?acc0[0]:(i==1)?acc1[0]:(i==2)?acc2[0]:acc3[0];
                            buf_mem[wr_tmp][1] <= (i==0)?acc0[1]:(i==1)?acc1[1]:(i==2)?acc2[1]:acc3[1];
                            buf_mem[wr_tmp][2] <= (i==0)?acc0[2]:(i==1)?acc1[2]:(i==2)?acc2[2]:acc3[2];
                            buf_mem[wr_tmp][3] <= (i==0)?acc0[3]:(i==1)?acc1[3]:(i==2)?acc2[3]:acc3[3];
                            buf_mem[wr_tmp][4] <= (i==0)?acc0[4]:(i==1)?acc1[4]:(i==2)?acc2[4]:acc3[4];
                            buf_mem[wr_tmp][5] <= (i==0)?acc0[5]:(i==1)?acc1[5]:(i==2)?acc2[5]:acc3[5];
                            buf_mem[wr_tmp][6] <= (i==0)?acc0[6]:(i==1)?acc1[6]:(i==2)?acc2[6]:acc3[6];
                            buf_mem[wr_tmp][7] <= din_r[i];
                            wr_tmp = (wr_tmp == 7) ? 0 : (wr_tmp + 1);
                            cnt_tmp = cnt_tmp + 1;
                        end
                        if (state == INIT_FILL) state_next = STREAM;
                    end
                end
                phase_cnt_next = (phase_cnt == 3'd7) ? 3'd0 : (phase_cnt + 3'd1);
            end

            valid_out <= 1'b0;
            for (i = 0; i < 4; i = i + 1)
                dout_r[i] <= 0;

            if (state == STREAM) begin
                if (!cur_valid) begin
                    if (cnt_tmp != 0) begin
                        row_idx = rd_tmp;
                        valid_out <= 1'b1;
                        for (i = 0; i < 8; i = i + 1)
                            cur_chunk[i] <= buf_mem[row_idx][i];
                        for (i = 0; i < 4; i = i + 1)
                            dout_r[i] <= buf_mem[row_idx][i];
                        rd_tmp = (rd_tmp == 7) ? 0 : (rd_tmp + 1);
                        cnt_tmp = cnt_tmp - 1;
                        cur_valid_next = 1'b1;
                        beat_sel_next = 1'b0;
                    end
                end else if (!beat_sel) begin
                    valid_out <= 1'b1;
                    for (i = 0; i < 4; i = i + 1)
                        dout_r[i] <= cur_chunk[4 + i];
                    cur_valid_next = 1'b1;
                    beat_sel_next = 1'b1;
                end else begin
                    if (cnt_tmp != 0) begin
                        row_idx = rd_tmp;
                        valid_out <= 1'b1;
                        for (i = 0; i < 8; i = i + 1)
                            cur_chunk[i] <= buf_mem[row_idx][i];
                        for (i = 0; i < 4; i = i + 1)
                            dout_r[i] <= buf_mem[row_idx][i];
                        rd_tmp = (rd_tmp == 7) ? 0 : (rd_tmp + 1);
                        cnt_tmp = cnt_tmp - 1;
                        cur_valid_next = 1'b1;
                        beat_sel_next = 1'b0;
                    end else begin
                        cur_valid_next = 1'b0;
                        beat_sel_next = 1'b0;
                    end
                end
            end

            phase_cnt       <= phase_cnt_next;
            state           <= state_next;
            init_pair_count <= init_pair_count_next;
            wr_ptr          <= wr_tmp[2:0];
            rd_ptr          <= rd_tmp[2:0];
            row_count       <= cnt_tmp[3:0];
            cur_valid       <= cur_valid_next;
            beat_sel        <= beat_sel_next;
            prev_valid      <= valid_in;
        end
    end

endmodule
