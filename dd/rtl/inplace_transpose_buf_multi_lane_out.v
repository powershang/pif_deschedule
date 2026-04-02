`timescale 1ns/1ps

// Multi-lane output pack module.
// Instantiates two inplace_transpose_buf_8lane_2beat child blocks.
// lane_mode selects active configuration:
//   2'b00 = 4-lane  : u_buf_a as LANE4, u_buf_b disabled
//   2'b01 = 8-lane  : u_buf_a as LANE8, u_buf_b disabled
//   2'b10 = 12-lane : u_buf_a as LANE8, u_buf_b as LANE4
//   2'b11 = 16-lane : u_buf_a as LANE8, u_buf_b as LANE8

module inplace_transpose_buf_multi_lane_out (
    clk, rst_n, valid_in, lane_mode, virtual_lane_en,
    din0,  din1,  din2,  din3,  din4,  din5,  din6,  din7,
    din8,  din9,  din10, din11, din12, din13, din14, din15,
    a_valid_out, a_top0, a_top1, a_top2, a_top3,
                 a_bot0, a_bot1, a_bot2, a_bot3,
    b_valid_out, b_top0, b_top1, b_top2, b_top3,
                 b_bot0, b_bot1, b_bot2, b_bot3
);

    parameter DATA_W = 8;

    input              clk;
    input              rst_n;
    input              valid_in;
    input  [1:0]       lane_mode;
    input              virtual_lane_en;
    input  [DATA_W-1:0] din0, din1, din2, din3;
    input  [DATA_W-1:0] din4, din5, din6, din7;
    input  [DATA_W-1:0] din8, din9, din10, din11;
    input  [DATA_W-1:0] din12, din13, din14, din15;
    output             a_valid_out;
    output [DATA_W-1:0] a_top0, a_top1, a_top2, a_top3;
    output [DATA_W-1:0] a_bot0, a_bot1, a_bot2, a_bot3;
    output             b_valid_out;
    output [DATA_W-1:0] b_top0, b_top1, b_top2, b_top3;
    output [DATA_W-1:0] b_bot0, b_bot1, b_bot2, b_bot3;

    localparam LANE8        = 1'b0;
    localparam LANE4        = 1'b1;
    localparam [1:0] MODE_PHY     = 2'b00;
    localparam [1:0] MODE_VLANE   = 2'b01;
    localparam [1:0] LMODE_4LANE  = 2'b00;
    localparam [1:0] LMODE_8LANE  = 2'b01;
    localparam [1:0] LMODE_12LANE = 2'b10;
    localparam [1:0] LMODE_16LANE = 2'b11;

    wire       lane_cfg_a = (lane_mode == LMODE_4LANE) ? LANE4 : LANE8;
    wire       lane_cfg_b = (lane_mode == LMODE_16LANE) ? LANE8 : LANE4;
    wire       valid_in_b = valid_in & lane_mode[1];
    wire [1:0] mode_a     = virtual_lane_en ? MODE_VLANE : MODE_PHY;
    wire [1:0] mode_b     = virtual_lane_en ? MODE_VLANE : MODE_PHY;

    inplace_transpose_buf_8lane_2beat #(.DATA_W(DATA_W)) u_buf_a (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in),
        .lane_cfg(lane_cfg_a), .mode(mode_a),
        .din0(din0), .din1(din1), .din2(din2), .din3(din3),
        .din4(din4), .din5(din5), .din6(din6), .din7(din7),
        .valid_out(a_valid_out),
        .dout_top0(a_top0), .dout_top1(a_top1), .dout_top2(a_top2), .dout_top3(a_top3),
        .dout_bot0(a_bot0), .dout_bot1(a_bot1), .dout_bot2(a_bot2), .dout_bot3(a_bot3)
    );

    inplace_transpose_buf_8lane_2beat #(.DATA_W(DATA_W)) u_buf_b (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in_b),
        .lane_cfg(lane_cfg_b), .mode(mode_b),
        .din0(din8), .din1(din9), .din2(din10), .din3(din11),
        .din4(din12), .din5(din13), .din6(din14), .din7(din15),
        .valid_out(b_valid_out),
        .dout_top0(b_top0), .dout_top1(b_top1), .dout_top2(b_top2), .dout_top3(b_top3),
        .dout_bot0(b_bot0), .dout_bot1(b_bot1), .dout_bot2(b_bot2), .dout_bot3(b_bot3)
    );

endmodule
