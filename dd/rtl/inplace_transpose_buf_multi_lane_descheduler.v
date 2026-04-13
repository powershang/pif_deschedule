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

    // =========================================================================
    // clk_in domain: Collection FSM + Hold Buffer (unchanged)
    // =========================================================================
    reg [2:0]  in_state;
    reg [2:0]  in_phase;
    reg        valid_in_d1;
    reg        in_cycle_odd_cnt;
    reg        in_cycle_odd_latch;

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

    // clk_in block 1: valid_in_d1
    always @(posedge clk_in or negedge rst_n) begin
        if (!rst_n) valid_in_d1 <= 1'b0;
        else        valid_in_d1 <= valid_in;
    end

    // clk_in block 2: odd/even tracking
    always @(posedge clk_in or negedge rst_n) begin
        if (!rst_n) begin
            in_cycle_odd_cnt   <= 1'b0;
            in_cycle_odd_latch <= 1'b0;
        end else if (in_state == IDLE && valid_in) begin
            if (valid_in & ~valid_in_d1) begin
                in_cycle_odd_latch <= 1'b0;
                in_cycle_odd_cnt   <= 1'b1;
            end else begin
                in_cycle_odd_latch <= in_cycle_odd_cnt;
                in_cycle_odd_cnt   <= ~in_cycle_odd_cnt;
            end
        end
    end

    // clk_in block 3: FSM — in_state, in_phase
    always @(posedge clk_in or negedge rst_n) begin
        if (!rst_n) begin
            in_state <= IDLE;
            in_phase <= 3'd0;
        end else if (in_state != IDLE) begin
            if (!valid_in) begin
                in_state <= IDLE;
                in_phase <= 3'd0;
            end else if (in_phase == phase_max) begin
                in_state <= IDLE;
                in_phase <= 3'd0;
            end else begin
                in_phase <= in_phase + 3'd1;
            end
        end else if (valid_in) begin
            case (lane_mode)
                MODE_4L:  begin in_state <= IDLE;        in_phase <= 3'd0; end
                MODE_8L:  begin in_state <= COLLECT_8L;  in_phase <= 3'd1; end
                MODE_12L: begin in_state <= COLLECT_12L; in_phase <= 3'd1; end
                MODE_16L: begin in_state <= COLLECT_16L; in_phase <= 3'd1; end
                default:  begin in_state <= IDLE;        in_phase <= 3'd0; end
            endcase
        end
    end

    // clk_in block 4: Collection buffers
    always @(posedge clk_in or negedge rst_n) begin
        if (!rst_n) begin
            col_p0_0 <= 0; col_p0_1 <= 0; col_p0_2 <= 0; col_p0_3 <= 0;
            col_p1_0 <= 0; col_p1_1 <= 0; col_p1_2 <= 0; col_p1_3 <= 0;
            col_p2_0 <= 0; col_p2_1 <= 0; col_p2_2 <= 0; col_p2_3 <= 0;
            col_p3_0 <= 0; col_p3_1 <= 0; col_p3_2 <= 0; col_p3_3 <= 0;
        end else begin
            if (in_state == IDLE && valid_in) begin
                col_p0_0 <= din0; col_p0_1 <= din1;
                col_p0_2 <= din2; col_p0_3 <= din3;
            end
            if (in_state != IDLE && valid_in) begin
                case (in_phase)
                    3'd1: begin col_p1_0<=din0; col_p1_1<=din1; col_p1_2<=din2; col_p1_3<=din3; end
                    3'd2: begin col_p2_0<=din0; col_p2_1<=din1; col_p2_2<=din2; col_p2_3<=din3; end
                    3'd3: begin col_p3_0<=din0; col_p3_1<=din1; col_p3_2<=din2; col_p3_3<=din3; end
                    default: ;
                endcase
            end
        end
    end

    // clk_in block 5: Hold buffer + toggle + hold_cycle_odd
    always @(posedge clk_in or negedge rst_n) begin
        if (!rst_n) begin
            hold_p0_0 <= 0; hold_p0_1 <= 0; hold_p0_2 <= 0; hold_p0_3 <= 0;
            hold_p1_0 <= 0; hold_p1_1 <= 0; hold_p1_2 <= 0; hold_p1_3 <= 0;
            hold_p2_0 <= 0; hold_p2_1 <= 0; hold_p2_2 <= 0; hold_p2_3 <= 0;
            hold_p3_0 <= 0; hold_p3_1 <= 0; hold_p3_2 <= 0; hold_p3_3 <= 0;
            hold_cycle_odd  <= 1'b0;
            col_done_toggle <= 1'b0;
        end else begin
            if (in_state == IDLE && valid_in && lane_mode == MODE_4L) begin
                col_done_toggle <= ~col_done_toggle;
                hold_p0_0 <= din0; hold_p0_1 <= din1;
                hold_p0_2 <= din2; hold_p0_3 <= din3;
                if (valid_in & ~valid_in_d1)
                    hold_cycle_odd <= 1'b0;
                else
                    hold_cycle_odd <= in_cycle_odd_cnt;
            end
            if (in_state != IDLE && valid_in && in_phase == phase_max) begin
                col_done_toggle <= ~col_done_toggle;
                hold_cycle_odd  <= in_cycle_odd_latch;
                hold_p0_0 <= col_p0_0; hold_p0_1 <= col_p0_1;
                hold_p0_2 <= col_p0_2; hold_p0_3 <= col_p0_3;
                case (in_state)
                    COLLECT_8L: begin
                        hold_p1_0<=din0; hold_p1_1<=din1;
                        hold_p1_2<=din2; hold_p1_3<=din3;
                    end
                    COLLECT_12L: begin
                        hold_p1_0<=col_p1_0; hold_p1_1<=col_p1_1;
                        hold_p1_2<=col_p1_2; hold_p1_3<=col_p1_3;
                        hold_p2_0<=din0; hold_p2_1<=din1;
                        hold_p2_2<=din2; hold_p2_3<=din3;
                    end
                    COLLECT_16L: begin
                        hold_p1_0<=col_p1_0; hold_p1_1<=col_p1_1;
                        hold_p1_2<=col_p1_2; hold_p1_3<=col_p1_3;
                        hold_p2_0<=col_p2_0; hold_p2_1<=col_p2_1;
                        hold_p2_2<=col_p2_2; hold_p2_3<=col_p2_3;
                        hold_p3_0<=din0; hold_p3_1<=din1;
                        hold_p3_2<=din2; hold_p3_3<=din3;
                    end
                    default: ;
                endcase
            end
        end
    end

    // =========================================================================
    // clk_out domain: Toggle detection + De-rotation + Direct output
    //
    // Each toggle delivers one chunk of de-rotated data from hold_p.
    // Output directly on each toggle — no accumulation.
    // The downstream reverse_inplace_transpose handles the transpose.
    // =========================================================================
    reg        col_done_toggle_d;
    wire       toggle_changed = (col_done_toggle != col_done_toggle_d);

    // Burst boundary detection: sync valid_in into clk_out domain
    reg        valid_in_sync1, valid_in_sync2, valid_in_sync3;
    wire       burst_end = valid_in_sync3 & ~valid_in_sync2;  // falling edge of synced valid_in

    always @(posedge clk_out or negedge rst_n) begin
        if (!rst_n) begin
            valid_in_sync1 <= 1'b0;
            valid_in_sync2 <= 1'b0;
            valid_in_sync3 <= 1'b0;
        end else begin
            valid_in_sync1 <= valid_in;
            valid_in_sync2 <= valid_in_sync1;
            valid_in_sync3 <= valid_in_sync2;
        end
    end

    // De-rotated hold values (wires)
    wire [DATA_W-1:0] derot_at0, derot_at1, derot_at2, derot_at3;
    wire [DATA_W-1:0] derot_ab0, derot_ab1, derot_ab2, derot_ab3;
    wire [DATA_W-1:0] derot_bt0, derot_bt1, derot_bt2, derot_bt3;
    wire [DATA_W-1:0] derot_bb0, derot_bb1, derot_bb2, derot_bb3;

    // 12L de-rotation MUX
    assign derot_at0 = (lane_mode == MODE_12L && hold_cycle_odd) ? hold_p1_0 : hold_p0_0;
    assign derot_at1 = (lane_mode == MODE_12L && hold_cycle_odd) ? hold_p1_1 : hold_p0_1;
    assign derot_at2 = (lane_mode == MODE_12L && hold_cycle_odd) ? hold_p1_2 : hold_p0_2;
    assign derot_at3 = (lane_mode == MODE_12L && hold_cycle_odd) ? hold_p1_3 : hold_p0_3;

    assign derot_ab0 = (lane_mode == MODE_12L && hold_cycle_odd) ? hold_p2_0 : hold_p1_0;
    assign derot_ab1 = (lane_mode == MODE_12L && hold_cycle_odd) ? hold_p2_1 : hold_p1_1;
    assign derot_ab2 = (lane_mode == MODE_12L && hold_cycle_odd) ? hold_p2_2 : hold_p1_2;
    assign derot_ab3 = (lane_mode == MODE_12L && hold_cycle_odd) ? hold_p2_3 : hold_p1_3;

    assign derot_bt0 = (lane_mode == MODE_12L && hold_cycle_odd) ? hold_p0_0 : hold_p2_0;
    assign derot_bt1 = (lane_mode == MODE_12L && hold_cycle_odd) ? hold_p0_1 : hold_p2_1;
    assign derot_bt2 = (lane_mode == MODE_12L && hold_cycle_odd) ? hold_p0_2 : hold_p2_2;
    assign derot_bt3 = (lane_mode == MODE_12L && hold_cycle_odd) ? hold_p0_3 : hold_p2_3;

    assign derot_bb0 = hold_p3_0;
    assign derot_bb1 = hold_p3_1;
    assign derot_bb2 = hold_p3_2;
    assign derot_bb3 = hold_p3_3;

    // Output registers
    reg [DATA_W-1:0] out_a_top0, out_a_top1, out_a_top2, out_a_top3;
    reg [DATA_W-1:0] out_a_bot0, out_a_bot1, out_a_bot2, out_a_bot3;
    reg [DATA_W-1:0] out_b_top0, out_b_top1, out_b_top2, out_b_top3;
    reg [DATA_W-1:0] out_b_bot0, out_b_bot1, out_b_bot2, out_b_bot3;

    always @(posedge clk_out or negedge rst_n) begin
        if (!rst_n) begin
            col_done_toggle_d <= 1'b0;
            valid_out  <= 1'b0;
            out_a_top0 <= 0; out_a_top1 <= 0; out_a_top2 <= 0; out_a_top3 <= 0;
            out_a_bot0 <= 0; out_a_bot1 <= 0; out_a_bot2 <= 0; out_a_bot3 <= 0;
            out_b_top0 <= 0; out_b_top1 <= 0; out_b_top2 <= 0; out_b_top3 <= 0;
            out_b_bot0 <= 0; out_b_bot1 <= 0; out_b_bot2 <= 0; out_b_bot3 <= 0;
        end else begin
            col_done_toggle_d <= col_done_toggle;
            if (toggle_changed) begin
                valid_out  <= 1'b1;
                out_a_top0 <= derot_at0; out_a_top1 <= derot_at1;
                out_a_top2 <= derot_at2; out_a_top3 <= derot_at3;
                out_a_bot0 <= derot_ab0; out_a_bot1 <= derot_ab1;
                out_a_bot2 <= derot_ab2; out_a_bot3 <= derot_ab3;
                out_b_top0 <= derot_bt0; out_b_top1 <= derot_bt1;
                out_b_top2 <= derot_bt2; out_b_top3 <= derot_bt3;
                out_b_bot0 <= derot_bb0; out_b_bot1 <= derot_bb1;
                out_b_bot2 <= derot_bb2; out_b_bot3 <= derot_bb3;
            end else begin
                valid_out <= 1'b0;
            end
        end
    end

    // =========================================================================
    // Output assignments
    // =========================================================================
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
