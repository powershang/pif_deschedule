// =============================================================================
// Module: inplace_transpose_buf_multi_lane_descheduler
// Description: Reverse of inplace_transpose_buf_multi_lane_scheduler
//   - Receives 4-lane serialized data on fast clock (clk_in)
//   - Reassembles into N-lane output on slow clock (clk_out)
//   - Supports 4/8/12/16 lane modes
//   - 12L mode: undoes the even/odd rotation of the forward scheduler
//   - Both clocks are from the same PLL, no CDC synchronizer needed
//
// Cross-domain handshake:
//   clk_in (fast) collects N/4 phases into col_p* buffers.  When collection
//   completes, it snapshots col_p* into hold_p* and flips col_done_toggle.
//   clk_out (slow) detects the toggle change and latches hold_p* through
//   the de-rotation MUX into the output DFFs.
//
//   The hold buffer prevents data corruption in back-to-back mode: the next
//   collection window may overwrite col_p0 before clk_out samples, but
//   hold_p* remains stable until the next collection completes.
// =============================================================================

module inplace_transpose_buf_multi_lane_descheduler #(
    parameter DATA_W = 32
)(
    input  logic                clk_in,         // fast clock (receives serialized 4-lane data)
    input  logic                clk_out,        // slow clock (outputs reassembled N-lane data)
    input  logic                rst_n,
    input  logic [1:0]          lane_mode,      // 2'b00=4L, 2'b01=8L, 2'b10=12L, 2'b11=16L
    input  logic                valid_in,       // input valid (clk_in domain)
    input  logic [DATA_W-1:0]   din0, din1, din2, din3,

    output logic                valid_out,      // output valid (clk_out domain)
    output logic [DATA_W-1:0]   a_top0, a_top1, a_top2, a_top3,
    output logic [DATA_W-1:0]   a_bot0, a_bot1, a_bot2, a_bot3,
    output logic [DATA_W-1:0]   b_top0, b_top1, b_top2, b_top3,
    output logic [DATA_W-1:0]   b_bot0, b_bot1, b_bot2, b_bot3,
    output logic [2:0]          dbg_state,
    output logic [3:0]          dbg_fifo_cnt
);

    // =========================================================================
    // FSM State Encoding
    // =========================================================================
    localparam [2:0] IDLE        = 3'd0;
    localparam [2:0] COLLECT_4L  = 3'd1;  // unused (4L is single-phase)
    localparam [2:0] COLLECT_8L  = 3'd2;
    localparam [2:0] COLLECT_12L = 3'd3;
    localparam [2:0] COLLECT_16L = 3'd4;

    // lane_mode encoding
    localparam [1:0] MODE_4L  = 2'b00;
    localparam [1:0] MODE_8L  = 2'b01;
    localparam [1:0] MODE_12L = 2'b10;
    localparam [1:0] MODE_16L = 2'b11;

    // =========================================================================
    // clk_in domain: Collection FSM + Phase Buffers + Hold Buffer
    // =========================================================================
    logic [2:0]  in_state;
    logic [2:0]  in_phase;
    logic        in_cycle_odd_cnt;
    logic        in_cycle_odd_latch;
    logic        valid_in_d1;

    // Collection buffers (clk_in domain, incremental writes)
    logic [DATA_W-1:0] col_p0_0, col_p0_1, col_p0_2, col_p0_3;
    logic [DATA_W-1:0] col_p1_0, col_p1_1, col_p1_2, col_p1_3;
    logic [DATA_W-1:0] col_p2_0, col_p2_1, col_p2_2, col_p2_3;
    logic [DATA_W-1:0] col_p3_0, col_p3_1, col_p3_2, col_p3_3;

    // Hold buffers (clk_in domain, snapshot when collection completes)
    // Stable for clk_out to read until next collection completes
    logic [DATA_W-1:0] hold_p0_0, hold_p0_1, hold_p0_2, hold_p0_3;
    logic [DATA_W-1:0] hold_p1_0, hold_p1_1, hold_p1_2, hold_p1_3;
    logic [DATA_W-1:0] hold_p2_0, hold_p2_1, hold_p2_2, hold_p2_3;
    logic [DATA_W-1:0] hold_p3_0, hold_p3_1, hold_p3_2, hold_p3_3;
    logic              hold_cycle_odd;  // snapshot of in_cycle_odd_latch

    // Toggle: flips when collection completes (clk_in domain)
    logic col_done_toggle;

    // phase_max for collection FSM
    logic [2:0] phase_max;
    always_comb begin
        case (in_state)
            COLLECT_4L:  phase_max = 3'd0;
            COLLECT_8L:  phase_max = 3'd1;
            COLLECT_12L: phase_max = 3'd2;
            COLLECT_16L: phase_max = 3'd3;
            default:     phase_max = 3'd0;
        endcase
    end

    // valid_in delayed 1T for rising edge detection (12L odd/even reset)
    always_ff @(posedge clk_in or negedge rst_n) begin
        if (!rst_n) valid_in_d1 <= 1'b0;
        else        valid_in_d1 <= valid_in;
    end

    // --- Collection FSM (clk_in domain) ---
    // When collection completes: snapshot col_p* → hold_p*, flip toggle
    // For the last phase, the din is written directly to hold (NBA: col_p gets
    // the OLD value, so hold_p[last] must use din directly)
    always_ff @(posedge clk_in or negedge rst_n) begin
        if (!rst_n) begin
            in_state          <= IDLE;
            in_phase          <= 3'd0;
            in_cycle_odd_cnt  <= 1'b0;
            in_cycle_odd_latch<= 1'b0;
            col_done_toggle   <= 1'b0;
            col_p0_0 <= '0; col_p0_1 <= '0; col_p0_2 <= '0; col_p0_3 <= '0;
            col_p1_0 <= '0; col_p1_1 <= '0; col_p1_2 <= '0; col_p1_3 <= '0;
            col_p2_0 <= '0; col_p2_1 <= '0; col_p2_2 <= '0; col_p2_3 <= '0;
            col_p3_0 <= '0; col_p3_1 <= '0; col_p3_2 <= '0; col_p3_3 <= '0;
            hold_p0_0 <= '0; hold_p0_1 <= '0; hold_p0_2 <= '0; hold_p0_3 <= '0;
            hold_p1_0 <= '0; hold_p1_1 <= '0; hold_p1_2 <= '0; hold_p1_3 <= '0;
            hold_p2_0 <= '0; hold_p2_1 <= '0; hold_p2_2 <= '0; hold_p2_3 <= '0;
            hold_p3_0 <= '0; hold_p3_1 <= '0; hold_p3_2 <= '0; hold_p3_3 <= '0;
            hold_cycle_odd    <= 1'b0;
        end else begin

            if (in_state != IDLE) begin
                // --- Collecting: store din into current phase buffer ---
                case (in_phase)
                    3'd1: begin col_p1_0<=din0; col_p1_1<=din1; col_p1_2<=din2; col_p1_3<=din3; end
                    3'd2: begin col_p2_0<=din0; col_p2_1<=din1; col_p2_2<=din2; col_p2_3<=din3; end
                    3'd3: begin col_p3_0<=din0; col_p3_1<=din1; col_p3_2<=din2; col_p3_3<=din3; end
                    default: ;
                endcase

                if (in_phase == phase_max) begin
                    in_state <= IDLE;
                    in_phase <= 3'd0;
                    // Snapshot to hold buffer + flip toggle
                    col_done_toggle <= ~col_done_toggle;
                    hold_cycle_odd  <= in_cycle_odd_latch;
                    // Copy already-collected phases from col_p*
                    hold_p0_0<=col_p0_0; hold_p0_1<=col_p0_1; hold_p0_2<=col_p0_2; hold_p0_3<=col_p0_3;
                    // For phases 1..N-1 that were captured earlier, copy from col_p*
                    // For the CURRENT (last) phase, use din directly (NBA: col_p[last] still has old value)
                    case (in_state)
                        COLLECT_8L: begin
                            // phase_max=1, current phase=1: col_p1 written this cycle but NBA = old
                            hold_p1_0<=din0; hold_p1_1<=din1; hold_p1_2<=din2; hold_p1_3<=din3;
                        end
                        COLLECT_12L: begin
                            hold_p1_0<=col_p1_0; hold_p1_1<=col_p1_1; hold_p1_2<=col_p1_2; hold_p1_3<=col_p1_3;
                            // phase_max=2, current phase=2: use din
                            hold_p2_0<=din0; hold_p2_1<=din1; hold_p2_2<=din2; hold_p2_3<=din3;
                        end
                        COLLECT_16L: begin
                            hold_p1_0<=col_p1_0; hold_p1_1<=col_p1_1; hold_p1_2<=col_p1_2; hold_p1_3<=col_p1_3;
                            hold_p2_0<=col_p2_0; hold_p2_1<=col_p2_1; hold_p2_2<=col_p2_2; hold_p2_3<=col_p2_3;
                            // phase_max=3, current phase=3: use din
                            hold_p3_0<=din0; hold_p3_1<=din1; hold_p3_2<=din2; hold_p3_3<=din3;
                        end
                        default: ;
                    endcase
                end else begin
                    in_phase <= in_phase + 3'd1;
                end

            end else if (valid_in) begin
                // --- Start new collection window ---
                // Capture phase 0 immediately
                col_p0_0 <= din0; col_p0_1 <= din1;
                col_p0_2 <= din2; col_p0_3 <= din3;

                // 12L odd/even tracking: reset on rising edge of valid_in
                if (valid_in & ~valid_in_d1) begin
                    in_cycle_odd_latch <= 1'b0;
                    in_cycle_odd_cnt   <= 1'b1;
                end else begin
                    in_cycle_odd_latch <= in_cycle_odd_cnt;
                    in_cycle_odd_cnt   <= ~in_cycle_odd_cnt;
                end

                case (lane_mode)
                    MODE_4L: begin
                        in_state <= IDLE;
                        in_phase <= 3'd0;
                        // 4L: single phase, snapshot immediately
                        col_done_toggle <= ~col_done_toggle;
                        hold_p0_0<=din0; hold_p0_1<=din1; hold_p0_2<=din2; hold_p0_3<=din3;
                        // For 4L, odd/even doesn't matter but still set hold_cycle_odd
                        if (valid_in & ~valid_in_d1)
                            hold_cycle_odd <= 1'b0;
                        else
                            hold_cycle_odd <= in_cycle_odd_cnt;
                    end
                    MODE_8L: begin
                        in_state <= COLLECT_8L;
                        in_phase <= 3'd1;
                    end
                    MODE_12L: begin
                        in_state <= COLLECT_12L;
                        in_phase <= 3'd1;
                    end
                    MODE_16L: begin
                        in_state <= COLLECT_16L;
                        in_phase <= 3'd1;
                    end
                    default: begin
                        in_state <= IDLE;
                        in_phase <= 3'd0;
                    end
                endcase
            end
        end
    end

    // =========================================================================
    // clk_out domain: Toggle detection + De-rotation MUX + Output Register
    //
    // col_done_toggle (clk_in domain) transitions at a fast posedge.
    // clk_out posedge falls between two fast posedges (same PLL, no
    // metastability), so it reliably samples the stable toggle value.
    // When toggle change is detected, latch hold_p* through de-rotation MUX.
    // =========================================================================
    logic        out_valid;
    logic        col_done_toggle_d;  // delayed toggle for edge detection
    logic [DATA_W-1:0] out_a_top0, out_a_top1, out_a_top2, out_a_top3;
    logic [DATA_W-1:0] out_a_bot0, out_a_bot1, out_a_bot2, out_a_bot3;
    logic [DATA_W-1:0] out_b_top0, out_b_top1, out_b_top2, out_b_top3;
    logic [DATA_W-1:0] out_b_bot0, out_b_bot1, out_b_bot2, out_b_bot3;

    wire toggle_changed = (col_done_toggle != col_done_toggle_d);

    always_ff @(posedge clk_out or negedge rst_n) begin
        if (!rst_n) begin
            out_valid         <= 1'b0;
            col_done_toggle_d <= 1'b0;
            out_a_top0 <= '0; out_a_top1 <= '0; out_a_top2 <= '0; out_a_top3 <= '0;
            out_a_bot0 <= '0; out_a_bot1 <= '0; out_a_bot2 <= '0; out_a_bot3 <= '0;
            out_b_top0 <= '0; out_b_top1 <= '0; out_b_top2 <= '0; out_b_top3 <= '0;
            out_b_bot0 <= '0; out_b_bot1 <= '0; out_b_bot2 <= '0; out_b_bot3 <= '0;
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
                            // Even: phase0=a_top, phase1=a_bot, phase2=b_top (direct)
                            out_a_top0<=hold_p0_0; out_a_top1<=hold_p0_1;
                            out_a_top2<=hold_p0_2; out_a_top3<=hold_p0_3;
                            out_a_bot0<=hold_p1_0; out_a_bot1<=hold_p1_1;
                            out_a_bot2<=hold_p1_2; out_a_bot3<=hold_p1_3;
                            out_b_top0<=hold_p2_0; out_b_top1<=hold_p2_1;
                            out_b_top2<=hold_p2_2; out_b_top3<=hold_p2_3;
                        end else begin
                            // Odd: phase0=b_top, phase1=a_top, phase2=a_bot (de-rotate!)
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
                    default: begin
                        out_valid <= 1'b0;
                    end
                endcase
            end else begin
                out_valid <= 1'b0;
            end
        end
    end

    // =========================================================================
    // Output assignments
    // =========================================================================
    assign valid_out = out_valid;
    assign a_top0 = out_a_top0; assign a_top1 = out_a_top1;
    assign a_top2 = out_a_top2; assign a_top3 = out_a_top3;
    assign a_bot0 = out_a_bot0; assign a_bot1 = out_a_bot1;
    assign a_bot2 = out_a_bot2; assign a_bot3 = out_a_bot3;
    assign b_top0 = out_b_top0; assign b_top1 = out_b_top1;
    assign b_top2 = out_b_top2; assign b_top3 = out_b_top3;
    assign b_bot0 = out_b_bot0; assign b_bot1 = out_b_bot1;
    assign b_bot2 = out_b_bot2; assign b_bot3 = out_b_bot3;

    // =========================================================================
    // Debug outputs
    // =========================================================================
    assign dbg_state    = in_state;
    assign dbg_fifo_cnt = {1'b0, in_phase};

endmodule
