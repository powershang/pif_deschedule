`timescale 1ns/1ps

// =============================================================================
// Module: inplace_transpose_buf_multi_lane_descheduler_top
// Description: Descheduler + Lane Compactor combined block
//   - u_desched: 4-lane fast → N-lane slow deserialization
//   - u_compact: merges 2 consecutive outputs into 1 full output
// =============================================================================

module inplace_transpose_buf_multi_lane_descheduler_top (
    clk_in, clk_out, rst_n, lane_mode, valid_in,
    din0, din1, din2, din3,
    valid_out,
    a_top0, a_top1, a_top2, a_top3,
    a_bot0, a_bot1, a_bot2, a_bot3,
    b_top0, b_top1, b_top2, b_top3,
    b_bot0, b_bot1, b_bot2, b_bot3,
    dbg_state, dbg_fifo_cnt
);
    parameter DATA_W = 32;

    input              clk_in, clk_out, rst_n;
    input  [1:0]       lane_mode;
    input              valid_in;
    input  [DATA_W-1:0] din0, din1, din2, din3;
    output             valid_out;
    output [DATA_W-1:0] a_top0, a_top1, a_top2, a_top3;
    output [DATA_W-1:0] a_bot0, a_bot1, a_bot2, a_bot3;
    output [DATA_W-1:0] b_top0, b_top1, b_top2, b_top3;
    output [DATA_W-1:0] b_bot0, b_bot1, b_bot2, b_bot3;
    output [2:0]       dbg_state;
    output [3:0]       dbg_fifo_cnt;

    // Descheduler → Compactor internal wires
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

    lane_compactor #(.DATA_W(DATA_W)) u_compact (
        .clk    (clk_out),
        .rst_n  (rst_n),
        .valid_in(ds_valid_out),
        .a_top0_in(ds_a_top0), .a_top1_in(ds_a_top1), .a_top2_in(ds_a_top2), .a_top3_in(ds_a_top3),
        .a_bot0_in(ds_a_bot0), .a_bot1_in(ds_a_bot1), .a_bot2_in(ds_a_bot2), .a_bot3_in(ds_a_bot3),
        .b_top0_in(ds_b_top0), .b_top1_in(ds_b_top1), .b_top2_in(ds_b_top2), .b_top3_in(ds_b_top3),
        .b_bot0_in(ds_b_bot0), .b_bot1_in(ds_b_bot1), .b_bot2_in(ds_b_bot2), .b_bot3_in(ds_b_bot3),
        .valid_out(valid_out),
        .a_top0(a_top0), .a_top1(a_top1), .a_top2(a_top2), .a_top3(a_top3),
        .a_bot0(a_bot0), .a_bot1(a_bot1), .a_bot2(a_bot2), .a_bot3(a_bot3),
        .b_top0(b_top0), .b_top1(b_top1), .b_top2(b_top2), .b_top3(b_top3),
        .b_bot0(b_bot0), .b_bot1(b_bot1), .b_bot2(b_bot2), .b_bot3(b_bot3)
    );

endmodule
