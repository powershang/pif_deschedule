`timescale 1ns/1ps

// =============================================================================
// inplace_transpose_buf_multi_lane_scheduler
// =============================================================================
// N-lane slow -> 4-lane fast serialiser. Legacy function preserved exactly
// (lat_* input latch in clk_in, hold_* double-buffer in clk_out, phase-mux
// FSM, 12L odd/even rotation). This refactor only reorganises the source
// into per-signal always blocks and two-process FSMs; the cycle-by-cycle
// valid_out/dout behavior is bit-identical to the prior revision.
//
// Coding style (Verilog-2001):
//   - One always block per related signal group.
//   - Two-process FSM for out_state / out_phase.
//   - No leading default inside shared always blocks; every branch lists
//     its value explicitly.
//   - Signals that own a dedicated always only enumerate the conditions
//     that actually update them (no forced else).
//   - Async-low reset on every sequential always.
//   - Block label on every always.
// =============================================================================

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

    input              clk_in;
    input              clk_out;
    input              rst_n;
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

    // -------------------------------------------------------------------------
    // Parameters: FSM encoding and lane_mode values
    // -------------------------------------------------------------------------
    localparam [2:0] IDLE      = 3'd0;
    localparam [2:0] SCHED_4L  = 3'd1;  // reserved (MODE_4L never dwells in a drain state)
    localparam [2:0] SCHED_8L  = 3'd2;
    localparam [2:0] SCHED_12L = 3'd3;
    localparam [2:0] SCHED_16L = 3'd4;

    localparam [1:0] MODE_4L   = 2'b00;
    localparam [1:0] MODE_8L   = 2'b01;
    localparam [1:0] MODE_12L  = 2'b10;
    localparam [1:0] MODE_16L  = 2'b11;

    // =========================================================================
    // clk_in domain: input latches and odd/even chunk counter
    // =========================================================================

    // -- lat_a_* : latch a_top/a_bot on a_valid_in
    reg [DATA_W-1:0] lat_a_top0, lat_a_top1, lat_a_top2, lat_a_top3;
    reg [DATA_W-1:0] lat_a_bot0, lat_a_bot1, lat_a_bot2, lat_a_bot3;

    always @(posedge clk_in or negedge rst_n) begin : p_lat_a
        if (!rst_n) begin
            lat_a_top0 <= {DATA_W{1'b0}};
            lat_a_top1 <= {DATA_W{1'b0}};
            lat_a_top2 <= {DATA_W{1'b0}};
            lat_a_top3 <= {DATA_W{1'b0}};
            lat_a_bot0 <= {DATA_W{1'b0}};
            lat_a_bot1 <= {DATA_W{1'b0}};
            lat_a_bot2 <= {DATA_W{1'b0}};
            lat_a_bot3 <= {DATA_W{1'b0}};
        end else if (a_valid_in) begin
            lat_a_top0 <= a_top0;
            lat_a_top1 <= a_top1;
            lat_a_top2 <= a_top2;
            lat_a_top3 <= a_top3;
            lat_a_bot0 <= a_bot0;
            lat_a_bot1 <= a_bot1;
            lat_a_bot2 <= a_bot2;
            lat_a_bot3 <= a_bot3;
        end
    end

    // -- lat_b_* : latch b_top/b_bot on b_valid_in
    reg [DATA_W-1:0] lat_b_top0, lat_b_top1, lat_b_top2, lat_b_top3;
    reg [DATA_W-1:0] lat_b_bot0, lat_b_bot1, lat_b_bot2, lat_b_bot3;

    always @(posedge clk_in or negedge rst_n) begin : p_lat_b
        if (!rst_n) begin
            lat_b_top0 <= {DATA_W{1'b0}};
            lat_b_top1 <= {DATA_W{1'b0}};
            lat_b_top2 <= {DATA_W{1'b0}};
            lat_b_top3 <= {DATA_W{1'b0}};
            lat_b_bot0 <= {DATA_W{1'b0}};
            lat_b_bot1 <= {DATA_W{1'b0}};
            lat_b_bot2 <= {DATA_W{1'b0}};
            lat_b_bot3 <= {DATA_W{1'b0}};
        end else if (b_valid_in) begin
            lat_b_top0 <= b_top0;
            lat_b_top1 <= b_top1;
            lat_b_top2 <= b_top2;
            lat_b_top3 <= b_top3;
            lat_b_bot0 <= b_bot0;
            lat_b_bot1 <= b_bot1;
            lat_b_bot2 <= b_bot2;
            lat_b_bot3 <= b_bot3;
        end
    end

    // -- a_valid_w1t : a_valid_in delayed 1 clk_in cycle (becomes win_trigger on clk_out)
    reg a_valid_w1t;
    always @(posedge clk_in or negedge rst_n) begin : p_a_valid_w1t
        if (!rst_n) a_valid_w1t <= 1'b0;
        else        a_valid_w1t <= a_valid_in;
    end

    // -- in_cycle_odd : clk_in odd/even counter; clears on fresh burst, toggles every a_valid
    reg in_cycle_odd;
    wire a_fresh_burst_in = a_valid_in & ~a_valid_w1t;
    always @(posedge clk_in or negedge rst_n) begin : p_in_cycle_odd
        if (!rst_n)               in_cycle_odd <= 1'b0;
        else if (a_fresh_burst_in) in_cycle_odd <= 1'b0;
        else if (a_valid_in)       in_cycle_odd <= ~in_cycle_odd;
    end

    // =========================================================================
    // clk_out domain
    // =========================================================================

    // -- win_trigger : a_valid_w1t crosses into clk_out (same-PLL integer
    //    divider, not async CDC; see project memory on clk_naming_caveat).
    wire win_trigger = a_valid_w1t;

    // -- win_trigger_prev : 1-cycle delay in clk_out, for fresh-burst detect
    reg win_trigger_prev;
    always @(posedge clk_out or negedge rst_n) begin : p_win_trigger_prev
        if (!rst_n) win_trigger_prev <= 1'b0;
        else        win_trigger_prev <= win_trigger;
    end
    wire fresh_burst_out = win_trigger & ~win_trigger_prev;

    // -------------------------------------------------------------------------
    // FSM: out_state (two-process)
    // -------------------------------------------------------------------------
    reg [2:0] out_state;
    reg [2:0] out_state_d;
    reg [2:0] out_phase;
    reg [2:0] out_phase_d;

    // phase_max for the current out_state
    reg [2:0] phase_max;
    always @(*) begin : p_phase_max
        case (out_state)
            SCHED_4L:  phase_max = 3'd0;
            SCHED_8L:  phase_max = 3'd1;
            SCHED_12L: phase_max = 3'd2;
            SCHED_16L: phase_max = 3'd3;
            default:   phase_max = 3'd0;
        endcase
    end

    // out_state next-state
    //   IDLE + win_trigger : enter SCHED_xL (or stay IDLE for MODE_4L)
    //   SCHED_xL + phase==phase_max : return to IDLE
    always @(*) begin : p_out_state_d
        if (out_state != IDLE) begin
            if (out_phase == phase_max) out_state_d = IDLE;
            else                        out_state_d = out_state;
        end else if (win_trigger) begin
            case (lane_mode)
                MODE_4L:  out_state_d = IDLE;        // 4L fires once, stays IDLE
                MODE_8L:  out_state_d = SCHED_8L;
                MODE_12L: out_state_d = SCHED_12L;
                MODE_16L: out_state_d = SCHED_16L;
                default:  out_state_d = IDLE;
            endcase
        end else begin
            out_state_d = IDLE;
        end
    end

    always @(posedge clk_out or negedge rst_n) begin : p_out_state
        if (!rst_n) out_state <= IDLE;
        else        out_state <= out_state_d;
    end

    // out_phase next-state
    //   SCHED_xL : advance until phase_max, then 0
    //   IDLE + win_trigger to SCHED_xL : start at 1 (first beat was phase 0)
    //   IDLE + win_trigger to MODE_4L  : stay 0
    always @(*) begin : p_out_phase_d
        if (out_state != IDLE) begin
            if (out_phase == phase_max) out_phase_d = 3'd0;
            else                        out_phase_d = out_phase + 3'd1;
        end else if (win_trigger) begin
            case (lane_mode)
                MODE_4L:  out_phase_d = 3'd0;
                MODE_8L:  out_phase_d = 3'd1;
                MODE_12L: out_phase_d = 3'd1;
                MODE_16L: out_phase_d = 3'd1;
                default:  out_phase_d = 3'd0;
            endcase
        end else begin
            out_phase_d = 3'd0;
        end
    end

    always @(posedge clk_out or negedge rst_n) begin : p_out_phase
        if (!rst_n) out_phase <= 3'd0;
        else        out_phase <= out_phase_d;
    end

    // -------------------------------------------------------------------------
    // 12L odd/even rotation counter (clk_out domain)
    //   out_cycle_odd_cnt   : toggles on each IDLE+win_trigger (a new drain
    //                         window starts); fresh burst forces to 1 so the
    //                         FIRST chunk (latched on cycle 0) is read as
    //                         "even" (cnt=0) via the pre-update value.
    //   out_cycle_odd_latch : captures the cnt value at drain-window entry,
    //                         reset on fresh burst. Stays stable across the
    //                         whole SCHED_12L drain window.
    //   IMPORTANT: these update ONLY on IDLE-entering-drain. Inside
    //   SCHED_xL the same win_trigger must not retrigger an update, or 12L
    //   rotation tracking breaks. (Legacy guarded this via if/else chain.)
    // -------------------------------------------------------------------------
    reg out_cycle_odd_cnt;
    reg out_cycle_odd_latch;
    wire in_cycle_odd_latch = out_cycle_odd_latch;

    wire drain_window_start = (out_state == IDLE) & win_trigger;

    always @(posedge clk_out or negedge rst_n) begin : p_out_cycle_odd_cnt
        if (!rst_n)                              out_cycle_odd_cnt <= 1'b0;
        else if (drain_window_start & ~win_trigger_prev)
                                                 out_cycle_odd_cnt <= 1'b1;
        else if (drain_window_start)             out_cycle_odd_cnt <= ~out_cycle_odd_cnt;
    end

    always @(posedge clk_out or negedge rst_n) begin : p_out_cycle_odd_latch
        if (!rst_n)                              out_cycle_odd_latch <= 1'b0;
        else if (drain_window_start & ~win_trigger_prev)
                                                 out_cycle_odd_latch <= 1'b0;
        else if (drain_window_start)             out_cycle_odd_latch <= out_cycle_odd_cnt;
    end

    // -------------------------------------------------------------------------
    // hold_* : clk_out-side double-buffer. Loaded from lat_* on win_trigger
    // while out_state==IDLE (i.e. the trigger that starts a new drain window).
    // -------------------------------------------------------------------------
    reg [DATA_W-1:0] hold_a_top0, hold_a_top1, hold_a_top2, hold_a_top3;
    reg [DATA_W-1:0] hold_a_bot0, hold_a_bot1, hold_a_bot2, hold_a_bot3;
    reg [DATA_W-1:0] hold_b_top0, hold_b_top1, hold_b_top2, hold_b_top3;
    reg [DATA_W-1:0] hold_b_bot0, hold_b_bot1, hold_b_bot2, hold_b_bot3;

    wire hold_load_en = (out_state == IDLE) & win_trigger;

    always @(posedge clk_out or negedge rst_n) begin : p_hold
        if (!rst_n) begin
            hold_a_top0 <= {DATA_W{1'b0}};
            hold_a_top1 <= {DATA_W{1'b0}};
            hold_a_top2 <= {DATA_W{1'b0}};
            hold_a_top3 <= {DATA_W{1'b0}};
            hold_a_bot0 <= {DATA_W{1'b0}};
            hold_a_bot1 <= {DATA_W{1'b0}};
            hold_a_bot2 <= {DATA_W{1'b0}};
            hold_a_bot3 <= {DATA_W{1'b0}};
            hold_b_top0 <= {DATA_W{1'b0}};
            hold_b_top1 <= {DATA_W{1'b0}};
            hold_b_top2 <= {DATA_W{1'b0}};
            hold_b_top3 <= {DATA_W{1'b0}};
            hold_b_bot0 <= {DATA_W{1'b0}};
            hold_b_bot1 <= {DATA_W{1'b0}};
            hold_b_bot2 <= {DATA_W{1'b0}};
            hold_b_bot3 <= {DATA_W{1'b0}};
        end else if (hold_load_en) begin
            hold_a_top0 <= lat_a_top0;
            hold_a_top1 <= lat_a_top1;
            hold_a_top2 <= lat_a_top2;
            hold_a_top3 <= lat_a_top3;
            hold_a_bot0 <= lat_a_bot0;
            hold_a_bot1 <= lat_a_bot1;
            hold_a_bot2 <= lat_a_bot2;
            hold_a_bot3 <= lat_a_bot3;
            hold_b_top0 <= lat_b_top0;
            hold_b_top1 <= lat_b_top1;
            hold_b_top2 <= lat_b_top2;
            hold_b_top3 <= lat_b_top3;
            hold_b_bot0 <= lat_b_bot0;
            hold_b_bot1 <= lat_b_bot1;
            hold_b_bot2 <= lat_b_bot2;
            hold_b_bot3 <= lat_b_bot3;
        end
    end

    // -------------------------------------------------------------------------
    // Output mux: sched_dout0..3 (two-process)
    //   During SCHED_xL : source is hold_* per out_phase
    //   During IDLE + win_trigger : source is lat_* (cycle 0 of a new burst)
    //     - 4L : lat_a_top
    //     - 8L : lat_a_top
    //     - 12L: lat_a_top (even chunk) or lat_b_top (odd chunk)
    //     - 16L: lat_a_top
    //   Otherwise dout = 0
    // -------------------------------------------------------------------------
    reg [DATA_W-1:0] sched_dout0_d, sched_dout1_d, sched_dout2_d, sched_dout3_d;
    reg              sched_valid_d;

    always @(*) begin : p_sched_dout_d
        if (out_state != IDLE) begin
            sched_valid_d = 1'b1;
            case (out_state)
                SCHED_8L: begin
                    sched_dout0_d = hold_a_bot0;
                    sched_dout1_d = hold_a_bot1;
                    sched_dout2_d = hold_a_bot2;
                    sched_dout3_d = hold_a_bot3;
                end
                SCHED_16L: begin
                    case (out_phase)
                        3'd1: begin
                            sched_dout0_d = hold_a_bot0;
                            sched_dout1_d = hold_a_bot1;
                            sched_dout2_d = hold_a_bot2;
                            sched_dout3_d = hold_a_bot3;
                        end
                        3'd2: begin
                            sched_dout0_d = hold_b_top0;
                            sched_dout1_d = hold_b_top1;
                            sched_dout2_d = hold_b_top2;
                            sched_dout3_d = hold_b_top3;
                        end
                        3'd3: begin
                            sched_dout0_d = hold_b_bot0;
                            sched_dout1_d = hold_b_bot1;
                            sched_dout2_d = hold_b_bot2;
                            sched_dout3_d = hold_b_bot3;
                        end
                        default: begin
                            sched_dout0_d = {DATA_W{1'b0}};
                            sched_dout1_d = {DATA_W{1'b0}};
                            sched_dout2_d = {DATA_W{1'b0}};
                            sched_dout3_d = {DATA_W{1'b0}};
                        end
                    endcase
                end
                SCHED_12L: begin
                    if (!in_cycle_odd_latch) begin
                        case (out_phase)
                            3'd1: begin
                                sched_dout0_d = hold_a_bot0;
                                sched_dout1_d = hold_a_bot1;
                                sched_dout2_d = hold_a_bot2;
                                sched_dout3_d = hold_a_bot3;
                            end
                            3'd2: begin
                                sched_dout0_d = hold_b_top0;
                                sched_dout1_d = hold_b_top1;
                                sched_dout2_d = hold_b_top2;
                                sched_dout3_d = hold_b_top3;
                            end
                            default: begin
                                sched_dout0_d = {DATA_W{1'b0}};
                                sched_dout1_d = {DATA_W{1'b0}};
                                sched_dout2_d = {DATA_W{1'b0}};
                                sched_dout3_d = {DATA_W{1'b0}};
                            end
                        endcase
                    end else begin
                        case (out_phase)
                            3'd1: begin
                                sched_dout0_d = hold_a_top0;
                                sched_dout1_d = hold_a_top1;
                                sched_dout2_d = hold_a_top2;
                                sched_dout3_d = hold_a_top3;
                            end
                            3'd2: begin
                                sched_dout0_d = hold_a_bot0;
                                sched_dout1_d = hold_a_bot1;
                                sched_dout2_d = hold_a_bot2;
                                sched_dout3_d = hold_a_bot3;
                            end
                            default: begin
                                sched_dout0_d = {DATA_W{1'b0}};
                                sched_dout1_d = {DATA_W{1'b0}};
                                sched_dout2_d = {DATA_W{1'b0}};
                                sched_dout3_d = {DATA_W{1'b0}};
                            end
                        endcase
                    end
                end
                default: begin
                    sched_dout0_d = {DATA_W{1'b0}};
                    sched_dout1_d = {DATA_W{1'b0}};
                    sched_dout2_d = {DATA_W{1'b0}};
                    sched_dout3_d = {DATA_W{1'b0}};
                end
            endcase
        end else if (win_trigger) begin
            // Cycle 0 of a new drain window: emit lat_* directly (before hold_* loads)
            case (lane_mode)
                MODE_4L: begin
                    sched_valid_d = 1'b1;
                    sched_dout0_d = lat_a_top0;
                    sched_dout1_d = lat_a_top1;
                    sched_dout2_d = lat_a_top2;
                    sched_dout3_d = lat_a_top3;
                end
                MODE_8L: begin
                    sched_valid_d = 1'b1;
                    sched_dout0_d = lat_a_top0;
                    sched_dout1_d = lat_a_top1;
                    sched_dout2_d = lat_a_top2;
                    sched_dout3_d = lat_a_top3;
                end
                MODE_12L: begin
                    sched_valid_d = 1'b1;
                    if (!out_cycle_odd_cnt) begin
                        sched_dout0_d = lat_a_top0;
                        sched_dout1_d = lat_a_top1;
                        sched_dout2_d = lat_a_top2;
                        sched_dout3_d = lat_a_top3;
                    end else begin
                        sched_dout0_d = lat_b_top0;
                        sched_dout1_d = lat_b_top1;
                        sched_dout2_d = lat_b_top2;
                        sched_dout3_d = lat_b_top3;
                    end
                end
                MODE_16L: begin
                    sched_valid_d = 1'b1;
                    sched_dout0_d = lat_a_top0;
                    sched_dout1_d = lat_a_top1;
                    sched_dout2_d = lat_a_top2;
                    sched_dout3_d = lat_a_top3;
                end
                default: begin
                    sched_valid_d = 1'b0;
                    sched_dout0_d = {DATA_W{1'b0}};
                    sched_dout1_d = {DATA_W{1'b0}};
                    sched_dout2_d = {DATA_W{1'b0}};
                    sched_dout3_d = {DATA_W{1'b0}};
                end
            endcase
        end else begin
            sched_valid_d = 1'b0;
            sched_dout0_d = {DATA_W{1'b0}};
            sched_dout1_d = {DATA_W{1'b0}};
            sched_dout2_d = {DATA_W{1'b0}};
            sched_dout3_d = {DATA_W{1'b0}};
        end
    end

    reg              sched_valid;
    reg [DATA_W-1:0] sched_dout0, sched_dout1, sched_dout2, sched_dout3;

    always @(posedge clk_out or negedge rst_n) begin : p_sched_valid
        if (!rst_n) sched_valid <= 1'b0;
        else        sched_valid <= sched_valid_d;
    end

    always @(posedge clk_out or negedge rst_n) begin : p_sched_dout
        if (!rst_n) begin
            sched_dout0 <= {DATA_W{1'b0}};
            sched_dout1 <= {DATA_W{1'b0}};
            sched_dout2 <= {DATA_W{1'b0}};
            sched_dout3 <= {DATA_W{1'b0}};
        end else begin
            sched_dout0 <= sched_dout0_d;
            sched_dout1 <= sched_dout1_d;
            sched_dout2 <= sched_dout2_d;
            sched_dout3 <= sched_dout3_d;
        end
    end

    // -------------------------------------------------------------------------
    // Module outputs
    // -------------------------------------------------------------------------
    assign valid_out    = sched_valid;
    assign dout0        = sched_dout0;
    assign dout1        = sched_dout1;
    assign dout2        = sched_dout2;
    assign dout3        = sched_dout3;
    assign dbg_state    = out_state;
    assign dbg_fifo_cnt = {1'b0, out_phase};

endmodule
