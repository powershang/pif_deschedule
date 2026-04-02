`timescale 1ns/1ps

module inplace_transpose_buf_multi_lane_descheduler (
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
    output reg         valid_out;
    output [DATA_W-1:0] a_top0, a_top1, a_top2, a_top3;
    output [DATA_W-1:0] a_bot0, a_bot1, a_bot2, a_bot3;
    output [DATA_W-1:0] b_top0, b_top1, b_top2, b_top3;
    output [DATA_W-1:0] b_bot0, b_bot1, b_bot2, b_bot3;
    output [2:0]       dbg_state;
    output [3:0]       dbg_fifo_cnt;

    localparam [2:0] IDLE        = 3'd0;
    localparam [2:0] COLLECT_4L  = 3'd1;
    localparam [2:0] COLLECT_8L  = 3'd2;
    localparam [2:0] COLLECT_12L = 3'd3;
    localparam [2:0] COLLECT_16L = 3'd4;

    localparam [1:0] MODE_4L  = 2'b00;
    localparam [1:0] MODE_8L  = 2'b01;
    localparam [1:0] MODE_12L = 2'b10;
    localparam [1:0] MODE_16L = 2'b11;

    // clk_in domain
    reg [2:0]  in_state;
    reg [2:0]  in_phase;
    reg        in_cycle_odd_cnt;
    reg        in_cycle_odd_latch;
    reg        valid_in_d1;

    reg [DATA_W-1:0] col_p0_0, col_p0_1, col_p0_2, col_p0_3;
    reg [DATA_W-1:0] col_p1_0, col_p1_1, col_p1_2, col_p1_3;
    reg [DATA_W-1:0] col_p2_0, col_p2_1, col_p2_2, col_p2_3;
    reg [DATA_W-1:0] col_p3_0, col_p3_1, col_p3_2, col_p3_3;

    reg [DATA_W-1:0] hold_p0_0, hold_p0_1, hold_p0_2, hold_p0_3;
    reg [DATA_W-1:0] hold_p1_0, hold_p1_1, hold_p1_2, hold_p1_3;
    reg [DATA_W-1:0] hold_p2_0, hold_p2_1, hold_p2_2, hold_p2_3;
    reg [DATA_W-1:0] hold_p3_0, hold_p3_1, hold_p3_2, hold_p3_3;
    reg              hold_cycle_odd;
    reg              col_done_toggle;

    reg [2:0] phase_max;
    always @(*) begin
        case (in_state)
            COLLECT_4L:  phase_max = 3'd0;
            COLLECT_8L:  phase_max = 3'd1;
            COLLECT_12L: phase_max = 3'd2;
            COLLECT_16L: phase_max = 3'd3;
            default:     phase_max = 3'd0;
        endcase
    end

    always @(posedge clk_in or negedge rst_n) begin
        if (!rst_n) valid_in_d1 <= 1'b0;
        else        valid_in_d1 <= valid_in;
    end

    always @(posedge clk_in or negedge rst_n) begin
        if (!rst_n) begin
            in_state           <= IDLE;
            in_phase           <= 3'd0;
            in_cycle_odd_cnt   <= 1'b0;
            in_cycle_odd_latch <= 1'b0;
            col_done_toggle    <= 1'b0;
            col_p0_0 <= 0; col_p0_1 <= 0; col_p0_2 <= 0; col_p0_3 <= 0;
            col_p1_0 <= 0; col_p1_1 <= 0; col_p1_2 <= 0; col_p1_3 <= 0;
            col_p2_0 <= 0; col_p2_1 <= 0; col_p2_2 <= 0; col_p2_3 <= 0;
            col_p3_0 <= 0; col_p3_1 <= 0; col_p3_2 <= 0; col_p3_3 <= 0;
            hold_p0_0 <= 0; hold_p0_1 <= 0; hold_p0_2 <= 0; hold_p0_3 <= 0;
            hold_p1_0 <= 0; hold_p1_1 <= 0; hold_p1_2 <= 0; hold_p1_3 <= 0;
            hold_p2_0 <= 0; hold_p2_1 <= 0; hold_p2_2 <= 0; hold_p2_3 <= 0;
            hold_p3_0 <= 0; hold_p3_1 <= 0; hold_p3_2 <= 0; hold_p3_3 <= 0;
            hold_cycle_odd <= 1'b0;
        end else begin
            if (in_state != IDLE) begin
                if (!valid_in) begin
                    // valid_in dropped mid-collection: abort, discard partial data
                    in_state <= IDLE;
                    in_phase <= 3'd0;
                end else begin
                    case (in_phase)
                        3'd1: begin col_p1_0<=din0; col_p1_1<=din1; col_p1_2<=din2; col_p1_3<=din3; end
                        3'd2: begin col_p2_0<=din0; col_p2_1<=din1; col_p2_2<=din2; col_p2_3<=din3; end
                        3'd3: begin col_p3_0<=din0; col_p3_1<=din1; col_p3_2<=din2; col_p3_3<=din3; end
                        default: ;
                    endcase
                    if (in_phase == phase_max) begin
                        in_state <= IDLE;
                        in_phase <= 3'd0;
                        col_done_toggle <= ~col_done_toggle;
                        hold_cycle_odd  <= in_cycle_odd_latch;
                        hold_p0_0<=col_p0_0; hold_p0_1<=col_p0_1; hold_p0_2<=col_p0_2; hold_p0_3<=col_p0_3;
                        case (in_state)
                            COLLECT_8L: begin
                                hold_p1_0<=din0; hold_p1_1<=din1; hold_p1_2<=din2; hold_p1_3<=din3;
                            end
                            COLLECT_12L: begin
                                hold_p1_0<=col_p1_0; hold_p1_1<=col_p1_1; hold_p1_2<=col_p1_2; hold_p1_3<=col_p1_3;
                                hold_p2_0<=din0; hold_p2_1<=din1; hold_p2_2<=din2; hold_p2_3<=din3;
                            end
                            COLLECT_16L: begin
                                hold_p1_0<=col_p1_0; hold_p1_1<=col_p1_1; hold_p1_2<=col_p1_2; hold_p1_3<=col_p1_3;
                                hold_p2_0<=col_p2_0; hold_p2_1<=col_p2_1; hold_p2_2<=col_p2_2; hold_p2_3<=col_p2_3;
                                hold_p3_0<=din0; hold_p3_1<=din1; hold_p3_2<=din2; hold_p3_3<=din3;
                            end
                            default: ;
                        endcase
                    end else begin
                        in_phase <= in_phase + 3'd1;
                    end
                end
            end else if (valid_in) begin
                col_p0_0 <= din0; col_p0_1 <= din1;
                col_p0_2 <= din2; col_p0_3 <= din3;
                if (valid_in & ~valid_in_d1) begin
                    in_cycle_odd_latch <= 1'b0;
                    in_cycle_odd_cnt   <= 1'b1;
                end else begin
                    in_cycle_odd_latch <= in_cycle_odd_cnt;
                    in_cycle_odd_cnt   <= ~in_cycle_odd_cnt;
                end
                case (lane_mode)
                    MODE_4L: begin
                        in_state <= IDLE; in_phase <= 3'd0;
                        col_done_toggle <= ~col_done_toggle;
                        hold_p0_0<=din0; hold_p0_1<=din1; hold_p0_2<=din2; hold_p0_3<=din3;
                        if (valid_in & ~valid_in_d1)
                            hold_cycle_odd <= 1'b0;
                        else
                            hold_cycle_odd <= in_cycle_odd_cnt;
                    end
                    MODE_8L:  begin in_state <= COLLECT_8L;  in_phase <= 3'd1; end
                    MODE_12L: begin in_state <= COLLECT_12L; in_phase <= 3'd1; end
                    MODE_16L: begin in_state <= COLLECT_16L; in_phase <= 3'd1; end
                    default:  begin in_state <= IDLE;        in_phase <= 3'd0; end
                endcase
            end
        end
    end

    // clk_out domain
    reg        out_valid;
    reg        col_done_toggle_d;
    reg [DATA_W-1:0] out_a_top0, out_a_top1, out_a_top2, out_a_top3;
    reg [DATA_W-1:0] out_a_bot0, out_a_bot1, out_a_bot2, out_a_bot3;
    reg [DATA_W-1:0] out_b_top0, out_b_top1, out_b_top2, out_b_top3;
    reg [DATA_W-1:0] out_b_bot0, out_b_bot1, out_b_bot2, out_b_bot3;

    wire toggle_changed = (col_done_toggle != col_done_toggle_d);

    always @(posedge clk_out or negedge rst_n) begin
        if (!rst_n) begin
            out_valid         <= 1'b0;
            col_done_toggle_d <= 1'b0;
            out_a_top0 <= 0; out_a_top1 <= 0; out_a_top2 <= 0; out_a_top3 <= 0;
            out_a_bot0 <= 0; out_a_bot1 <= 0; out_a_bot2 <= 0; out_a_bot3 <= 0;
            out_b_top0 <= 0; out_b_top1 <= 0; out_b_top2 <= 0; out_b_top3 <= 0;
            out_b_bot0 <= 0; out_b_bot1 <= 0; out_b_bot2 <= 0; out_b_bot3 <= 0;
        end else begin
            col_done_toggle_d <= col_done_toggle;
            if (toggle_changed) begin
                out_valid <= 1'b1;
                case (lane_mode)
                    MODE_4L: begin
                        out_a_top0<=hold_p0_0; out_a_top1<=hold_p0_1;
                        out_a_top2<=hold_p0_2; out_a_top3<=hold_p0_3;
                    end
                    MODE_8L: begin
                        out_a_top0<=hold_p0_0; out_a_top1<=hold_p0_1;
                        out_a_top2<=hold_p0_2; out_a_top3<=hold_p0_3;
                        out_a_bot0<=hold_p1_0; out_a_bot1<=hold_p1_1;
                        out_a_bot2<=hold_p1_2; out_a_bot3<=hold_p1_3;
                    end
                    MODE_12L: begin
                        if (!hold_cycle_odd) begin
                            out_a_top0<=hold_p0_0; out_a_top1<=hold_p0_1;
                            out_a_top2<=hold_p0_2; out_a_top3<=hold_p0_3;
                            out_a_bot0<=hold_p1_0; out_a_bot1<=hold_p1_1;
                            out_a_bot2<=hold_p1_2; out_a_bot3<=hold_p1_3;
                            out_b_top0<=hold_p2_0; out_b_top1<=hold_p2_1;
                            out_b_top2<=hold_p2_2; out_b_top3<=hold_p2_3;
                        end else begin
                            out_a_top0<=hold_p1_0; out_a_top1<=hold_p1_1;
                            out_a_top2<=hold_p1_2; out_a_top3<=hold_p1_3;
                            out_a_bot0<=hold_p2_0; out_a_bot1<=hold_p2_1;
                            out_a_bot2<=hold_p2_2; out_a_bot3<=hold_p2_3;
                            out_b_top0<=hold_p0_0; out_b_top1<=hold_p0_1;
                            out_b_top2<=hold_p0_2; out_b_top3<=hold_p0_3;
                        end
                    end
                    MODE_16L: begin
                        out_a_top0<=hold_p0_0; out_a_top1<=hold_p0_1;
                        out_a_top2<=hold_p0_2; out_a_top3<=hold_p0_3;
                        out_a_bot0<=hold_p1_0; out_a_bot1<=hold_p1_1;
                        out_a_bot2<=hold_p1_2; out_a_bot3<=hold_p1_3;
                        out_b_top0<=hold_p2_0; out_b_top1<=hold_p2_1;
                        out_b_top2<=hold_p2_2; out_b_top3<=hold_p2_3;
                        out_b_bot0<=hold_p3_0; out_b_bot1<=hold_p3_1;
                        out_b_bot2<=hold_p3_2; out_b_bot3<=hold_p3_3;
                    end
                    default: out_valid <= 1'b0;
                endcase
            end else begin
                out_valid <= 1'b0;
            end
        end
    end

    assign valid_out = out_valid;
    assign a_top0 = out_a_top0; assign a_top1 = out_a_top1;
    assign a_top2 = out_a_top2; assign a_top3 = out_a_top3;
    assign a_bot0 = out_a_bot0; assign a_bot1 = out_a_bot1;
    assign a_bot2 = out_a_bot2; assign a_bot3 = out_a_bot3;
    assign b_top0 = out_b_top0; assign b_top1 = out_b_top1;
    assign b_top2 = out_b_top2; assign b_top3 = out_b_top3;
    assign b_bot0 = out_b_bot0; assign b_bot1 = out_b_bot1;
    assign b_bot2 = out_b_bot2; assign b_bot3 = out_b_bot3;
    assign dbg_state    = in_state;
    assign dbg_fifo_cnt = {1'b0, in_phase};

endmodule
