`timescale 1ns/1ps

// =============================================================================
// Module: inplace_transpose_buf_multi_lane_descheduler_top
// Description: Two-stage descheduler + Lane Compactor
//   - u_desched: Stage 1 — collection FSM + de-rotation (chunk output)
//   - u_rev_a:   Stage 2A — reverse transpose for Group A (all modes)
//   - u_rev_b:   Stage 2B — reverse transpose for Group B (12L/16L only)
//   - u_compact: Lane compactor (unchanged)
// =============================================================================

module inplace_transpose_buf_multi_lane_descheduler_top (
    clk_in, clk_out, clk_out_div2, rst_n, lane_mode, virtual_lane_en, valid_in,
    din0, din1, din2, din3,
    lane_len_0,  lane_len_1,  lane_len_2,  lane_len_3,
    lane_len_4,  lane_len_5,  lane_len_6,  lane_len_7,
    lane_len_8,  lane_len_9,  lane_len_10, lane_len_11,
    lane_len_12, lane_len_13, lane_len_14, lane_len_15,
    valid_out,
    a_top0, a_top1, a_top2, a_top3,
    a_bot0, a_bot1, a_bot2, a_bot3,
    b_top0, b_top1, b_top2, b_top3,
    b_bot0, b_bot1, b_bot2, b_bot3,
    dbg_state, dbg_fifo_cnt
);
    parameter DATA_W = 32;
    parameter LEN_W  = 13;

    input              clk_in, clk_out, clk_out_div2, rst_n;
    input  [1:0]       lane_mode;
    input              virtual_lane_en;   // 0 = MODE_PHY, 1 = MODE_VLANE
    input              valid_in;
    input  [DATA_W-1:0] din0, din1, din2, din3;
    // Per-lane length limiter (passes straight to lane_compactor).
    // Lane <-> bit mapping (matches valid_out[15:0]):
    //   0..3   a_top0..3      4..7   a_bot0..3
    //   8..11  b_top0..3      12..15 b_bot0..3
    input  [LEN_W-1:0] lane_len_0,  lane_len_1,  lane_len_2,  lane_len_3;
    input  [LEN_W-1:0] lane_len_4,  lane_len_5,  lane_len_6,  lane_len_7;
    input  [LEN_W-1:0] lane_len_8,  lane_len_9,  lane_len_10, lane_len_11;
    input  [LEN_W-1:0] lane_len_12, lane_len_13, lane_len_14, lane_len_15;
    output [15:0]      valid_out;
    output [DATA_W-1:0] a_top0, a_top1, a_top2, a_top3;
    output [DATA_W-1:0] a_bot0, a_bot1, a_bot2, a_bot3;
    output [DATA_W-1:0] b_top0, b_top1, b_top2, b_top3;
    output [DATA_W-1:0] b_bot0, b_bot1, b_bot2, b_bot3;
    output [2:0]       dbg_state;
    output [3:0]       dbg_fifo_cnt;

    // =========================================================================
    // Lane config mapping
    // =========================================================================
    localparam LANE8 = 1'b0;
    localparam LANE4 = 1'b1;
    localparam [1:0] MODE_4L  = 2'b00;
    localparam [1:0] MODE_16L = 2'b11;

    wire lane_cfg_a = (lane_mode == MODE_4L) ? LANE4 : LANE8;
    wire lane_cfg_b = (lane_mode == MODE_16L) ? LANE8 : LANE4;

    // =========================================================================
    // Stage 1: Descheduler (collection FSM + de-rotation, chunk output)
    // =========================================================================
    wire               ds_valid_out;
    wire [DATA_W-1:0]  ds_a_top0, ds_a_top1, ds_a_top2, ds_a_top3;
    wire [DATA_W-1:0]  ds_a_bot0, ds_a_bot1, ds_a_bot2, ds_a_bot3;
    wire [DATA_W-1:0]  ds_b_top0, ds_b_top1, ds_b_top2, ds_b_top3;
    wire [DATA_W-1:0]  ds_b_bot0, ds_b_bot1, ds_b_bot2, ds_b_bot3;

    inplace_transpose_buf_multi_lane_descheduler #(.DATA_W(DATA_W)) u_desched (
        .clk_in     (clk_in),
        .clk_out    (clk_out),
        .rst_n      (rst_n),
        .lane_mode  (lane_mode),
        .valid_in   (valid_in),
        .din0(din0), .din1(din1), .din2(din2), .din3(din3),
        .valid_out  (ds_valid_out),
        .a_top0(ds_a_top0), .a_top1(ds_a_top1), .a_top2(ds_a_top2), .a_top3(ds_a_top3),
        .a_bot0(ds_a_bot0), .a_bot1(ds_a_bot1), .a_bot2(ds_a_bot2), .a_bot3(ds_a_bot3),
        .b_top0(ds_b_top0), .b_top1(ds_b_top1), .b_top2(ds_b_top2), .b_top3(ds_b_top3),
        .b_bot0(ds_b_bot0), .b_bot1(ds_b_bot1), .b_bot2(ds_b_bot2), .b_bot3(ds_b_bot3),
        .dbg_state  (dbg_state),
        .dbg_fifo_cnt(dbg_fifo_cnt)
    );

    // =========================================================================
    // Stage 2A: Reverse inplace transpose — Group A (all modes)
    // =========================================================================
    wire               rev_a_valid_out;
    wire [DATA_W-1:0]  rev_a_dout0, rev_a_dout1, rev_a_dout2, rev_a_dout3;
    wire [DATA_W-1:0]  rev_a_dout4, rev_a_dout5, rev_a_dout6, rev_a_dout7;

    reverse_inplace_transpose #(.DATA_W(DATA_W)) u_rev_a (
        .clk       (clk_out),
        .rst_n     (rst_n),
        .lane_cfg  (lane_cfg_a),
        .mode      (virtual_lane_en),
        .valid_in  (ds_valid_out),
        .din_top0  (ds_a_top0), .din_top1(ds_a_top1),
        .din_top2  (ds_a_top2), .din_top3(ds_a_top3),
        .din_bot0  (ds_a_bot0), .din_bot1(ds_a_bot1),
        .din_bot2  (ds_a_bot2), .din_bot3(ds_a_bot3),
        .valid_out (rev_a_valid_out),
        .dout0(rev_a_dout0), .dout1(rev_a_dout1),
        .dout2(rev_a_dout2), .dout3(rev_a_dout3),
        .dout4(rev_a_dout4), .dout5(rev_a_dout5),
        .dout6(rev_a_dout6), .dout7(rev_a_dout7)
    );

    // =========================================================================
    // Stage 2B: Reverse inplace transpose — Group B (12L/16L only)
    // =========================================================================
    wire               b_valid = ds_valid_out & lane_mode[1];  // active for 12L/16L

    wire               rev_b_valid_out;
    wire [DATA_W-1:0]  rev_b_dout0, rev_b_dout1, rev_b_dout2, rev_b_dout3;
    wire [DATA_W-1:0]  rev_b_dout4, rev_b_dout5, rev_b_dout6, rev_b_dout7;

    reverse_inplace_transpose #(.DATA_W(DATA_W)) u_rev_b (
        .clk       (clk_out),
        .rst_n     (rst_n),
        .lane_cfg  (lane_cfg_b),
        .mode      (virtual_lane_en),
        .valid_in  (b_valid),
        .din_top0  (ds_b_top0), .din_top1(ds_b_top1),
        .din_top2  (ds_b_top2), .din_top3(ds_b_top3),
        .din_bot0  (ds_b_bot0), .din_bot1(ds_b_bot1),
        .din_bot2  (ds_b_bot2), .din_bot3(ds_b_bot3),
        .valid_out (rev_b_valid_out),
        .dout0(rev_b_dout0), .dout1(rev_b_dout1),
        .dout2(rev_b_dout2), .dout3(rev_b_dout3),
        .dout4(rev_b_dout4), .dout5(rev_b_dout5),
        .dout6(rev_b_dout6), .dout7(rev_b_dout7)
    );

    // =========================================================================
    // Output mapping: reverse transpose 8-lane → a_top/bot, b_top/bot format
    //   dout[0:3] → top[0:3]
    //   dout[4:7] → bot[0:3]
    // =========================================================================
    wire [DATA_W-1:0] cmp_a_top0, cmp_a_top1, cmp_a_top2, cmp_a_top3;
    wire [DATA_W-1:0] cmp_a_bot0, cmp_a_bot1, cmp_a_bot2, cmp_a_bot3;
    wire [DATA_W-1:0] cmp_b_top0, cmp_b_top1, cmp_b_top2, cmp_b_top3;
    wire [DATA_W-1:0] cmp_b_bot0, cmp_b_bot1, cmp_b_bot2, cmp_b_bot3;

    assign cmp_a_top0 = rev_a_dout0; assign cmp_a_top1 = rev_a_dout1;
    assign cmp_a_top2 = rev_a_dout2; assign cmp_a_top3 = rev_a_dout3;
    assign cmp_a_bot0 = rev_a_dout4; assign cmp_a_bot1 = rev_a_dout5;
    assign cmp_a_bot2 = rev_a_dout6; assign cmp_a_bot3 = rev_a_dout7;

    assign cmp_b_top0 = rev_b_dout0; assign cmp_b_top1 = rev_b_dout1;
    assign cmp_b_top2 = rev_b_dout2; assign cmp_b_top3 = rev_b_dout3;
    assign cmp_b_bot0 = rev_b_dout4; assign cmp_b_bot1 = rev_b_dout5;
    assign cmp_b_bot2 = rev_b_dout6; assign cmp_b_bot3 = rev_b_dout7;

    // =========================================================================
    // Stage 3: Lane Compactor (unchanged)
    // =========================================================================
    lane_compactor #(.DATA_W(DATA_W), .LEN_W(LEN_W)) u_compact (
        .clk_in_fast  (clk_out),
        .clk_out_slow (clk_out_div2),
        .rst_n        (rst_n),
        .valid_in(rev_a_valid_out),
        .a_top0_in(cmp_a_top0), .a_top1_in(cmp_a_top1), .a_top2_in(cmp_a_top2), .a_top3_in(cmp_a_top3),
        .a_bot0_in(cmp_a_bot0), .a_bot1_in(cmp_a_bot1), .a_bot2_in(cmp_a_bot2), .a_bot3_in(cmp_a_bot3),
        .b_top0_in(cmp_b_top0), .b_top1_in(cmp_b_top1), .b_top2_in(cmp_b_top2), .b_top3_in(cmp_b_top3),
        .b_bot0_in(cmp_b_bot0), .b_bot1_in(cmp_b_bot1), .b_bot2_in(cmp_b_bot2), .b_bot3_in(cmp_b_bot3),
        .lane_len_0 (lane_len_0),  .lane_len_1 (lane_len_1),
        .lane_len_2 (lane_len_2),  .lane_len_3 (lane_len_3),
        .lane_len_4 (lane_len_4),  .lane_len_5 (lane_len_5),
        .lane_len_6 (lane_len_6),  .lane_len_7 (lane_len_7),
        .lane_len_8 (lane_len_8),  .lane_len_9 (lane_len_9),
        .lane_len_10(lane_len_10), .lane_len_11(lane_len_11),
        .lane_len_12(lane_len_12), .lane_len_13(lane_len_13),
        .lane_len_14(lane_len_14), .lane_len_15(lane_len_15),
        .valid_out(valid_out),
        .a_top0(a_top0), .a_top1(a_top1), .a_top2(a_top2), .a_top3(a_top3),
        .a_bot0(a_bot0), .a_bot1(a_bot1), .a_bot2(a_bot2), .a_bot3(a_bot3),
        .b_top0(b_top0), .b_top1(b_top1), .b_top2(b_top2), .b_top3(b_top3),
        .b_bot0(b_bot0), .b_bot1(b_bot1), .b_bot2(b_bot2), .b_bot3(b_bot3)
    );

endmodule
