`timescale 1ns/1ps

module inplace_transpose_buf_multi_lane_scheduler (
    clk_in, clk_out, rst_n, lane_mode,
    a_valid_in, a_top0, a_top1, a_top2, a_top3,
                a_bot0, a_bot1, a_bot2, a_bot3,
    b_valid_in, b_top0, b_top1, b_top2, b_top3,
                b_bot0, b_bot1, b_bot2, b_bot3,
    valid_out, dout0, dout1, dout2, dout3,
    dbg_state, dbg_fifo_cnt
);
    parameter DATA_W = 32;

    input              clk_in, clk_out, rst_n;
    input  [1:0]       lane_mode;
    input              a_valid_in;
    input  [DATA_W-1:0] a_top0, a_top1, a_top2, a_top3;
    input  [DATA_W-1:0] a_bot0, a_bot1, a_bot2, a_bot3;
    input              b_valid_in;
    input  [DATA_W-1:0] b_top0, b_top1, b_top2, b_top3;
    input  [DATA_W-1:0] b_bot0, b_bot1, b_bot2, b_bot3;
    output             valid_out;
    output [DATA_W-1:0] dout0, dout1, dout2, dout3;
    output [2:0]       dbg_state;
    output [3:0]       dbg_fifo_cnt;

    localparam [2:0] IDLE      = 3'd0;
    localparam [2:0] SCHED_4L  = 3'd1;
    localparam [2:0] SCHED_8L  = 3'd2;
    localparam [2:0] SCHED_12L = 3'd3;
    localparam [2:0] SCHED_16L = 3'd4;

    localparam [1:0] MODE_4L  = 2'b00;
    localparam [1:0] MODE_8L  = 2'b01;
    localparam [1:0] MODE_12L = 2'b10;
    localparam [1:0] MODE_16L = 2'b11;

    // clk_in domain: Input Latch
    reg [DATA_W-1:0] lat_a_top0, lat_a_top1, lat_a_top2, lat_a_top3;
    reg [DATA_W-1:0] lat_a_bot0, lat_a_bot1, lat_a_bot2, lat_a_bot3;
    reg [DATA_W-1:0] lat_b_top0, lat_b_top1, lat_b_top2, lat_b_top3;
    reg [DATA_W-1:0] lat_b_bot0, lat_b_bot1, lat_b_bot2, lat_b_bot3;

    always @(posedge clk_in or negedge rst_n) begin
        if (!rst_n) begin
            lat_a_top0 <= 0; lat_a_top1 <= 0; lat_a_top2 <= 0; lat_a_top3 <= 0;
            lat_a_bot0 <= 0; lat_a_bot1 <= 0; lat_a_bot2 <= 0; lat_a_bot3 <= 0;
        end else if (a_valid_in) begin
            lat_a_top0 <= a_top0; lat_a_top1 <= a_top1;
            lat_a_top2 <= a_top2; lat_a_top3 <= a_top3;
            lat_a_bot0 <= a_bot0; lat_a_bot1 <= a_bot1;
            lat_a_bot2 <= a_bot2; lat_a_bot3 <= a_bot3;
        end
    end

    always @(posedge clk_in or negedge rst_n) begin
        if (!rst_n) begin
            lat_b_top0 <= 0; lat_b_top1 <= 0; lat_b_top2 <= 0; lat_b_top3 <= 0;
            lat_b_bot0 <= 0; lat_b_bot1 <= 0; lat_b_bot2 <= 0; lat_b_bot3 <= 0;
        end else if (b_valid_in) begin
            lat_b_top0 <= b_top0; lat_b_top1 <= b_top1;
            lat_b_top2 <= b_top2; lat_b_top3 <= b_top3;
            lat_b_bot0 <= b_bot0; lat_b_bot1 <= b_bot1;
            lat_b_bot2 <= b_bot2; lat_b_bot3 <= b_bot3;
        end
    end

    // clk_in: a_valid_w1t, in_cycle_odd
    reg in_cycle_odd;
    reg a_valid_w1t;

    always @(posedge clk_in or negedge rst_n) begin
        if (!rst_n) a_valid_w1t <= 1'b0;
        else        a_valid_w1t <= a_valid_in;
    end

    always @(posedge clk_in or negedge rst_n) begin
        if (!rst_n)                          in_cycle_odd <= 1'b0;
        else if (a_valid_in & ~a_valid_w1t)  in_cycle_odd <= 1'b0;
        else if (a_valid_in)                 in_cycle_odd <= ~in_cycle_odd;
    end

    // clk_out domain: hold buffer + phase FSM + output
    reg [DATA_W-1:0] hold_a_top0, hold_a_top1, hold_a_top2, hold_a_top3;
    reg [DATA_W-1:0] hold_a_bot0, hold_a_bot1, hold_a_bot2, hold_a_bot3;
    reg [DATA_W-1:0] hold_b_top0, hold_b_top1, hold_b_top2, hold_b_top3;
    reg [DATA_W-1:0] hold_b_bot0, hold_b_bot1, hold_b_bot2, hold_b_bot3;

    reg [2:0]  out_phase;
    reg [2:0]  out_state;
    reg        out_cycle_odd_cnt;
    reg        win_trigger_prev;  // for fresh burst detection in clk_out
    reg        out_cycle_odd_latch;
    wire       in_cycle_odd_latch = out_cycle_odd_latch;

    reg [2:0] phase_max;
    always @(*) begin
        case (out_state)
            SCHED_4L:  phase_max = 3'd0;
            SCHED_8L:  phase_max = 3'd1;
            SCHED_12L: phase_max = 3'd2;
            SCHED_16L: phase_max = 3'd3;
            default:   phase_max = 3'd0;
        endcase
    end

    wire win_trigger = a_valid_w1t;

    reg        sched_valid;
    reg [DATA_W-1:0] sched_dout0, sched_dout1, sched_dout2, sched_dout3;

    always @(posedge clk_out or negedge rst_n) begin
        if (!rst_n) begin
            out_phase           <= 3'd0;
            out_state           <= IDLE;
            out_cycle_odd_cnt   <= 1'b0;
            out_cycle_odd_latch <= 1'b0;
            win_trigger_prev    <= 1'b0;
            sched_valid         <= 1'b0;
            sched_dout0 <= 0; sched_dout1 <= 0; sched_dout2 <= 0; sched_dout3 <= 0;
            hold_a_top0 <= 0; hold_a_top1 <= 0; hold_a_top2 <= 0; hold_a_top3 <= 0;
            hold_a_bot0 <= 0; hold_a_bot1 <= 0; hold_a_bot2 <= 0; hold_a_bot3 <= 0;
            hold_b_top0 <= 0; hold_b_top1 <= 0; hold_b_top2 <= 0; hold_b_top3 <= 0;
            hold_b_bot0 <= 0; hold_b_bot1 <= 0; hold_b_bot2 <= 0; hold_b_bot3 <= 0;
        end else begin
            win_trigger_prev <= win_trigger;

            if (out_state != IDLE) begin
                sched_valid <= 1'b1;
                case (out_state)
                    SCHED_8L: begin
                        sched_dout0 <= hold_a_bot0; sched_dout1 <= hold_a_bot1;
                        sched_dout2 <= hold_a_bot2; sched_dout3 <= hold_a_bot3;
                    end
                    SCHED_16L: begin
                        case (out_phase)
                            3'd1: begin sched_dout0<=hold_a_bot0; sched_dout1<=hold_a_bot1; sched_dout2<=hold_a_bot2; sched_dout3<=hold_a_bot3; end
                            3'd2: begin sched_dout0<=hold_b_top0; sched_dout1<=hold_b_top1; sched_dout2<=hold_b_top2; sched_dout3<=hold_b_top3; end
                            3'd3: begin sched_dout0<=hold_b_bot0; sched_dout1<=hold_b_bot1; sched_dout2<=hold_b_bot2; sched_dout3<=hold_b_bot3; end
                            default: begin sched_dout0<=0; sched_dout1<=0; sched_dout2<=0; sched_dout3<=0; end
                        endcase
                    end
                    SCHED_12L: begin
                        if (!in_cycle_odd_latch) begin
                            case (out_phase)
                                3'd1: begin sched_dout0<=hold_a_bot0; sched_dout1<=hold_a_bot1; sched_dout2<=hold_a_bot2; sched_dout3<=hold_a_bot3; end
                                3'd2: begin sched_dout0<=hold_b_top0; sched_dout1<=hold_b_top1; sched_dout2<=hold_b_top2; sched_dout3<=hold_b_top3; end
                                default: begin sched_dout0<=0; sched_dout1<=0; sched_dout2<=0; sched_dout3<=0; end
                            endcase
                        end else begin
                            case (out_phase)
                                3'd1: begin sched_dout0<=hold_a_top0; sched_dout1<=hold_a_top1; sched_dout2<=hold_a_top2; sched_dout3<=hold_a_top3; end
                                3'd2: begin sched_dout0<=hold_a_bot0; sched_dout1<=hold_a_bot1; sched_dout2<=hold_a_bot2; sched_dout3<=hold_a_bot3; end
                                default: begin sched_dout0<=0; sched_dout1<=0; sched_dout2<=0; sched_dout3<=0; end
                            endcase
                        end
                    end
                    default: begin
                        sched_dout0 <= 0; sched_dout1 <= 0; sched_dout2 <= 0; sched_dout3 <= 0;
                    end
                endcase
                if (out_phase == phase_max) begin
                    out_state <= IDLE;
                    out_phase <= 3'd0;
                end else begin
                    out_phase <= out_phase + 3'd1;
                end
            end else if (win_trigger) begin
                if (!win_trigger_prev) begin
                    // Fresh burst: reset odd counter, latch even
                    out_cycle_odd_latch <= 1'b0;
                    out_cycle_odd_cnt   <= 1'b1;
                end else begin
                    out_cycle_odd_latch <= out_cycle_odd_cnt;
                    out_cycle_odd_cnt   <= ~out_cycle_odd_cnt;
                end
                hold_a_top0 <= lat_a_top0; hold_a_top1 <= lat_a_top1;
                hold_a_top2 <= lat_a_top2; hold_a_top3 <= lat_a_top3;
                hold_a_bot0 <= lat_a_bot0; hold_a_bot1 <= lat_a_bot1;
                hold_a_bot2 <= lat_a_bot2; hold_a_bot3 <= lat_a_bot3;
                hold_b_top0 <= lat_b_top0; hold_b_top1 <= lat_b_top1;
                hold_b_top2 <= lat_b_top2; hold_b_top3 <= lat_b_top3;
                hold_b_bot0 <= lat_b_bot0; hold_b_bot1 <= lat_b_bot1;
                hold_b_bot2 <= lat_b_bot2; hold_b_bot3 <= lat_b_bot3;
                sched_valid <= 1'b1;
                case (lane_mode)
                    MODE_4L: begin
                        out_state <= IDLE; out_phase <= 3'd0;
                        sched_dout0 <= lat_a_top0; sched_dout1 <= lat_a_top1;
                        sched_dout2 <= lat_a_top2; sched_dout3 <= lat_a_top3;
                    end
                    MODE_8L: begin
                        out_state <= SCHED_8L; out_phase <= 3'd1;
                        sched_dout0 <= lat_a_top0; sched_dout1 <= lat_a_top1;
                        sched_dout2 <= lat_a_top2; sched_dout3 <= lat_a_top3;
                    end
                    MODE_12L: begin
                        out_state <= SCHED_12L; out_phase <= 3'd1;
                        if (!out_cycle_odd_cnt) begin
                            sched_dout0 <= lat_a_top0; sched_dout1 <= lat_a_top1;
                            sched_dout2 <= lat_a_top2; sched_dout3 <= lat_a_top3;
                        end else begin
                            sched_dout0 <= lat_b_top0; sched_dout1 <= lat_b_top1;
                            sched_dout2 <= lat_b_top2; sched_dout3 <= lat_b_top3;
                        end
                    end
                    MODE_16L: begin
                        out_state <= SCHED_16L; out_phase <= 3'd1;
                        sched_dout0 <= lat_a_top0; sched_dout1 <= lat_a_top1;
                        sched_dout2 <= lat_a_top2; sched_dout3 <= lat_a_top3;
                    end
                    default: begin
                        out_state <= IDLE; out_phase <= 3'd0;
                        sched_valid <= 1'b0;
                    end
                endcase
            end else begin
                sched_valid <= 1'b0;
            end
        end
    end

    assign valid_out    = sched_valid;
    assign dout0        = sched_dout0;
    assign dout1        = sched_dout1;
    assign dout2        = sched_dout2;
    assign dout3        = sched_dout3;
    assign dbg_state    = out_state;
    assign dbg_fifo_cnt = {1'b0, out_phase};

endmodule
