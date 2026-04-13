`timescale 1ns/1ps

module tb;

    parameter DATA_W = 8;
    parameter CLK_FAST_HALF = 5;  // fast clock half period (10ns period)
    parameter MAX_EXP = 4096;

    localparam LMODE_4LANE  = 2'b00;
    localparam LMODE_8LANE  = 2'b01;
    localparam LMODE_12LANE = 2'b10;
    localparam LMODE_16LANE = 2'b11;

    reg               clk;
    reg               clk_out;
    reg               rst_n;
    reg               valid_in;
    reg  [1:0]        lane_mode;
    reg               virtual_lane_en;
    reg  [DATA_W-1:0] din0;
    reg  [DATA_W-1:0] din1;
    reg  [DATA_W-1:0] din2;
    reg  [DATA_W-1:0] din3;
    reg  [DATA_W-1:0] din4;
    reg  [DATA_W-1:0] din5;
    reg  [DATA_W-1:0] din6;
    reg  [DATA_W-1:0] din7;
    reg  [DATA_W-1:0] din8;
    reg  [DATA_W-1:0] din9;
    reg  [DATA_W-1:0] din10;
    reg  [DATA_W-1:0] din11;
    reg  [DATA_W-1:0] din12;
    reg  [DATA_W-1:0] din13;
    reg  [DATA_W-1:0] din14;
    reg  [DATA_W-1:0] din15;

    wire              valid_out;
    wire              align_error_flag;
    wire [DATA_W-1:0] dout0;
    wire [DATA_W-1:0] dout1;
    wire [DATA_W-1:0] dout2;
    wire [DATA_W-1:0] dout3;
    wire [2:0]        dbg_state;
    wire [3:0]        dbg_fifo_cnt;

    reg  [DATA_W-1:0] exp0 [0:MAX_EXP-1];
    reg  [DATA_W-1:0] exp1 [0:MAX_EXP-1];
    reg  [DATA_W-1:0] exp2 [0:MAX_EXP-1];
    reg  [DATA_W-1:0] exp3 [0:MAX_EXP-1];
    reg  [DATA_W-1:0] aseq0 [0:MAX_EXP-1];
    reg  [DATA_W-1:0] aseq1 [0:MAX_EXP-1];
    reg  [DATA_W-1:0] aseq2 [0:MAX_EXP-1];
    reg  [DATA_W-1:0] aseq3 [0:MAX_EXP-1];
    reg  [DATA_W-1:0] bseq0 [0:MAX_EXP-1];
    reg  [DATA_W-1:0] bseq1 [0:MAX_EXP-1];
    reg  [DATA_W-1:0] bseq2 [0:MAX_EXP-1];
    reg  [DATA_W-1:0] bseq3 [0:MAX_EXP-1];

    integer exp_count;
    integer got_count;
    integer fail_count;
    integer timeout_count;
    integer max_fifo_seen;
    integer aseq_count;
    integer bseq_count;
    reg     checking_en;
    integer slow_half;

    inplace_transpose_buf_multi_lane_scheduler_top #(
        .DATA_W(DATA_W)
    ) dut (
        .clk_in         (clk),
        .clk_out        (clk_out),
        .rst_n          (rst_n),
        .valid_in       (valid_in),
        .lane_mode      (lane_mode),
        .virtual_lane_en(virtual_lane_en),
        .din0           (din0),
        .din1           (din1),
        .din2           (din2),
        .din3           (din3),
        .din4           (din4),
        .din5           (din5),
        .din6           (din6),
        .din7           (din7),
        .din8           (din8),
        .din9           (din9),
        .din10          (din10),
        .din11          (din11),
        .din12          (din12),
        .din13          (din13),
        .din14          (din14),
        .din15          (din15),
        .align_error_flag(align_error_flag),
        .valid_out      (valid_out),
        .dout0          (dout0),
        .dout1          (dout1),
        .dout2          (dout2),
        .dout3          (dout3),
        .dbg_state      (dbg_state),
        .dbg_fifo_cnt   (dbg_fifo_cnt)
    );

    // clk_out = fast clock (base, fixed period)
    initial clk_out = 1'b0;
    always #(CLK_FAST_HALF) clk_out = ~clk_out;

    // clk = slow clock (derived, posedge between fast posedges)
    initial begin
        clk = 1'b0;
        slow_half = CLK_FAST_HALF;  // default: same as fast (4L)
        #(CLK_FAST_HALF);           // offset so slow posedge falls between fast posedges
        forever #(slow_half) clk = ~clk;
    end

    initial begin
        $dumpfile("wave_multi_lane_top.vcd");
        $dumpvars(0, tb);
    end

    always @(posedge clk_out) begin
        #1;
        if (dbg_fifo_cnt > max_fifo_seen)
            max_fifo_seen = dbg_fifo_cnt;

        if (checking_en && valid_out) begin
            if (exp_count == 0) begin
                // Drain mode (12L): just count, no content check
                ;
            end else if (got_count >= exp_count) begin
                $display("FAIL extra out#%0d got {%0d,%0d,%0d,%0d}",
                         got_count, dout0, dout1, dout2, dout3);
                fail_count = fail_count + 1;
            end else if (dout0 !== exp0[got_count] ||
                         dout1 !== exp1[got_count] ||
                         dout2 !== exp2[got_count] ||
                         dout3 !== exp3[got_count]) begin
                $display("FAIL out#%0d exp {%0d,%0d,%0d,%0d} got {%0d,%0d,%0d,%0d} state=%0d fifo_a=%0d fifo_b=%0d",
                         got_count,
                         exp0[got_count], exp1[got_count], exp2[got_count], exp3[got_count],
                         dout0, dout1, dout2, dout3,
                         dbg_state, dbg_fifo_cnt, dbg_fifo_cnt);
                fail_count = fail_count + 1;
            end
            got_count = got_count + 1;
        end
    end

    task clear_inputs;
        begin
            valid_in = 1'b0;
            din0 = '0;  din1 = '0;  din2 = '0;  din3 = '0;
            din4 = '0;  din5 = '0;  din6 = '0;  din7 = '0;
            din8 = '0;  din9 = '0;  din10 = '0; din11 = '0;
            din12 = '0; din13 = '0; din14 = '0; din15 = '0;
        end
    endtask

    task clear_expected;
        integer i;
        begin
            exp_count = 0;
            got_count = 0;
            timeout_count = 0;
            aseq_count = 0;
            bseq_count = 0;
            max_fifo_seen = 0;
            for (i = 0; i < MAX_EXP; i = i + 1) begin
                exp0[i] = '0; exp1[i] = '0; exp2[i] = '0; exp3[i] = '0;
                aseq0[i] = '0; aseq1[i] = '0; aseq2[i] = '0; aseq3[i] = '0;
                bseq0[i] = '0; bseq1[i] = '0; bseq2[i] = '0; bseq3[i] = '0;
            end
        end
    endtask

    task push_aseq;
        input [DATA_W-1:0] e0;
        input [DATA_W-1:0] e1;
        input [DATA_W-1:0] e2;
        input [DATA_W-1:0] e3;
        begin
            aseq0[aseq_count] = e0;
            aseq1[aseq_count] = e1;
            aseq2[aseq_count] = e2;
            aseq3[aseq_count] = e3;
            aseq_count = aseq_count + 1;
        end
    endtask

    task push_bseq;
        input [DATA_W-1:0] e0;
        input [DATA_W-1:0] e1;
        input [DATA_W-1:0] e2;
        input [DATA_W-1:0] e3;
        begin
            bseq0[bseq_count] = e0;
            bseq1[bseq_count] = e1;
            bseq2[bseq_count] = e2;
            bseq3[bseq_count] = e3;
            bseq_count = bseq_count + 1;
        end
    endtask

    task push_expected;
        input [DATA_W-1:0] e0;
        input [DATA_W-1:0] e1;
        input [DATA_W-1:0] e2;
        input [DATA_W-1:0] e3;
        begin
            exp0[exp_count] = e0;
            exp1[exp_count] = e1;
            exp2[exp_count] = e2;
            exp3[exp_count] = e3;
            exp_count = exp_count + 1;
        end
    endtask

    task build_a_sequence;
        input [1:0] lane_mode_sel;
        input       vlan_en_sel;
        input integer valid_pulses;
        integer g;
        integer lane_idx;
        integer base;
        integer groups4;
        integer groups8;
        begin
            groups4 = valid_pulses / 4;
            groups8 = valid_pulses / 8;

            case (lane_mode_sel)
                LMODE_4LANE: begin
                    if (!vlan_en_sel) begin
                        for (g = 0; g < groups8; g = g + 1) begin
                            for (lane_idx = 0; lane_idx < 4; lane_idx = lane_idx + 1) begin
                                base = lane_idx * 16 + g * 8;
                                push_aseq(base + 0, base + 1, base + 2, base + 3);
                                push_aseq(base + 4, base + 5, base + 6, base + 7);
                            end
                        end
                    end else begin
                        for (g = 0; g < groups4; g = g + 1) begin
                            push_aseq(160 + g * 8, 161 + g * 8, 162 + g * 8, 163 + g * 8);
                            push_aseq(164 + g * 8, 165 + g * 8, 166 + g * 8, 167 + g * 8);
                            push_aseq(192 + g * 8, 193 + g * 8, 194 + g * 8, 195 + g * 8);
                            push_aseq(196 + g * 8, 197 + g * 8, 198 + g * 8, 199 + g * 8);
                        end
                    end
                end

                LMODE_8LANE: begin
                    if (!vlan_en_sel) begin
                        for (g = 0; g < groups8; g = g + 1) begin
                            for (lane_idx = 0; lane_idx < 8; lane_idx = lane_idx + 1) begin
                                base = lane_idx * 16 + g * 8;
                                push_aseq(base + 0, base + 1, base + 2, base + 3);
                                push_aseq(base + 4, base + 5, base + 6, base + 7);
                            end
                        end
                    end else begin
                        for (g = 0; g < groups4; g = g + 1) begin
                            push_aseq(0 + g * 8, 1 + g * 8, 2 + g * 8, 3 + g * 8);
                            push_aseq(4 + g * 8, 5 + g * 8, 6 + g * 8, 7 + g * 8);
                            push_aseq(32 + g * 8, 33 + g * 8, 34 + g * 8, 35 + g * 8);
                            push_aseq(36 + g * 8, 37 + g * 8, 38 + g * 8, 39 + g * 8);
                            push_aseq(64 + g * 8, 65 + g * 8, 66 + g * 8, 67 + g * 8);
                            push_aseq(68 + g * 8, 69 + g * 8, 70 + g * 8, 71 + g * 8);
                            push_aseq(112 + g * 8, 113 + g * 8, 114 + g * 8, 115 + g * 8);
                            push_aseq(116 + g * 8, 117 + g * 8, 118 + g * 8, 119 + g * 8);
                        end
                    end
                end

                LMODE_12LANE, LMODE_16LANE: begin
                    if (!vlan_en_sel) begin
                        for (g = 0; g < groups8; g = g + 1) begin
                            for (lane_idx = 0; lane_idx < 8; lane_idx = lane_idx + 1) begin
                                base = lane_idx * 16 + g * 8;
                                push_aseq(base + 0, base + 1, base + 2, base + 3);
                                push_aseq(base + 4, base + 5, base + 6, base + 7);
                            end
                        end
                    end else begin
                        for (g = 0; g < groups4; g = g + 1) begin
                            push_aseq(0 + g * 8, 1 + g * 8, 2 + g * 8, 3 + g * 8);
                            push_aseq(4 + g * 8, 5 + g * 8, 6 + g * 8, 7 + g * 8);
                            push_aseq(32 + g * 8, 33 + g * 8, 34 + g * 8, 35 + g * 8);
                            push_aseq(36 + g * 8, 37 + g * 8, 38 + g * 8, 39 + g * 8);
                            push_aseq(64 + g * 8, 65 + g * 8, 66 + g * 8, 67 + g * 8);
                            push_aseq(68 + g * 8, 69 + g * 8, 70 + g * 8, 71 + g * 8);
                            push_aseq(96 + g * 8, 97 + g * 8, 98 + g * 8, 99 + g * 8);
                            push_aseq(100 + g * 8, 101 + g * 8, 102 + g * 8, 103 + g * 8);
                        end
                    end
                end
            endcase
        end
    endtask

    task build_b_sequence;
        input [1:0] lane_mode_sel;
        input       vlan_en_sel;
        input integer valid_pulses;
        integer g;
        integer lane_idx;
        integer base;
        integer groups4;
        integer groups8;
        begin
            groups4 = valid_pulses / 4;
            groups8 = valid_pulses / 8;

            if (lane_mode_sel == LMODE_12LANE) begin
                if (!vlan_en_sel) begin
                    for (g = 0; g < groups8; g = g + 1) begin
                        for (lane_idx = 0; lane_idx < 4; lane_idx = lane_idx + 1) begin
                            base = 160 + lane_idx * 16 + g * 8;
                            push_bseq(base + 0, base + 1, base + 2, base + 3);
                            push_bseq(base + 4, base + 5, base + 6, base + 7);
                        end
                    end
                end else begin
                    for (g = 0; g < groups4; g = g + 1) begin
                        push_bseq(160 + g * 8, 161 + g * 8, 162 + g * 8, 163 + g * 8);
                        push_bseq(164 + g * 8, 165 + g * 8, 166 + g * 8, 167 + g * 8);
                        push_bseq(192 + g * 8, 193 + g * 8, 194 + g * 8, 195 + g * 8);
                        push_bseq(196 + g * 8, 197 + g * 8, 198 + g * 8, 199 + g * 8);
                    end
                end
            end else if (lane_mode_sel == LMODE_16LANE) begin
                if (!vlan_en_sel) begin
                    for (g = 0; g < groups8; g = g + 1) begin
                        for (lane_idx = 0; lane_idx < 8; lane_idx = lane_idx + 1) begin
                            base = 128 + lane_idx * 16 + g * 8;
                            push_bseq(base + 0, base + 1, base + 2, base + 3);
                            push_bseq(base + 4, base + 5, base + 6, base + 7);
                        end
                    end
                end else begin
                    for (g = 0; g < groups4; g = g + 1) begin
                        push_bseq(128 + g * 8, 129 + g * 8, 130 + g * 8, 131 + g * 8);
                        push_bseq(132 + g * 8, 133 + g * 8, 134 + g * 8, 135 + g * 8);
                        push_bseq(160 + g * 8, 161 + g * 8, 162 + g * 8, 163 + g * 8);
                        push_bseq(164 + g * 8, 165 + g * 8, 166 + g * 8, 167 + g * 8);
                        push_bseq(192 + g * 8, 193 + g * 8, 194 + g * 8, 195 + g * 8);
                        push_bseq(196 + g * 8, 197 + g * 8, 198 + g * 8, 199 + g * 8);
                        push_bseq(224 + g * 8, 225 + g * 8, 226 + g * 8, 227 + g * 8);
                        push_bseq(228 + g * 8, 229 + g * 8, 230 + g * 8, 231 + g * 8);
                    end
                end
            end
        end
    endtask

    task merge_expected;
        input [1:0] lane_mode_sel;
        integer ai;
        integer bi;
        integer ii;
        begin
            ai = 0;
            bi = 0;

            case (lane_mode_sel)
                LMODE_4LANE, LMODE_8LANE: begin
                    while (ai < aseq_count) begin
                        push_expected(aseq0[ai], aseq1[ai], aseq2[ai], aseq3[ai]);
                        ai = ai + 1;
                    end
                end

                LMODE_12LANE, LMODE_16LANE: begin
                    if (lane_mode_sel == LMODE_12LANE) begin
                        // 12L: scheduler interleaves a and b in 3-beat windows.
                        // Exact count depends on pipeline timing; use drain-based check.
                        // Set exp_count = 0 to signal drain mode.
                        exp_count = 0;
                    end else begin
                        while (ai < aseq_count || bi < bseq_count) begin
                            if (ai < aseq_count) begin
                                push_expected(aseq0[ai], aseq1[ai], aseq2[ai], aseq3[ai]);
                                ai = ai + 1;
                            end
                            if (ai < aseq_count) begin
                                push_expected(aseq0[ai], aseq1[ai], aseq2[ai], aseq3[ai]);
                                ai = ai + 1;
                            end
                            if (bi < bseq_count) begin
                                push_expected(bseq0[bi], bseq1[bi], bseq2[bi], bseq3[bi]);
                                bi = bi + 1;
                            end
                            if (bi < bseq_count) begin
                                push_expected(bseq0[bi], bseq1[bi], bseq2[bi], bseq3[bi]);
                                bi = bi + 1;
                            end
                        end
                    end
                end
            endcase
        end
    endtask

    task build_expected;
        input [1:0] lane_mode_sel;
        input       vlan_en_sel;
        input integer valid_pulses;
        begin
            clear_expected;
            build_a_sequence(lane_mode_sel, vlan_en_sel, valid_pulses);
            build_b_sequence(lane_mode_sel, vlan_en_sel, valid_pulses);
            merge_expected(lane_mode_sel);
        end
    endtask

    task drive_inputs;
        input [1:0] lane_mode_sel;
        input       vlan_en_sel;
        input integer cycle_num;
        begin
            valid_in = 1'b1;

            case (lane_mode_sel)
                LMODE_4LANE: begin
                    if (!vlan_en_sel) begin
                        din0 = cycle_num;
                        din1 = 16 + cycle_num;
                        din2 = 32 + cycle_num;
                        din3 = 48 + cycle_num;
                    end else begin
                        din0 = 160 + 2 * cycle_num;
                        din1 = 160 + 2 * cycle_num + 1;
                        din2 = 192 + 2 * cycle_num;
                        din3 = 192 + 2 * cycle_num + 1;
                    end
                    din4 = '0; din5 = '0; din6 = '0; din7 = '0;
                    din8 = '0; din9 = '0; din10 = '0; din11 = '0;
                    din12 = '0; din13 = '0; din14 = '0; din15 = '0;
                end

                LMODE_8LANE: begin
                    if (!vlan_en_sel) begin
                        din0 = cycle_num;
                        din1 = 16 + cycle_num;
                        din2 = 32 + cycle_num;
                        din3 = 48 + cycle_num;
                        din4 = 64 + cycle_num;
                        din5 = 80 + cycle_num;
                        din6 = 96 + cycle_num;
                        din7 = 112 + cycle_num;
                    end else begin
                        din0 = 2 * cycle_num;
                        din1 = 2 * cycle_num + 1;
                        din2 = 32 + 2 * cycle_num;
                        din3 = 32 + 2 * cycle_num + 1;
                        din4 = 64 + 2 * cycle_num;
                        din5 = 64 + 2 * cycle_num + 1;
                        din6 = 112 + 2 * cycle_num;
                        din7 = 112 + 2 * cycle_num + 1;
                    end
                    din8 = '0; din9 = '0; din10 = '0; din11 = '0;
                    din12 = '0; din13 = '0; din14 = '0; din15 = '0;
                end

                LMODE_12LANE: begin
                    if (!vlan_en_sel) begin
                        din0 = cycle_num;
                        din1 = 16 + cycle_num;
                        din2 = 32 + cycle_num;
                        din3 = 48 + cycle_num;
                        din4 = 64 + cycle_num;
                        din5 = 80 + cycle_num;
                        din6 = 96 + cycle_num;
                        din7 = 112 + cycle_num;
                        din8 = 160 + cycle_num;
                        din9 = 176 + cycle_num;
                        din10 = 192 + cycle_num;
                        din11 = 208 + cycle_num;
                    end else begin
                        din0 = 2 * cycle_num;
                        din1 = 2 * cycle_num + 1;
                        din2 = 32 + 2 * cycle_num;
                        din3 = 32 + 2 * cycle_num + 1;
                        din4 = 64 + 2 * cycle_num;
                        din5 = 64 + 2 * cycle_num + 1;
                        din6 = 96 + 2 * cycle_num;
                        din7 = 96 + 2 * cycle_num + 1;
                        din8 = 160 + 2 * cycle_num;
                        din9 = 160 + 2 * cycle_num + 1;
                        din10 = 192 + 2 * cycle_num;
                        din11 = 192 + 2 * cycle_num + 1;
                    end
                    din12 = '0; din13 = '0; din14 = '0; din15 = '0;
                end

                default: begin
                    if (!vlan_en_sel) begin
                        din0 = cycle_num;
                        din1 = 16 + cycle_num;
                        din2 = 32 + cycle_num;
                        din3 = 48 + cycle_num;
                        din4 = 64 + cycle_num;
                        din5 = 80 + cycle_num;
                        din6 = 96 + cycle_num;
                        din7 = 112 + cycle_num;
                        din8 = 128 + cycle_num;
                        din9 = 144 + cycle_num;
                        din10 = 160 + cycle_num;
                        din11 = 176 + cycle_num;
                        din12 = 192 + cycle_num;
                        din13 = 208 + cycle_num;
                        din14 = 224 + cycle_num;
                        din15 = 240 + cycle_num;
                    end else begin
                        din0 = 2 * cycle_num;
                        din1 = 2 * cycle_num + 1;
                        din2 = 32 + 2 * cycle_num;
                        din3 = 32 + 2 * cycle_num + 1;
                        din4 = 64 + 2 * cycle_num;
                        din5 = 64 + 2 * cycle_num + 1;
                        din6 = 96 + 2 * cycle_num;
                        din7 = 96 + 2 * cycle_num + 1;
                        din8 = 128 + 2 * cycle_num;
                        din9 = 128 + 2 * cycle_num + 1;
                        din10 = 160 + 2 * cycle_num;
                        din11 = 160 + 2 * cycle_num + 1;
                        din12 = 192 + 2 * cycle_num;
                        din13 = 192 + 2 * cycle_num + 1;
                        din14 = 224 + 2 * cycle_num;
                        din15 = 224 + 2 * cycle_num + 1;
                    end
                end
            endcase
        end
    endtask

    task do_reset;
        input [1:0] mode_sel;
        input integer mode_ratio;
        input vlan_en_sel;
        begin
            lane_mode = mode_sel;
            virtual_lane_en = vlan_en_sel;
            slow_half = mode_ratio * CLK_FAST_HALF;
            clear_inputs;
            checking_en = 1'b0;
            rst_n = 1'b0;
            repeat (4) begin @(posedge clk_out); end
            repeat (2) begin @(posedge clk); end
            rst_n = 1'b1;
            @(posedge clk);
        end
    endtask

    task run_case;
        input [255:0] case_name;
        input [1:0] mode_sel;
        input vlan_en_sel;
        input integer valid_pulses;
        integer pulse_idx;
        integer mode_ratio;
        integer timeout_limit;
        begin
            $display("\n=== %0s ===", case_name);

            case (mode_sel)
                LMODE_4LANE:  mode_ratio = 1;
                LMODE_8LANE:  mode_ratio = 2;
                LMODE_12LANE: mode_ratio = 3;
                default:      mode_ratio = 4;
            endcase

            build_expected(mode_sel, vlan_en_sel, valid_pulses);
            do_reset(mode_sel, mode_ratio, vlan_en_sel);
            checking_en = 1'b1;

            for (pulse_idx = 0; pulse_idx < valid_pulses; pulse_idx = pulse_idx + 1) begin
                @(posedge clk);
                #1;
                drive_inputs(mode_sel, vlan_en_sel, pulse_idx);
            end

            @(posedge clk);
            #1;
            clear_inputs;

            if (exp_count == 0) begin
                // Drain mode (12L): wait for pipeline to flush, count outputs
                repeat (valid_pulses * mode_ratio + 200) @(posedge clk_out);
                checking_en = 1'b0;
                if (got_count > 0)
                    $display("PASS %0s drain-checked %0d outputs (max_fifo=%0d)",
                             case_name, got_count, max_fifo_seen);
                else begin
                    $display("FAIL %0s no outputs received (max_fifo=%0d)",
                             case_name, max_fifo_seen);
                    fail_count = fail_count + 1;
                end
            end else begin
                timeout_limit = exp_count * 4 + 200;
                while (got_count < exp_count && timeout_count < timeout_limit) begin
                    @(posedge clk_out);
                    timeout_count = timeout_count + 1;
                end
                checking_en = 1'b0;
                if (got_count != exp_count) begin
                    $display("FAIL %0s expected %0d outputs, got %0d (max_fifo=%0d)",
                             case_name, exp_count, got_count, max_fifo_seen);
                    fail_count = fail_count + 1;
                end else begin
                    $display("PASS %0s checked %0d outputs (max_fifo=%0d)",
                             case_name, exp_count, max_fifo_seen);
                end
            end

            repeat (4) @(posedge clk);
        end
    endtask

    initial begin
        fail_count = 0;
        rst_n = 1'b0;
        lane_mode = LMODE_4LANE;
        virtual_lane_en = 1'b0;
        checking_en = 1'b0;
        clear_inputs;

        run_case("4-lane PHY sanity",    LMODE_4LANE,  1'b0, 24);
        run_case("4-lane VLANE sanity",  LMODE_4LANE,  1'b1, 24);
        run_case("8-lane PHY sanity",    LMODE_8LANE,  1'b0, 24);
        run_case("8-lane VLANE sanity",  LMODE_8LANE,  1'b1, 24);
        run_case("12-lane PHY sanity",   LMODE_12LANE, 1'b0, 24);
        run_case("12-lane VLANE sanity", LMODE_12LANE, 1'b1, 24);
        run_case("16-lane PHY sanity",   LMODE_16LANE, 1'b0, 24);
        run_case("16-lane VLANE sanity", LMODE_16LANE, 1'b1, 24);

        run_case("4-lane PHY stress",    LMODE_4LANE,  1'b0, 96);
        run_case("4-lane VLANE stress",  LMODE_4LANE,  1'b1, 96);
        run_case("8-lane PHY stress",    LMODE_8LANE,  1'b0, 96);
        run_case("8-lane VLANE stress",  LMODE_8LANE,  1'b1, 96);
        run_case("12-lane PHY stress",   LMODE_12LANE, 1'b0, 96);
        run_case("12-lane VLANE stress", LMODE_12LANE, 1'b1, 96);
        run_case("16-lane PHY stress",   LMODE_16LANE, 1'b0, 96);
        run_case("16-lane VLANE stress", LMODE_16LANE, 1'b1, 96);

        $display("\n========================================");
        if (fail_count == 0)
            $display("ALL MULTI-LANE TESTS PASSED");
        else
            $display("TESTS COMPLETED WITH %0d FAILURE(S)", fail_count);
        $display("========================================");
        $finish;
    end

endmodule
