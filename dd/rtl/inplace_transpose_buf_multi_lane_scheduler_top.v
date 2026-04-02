`timescale 1ns/1ps

// =============================================================================
// Module: inplace_transpose_buf_multi_lane_scheduler_top
// Description: 4N-Align + Multi-lane Output Pack + Scheduler combined block
//   - u_align:  burst padding to 4N
//   - u_out:    chunk accumulation (2x 8lane_2beat instances)
//   - u_sched:  N-lane slow → 4-lane fast serialization
// =============================================================================

module inplace_transpose_buf_multi_lane_scheduler_top (
    clk_in, clk_out, rst_n, valid_in, lane_mode, virtual_lane_en,
    din0,  din1,  din2,  din3,
    din4,  din5,  din6,  din7,
    din8,  din9,  din10, din11,
    din12, din13, din14, din15,
    align_error_flag,
    valid_out, dout0, dout1, dout2, dout3,
    dbg_state, dbg_fifo_cnt
);

    parameter DATA_W     = 8;

    input              clk_in;
    input              clk_out;
    input              rst_n;
    input              valid_in;
    input  [1:0]       lane_mode;
    input              virtual_lane_en;
    input  [DATA_W-1:0] din0, din1, din2, din3;
    input  [DATA_W-1:0] din4, din5, din6, din7;
    input  [DATA_W-1:0] din8, din9, din10, din11;
    input  [DATA_W-1:0] din12, din13, din14, din15;
    output             align_error_flag;
    output             valid_out;
    output [DATA_W-1:0] dout0, dout1, dout2, dout3;
    output [2:0]       dbg_state;
    output [3:0]       dbg_fifo_cnt;

    wire               a_valid_out;
    wire  [DATA_W-1:0] a_top0, a_top1, a_top2, a_top3;
    wire  [DATA_W-1:0] a_bot0, a_bot1, a_bot2, a_bot3;
    wire               b_valid_out;
    wire  [DATA_W-1:0] b_top0, b_top1, b_top2, b_top3;
    wire  [DATA_W-1:0] b_bot0, b_bot1, b_bot2, b_bot3;
    wire               align_valid_out;
    wire  [DATA_W-1:0] align_dout0, align_dout1, align_dout2, align_dout3;
    wire  [DATA_W-1:0] align_dout4, align_dout5, align_dout6, align_dout7;
    wire  [DATA_W-1:0] align_dout8, align_dout9, align_dout10, align_dout11;
    wire  [DATA_W-1:0] align_dout12, align_dout13, align_dout14, align_dout15;

    lanedata_4n_align_process #(.DATA_W(DATA_W)) u_align (
        .clk(clk_in), .rst_n(rst_n),
        .valid_in(valid_in), .virtual_lane_en(virtual_lane_en),
        .din0(din0), .din1(din1), .din2(din2), .din3(din3),
        .din4(din4), .din5(din5), .din6(din6), .din7(din7),
        .din8(din8), .din9(din9), .din10(din10), .din11(din11),
        .din12(din12), .din13(din13), .din14(din14), .din15(din15),
        .valid_out(align_valid_out),
        .dout0(align_dout0), .dout1(align_dout1), .dout2(align_dout2), .dout3(align_dout3),
        .dout4(align_dout4), .dout5(align_dout5), .dout6(align_dout6), .dout7(align_dout7),
        .dout8(align_dout8), .dout9(align_dout9), .dout10(align_dout10), .dout11(align_dout11),
        .dout12(align_dout12), .dout13(align_dout13), .dout14(align_dout14), .dout15(align_dout15),
        .error_flag(align_error_flag)
    );

    inplace_transpose_buf_multi_lane_out #(.DATA_W(DATA_W)) u_out (
        .clk(clk_in), .rst_n(rst_n),
        .valid_in(align_valid_out), .lane_mode(lane_mode), .virtual_lane_en(virtual_lane_en),
        .din0(align_dout0), .din1(align_dout1), .din2(align_dout2), .din3(align_dout3),
        .din4(align_dout4), .din5(align_dout5), .din6(align_dout6), .din7(align_dout7),
        .din8(align_dout8), .din9(align_dout9), .din10(align_dout10), .din11(align_dout11),
        .din12(align_dout12), .din13(align_dout13), .din14(align_dout14), .din15(align_dout15),
        .a_valid_out(a_valid_out),
        .a_top0(a_top0), .a_top1(a_top1), .a_top2(a_top2), .a_top3(a_top3),
        .a_bot0(a_bot0), .a_bot1(a_bot1), .a_bot2(a_bot2), .a_bot3(a_bot3),
        .b_valid_out(b_valid_out),
        .b_top0(b_top0), .b_top1(b_top1), .b_top2(b_top2), .b_top3(b_top3),
        .b_bot0(b_bot0), .b_bot1(b_bot1), .b_bot2(b_bot2), .b_bot3(b_bot3)
    );

    inplace_transpose_buf_multi_lane_scheduler #(.DATA_W(DATA_W)) u_sched (
        .clk_in(clk_in), .clk_out(clk_out), .rst_n(rst_n),
        .lane_mode(lane_mode),
        .a_valid_in(a_valid_out),
        .a_top0(a_top0), .a_top1(a_top1), .a_top2(a_top2), .a_top3(a_top3),
        .a_bot0(a_bot0), .a_bot1(a_bot1), .a_bot2(a_bot2), .a_bot3(a_bot3),
        .b_valid_in(b_valid_out),
        .b_top0(b_top0), .b_top1(b_top1), .b_top2(b_top2), .b_top3(b_top3),
        .b_bot0(b_bot0), .b_bot1(b_bot1), .b_bot2(b_bot2), .b_bot3(b_bot3),
        .valid_out(valid_out),
        .dout0(dout0), .dout1(dout1), .dout2(dout2), .dout3(dout3),
        .dbg_state(dbg_state), .dbg_fifo_cnt(dbg_fifo_cnt)
    );

endmodule
