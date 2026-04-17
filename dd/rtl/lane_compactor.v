`timescale 1ns/1ps

// =============================================================================
// Module: lane_compactor
// Description: Dual-clock 4:2 compactor.
//   - Input side runs on clk_in_fast (= descheduler clk_out).
//     Of every 4 consecutive fast cycles of valid_in, the compactor captures
//     the 1st sample into reg_a (wr_phase==0) and the 2nd sample into reg_b
//     (wr_phase==1). Samples on wr_phase==2/3 are intentionally dropped
//     (they are redundant half-filled beats).
//   - Output side runs on clk_out_slow (= clk_in_fast / 2, same PLL).
//     On clk_out_slow posedge rd_phase toggles (0 -> reg_a, 1 -> reg_b)
//     and drives the 8-lane full output.
//   - reg_a / reg_b are written on clk_in_fast and read on clk_out_slow.
//     Both clocks are generated from the same PLL with a fixed phase
//     relation (clk_out_slow is clk_in_fast divided by 2). No asynchronous
//     CDC synchronizers are used.
//
// Throughput (continuous valid_in burst):
//   24 clk_in_fast cycles of valid data -> 12 clk_out_slow cycles of
//   valid_out with continuous valid (R0,R1,R4,R5,R8,R9,...).
//
// Correctness notes (this revision fixes four earlier RTL bugs):
//   1. Pair-order bug: earlier revision toggled rd_phase on every slow edge
//      when valid_in was high, which (depending on the fast/slow phase
//      relationship) could issue reg_b before reg_a at the start of a burst,
//      producing {beat1, beat0, beat5, beat4, ...}.  The fix: drive rd_phase
//      from beat_rd_cnt[0], a counter that only advances when a real output
//      is issued.  The first issued output of a burst is always reg_a.
//   2. Stale-zero bug: earlier revision set valid_out_r <= valid_in directly,
//      which could assert valid_out one slow edge before reg_a had actually
//      been written by the fast domain, emitting one reset-zero beat.  The
//      fix: valid_out is derived from (beat_wr_cnt != beat_rd_cnt), so it can
//      only go high once the fast domain has actually committed a beat into
//      reg_a / reg_b.
//   3. Tail-drop bug: earlier revision dropped valid_out the cycle valid_in
//      fell, even though the last pair was still sitting in reg_a / reg_b
//      unconsumed.  The fix: valid_out stays high until beat_rd_cnt catches
//      up to beat_wr_cnt, flushing the trailing pair.
//   4. Phantom-tail bug: earlier revision cleared beat_wr_cnt to zero the
//      cycle the fast domain went idle (valid_in=0 && !cap_a && !cap_b),
//      even when beat_rd_cnt was still mid-drain (e.g. wr=12, rd=10).  The
//      clear made pending = (0 != 10) spuriously true, and the slow domain
//      issued phantom beats for ~246 cycles (until rd wrapped around back
//      to 0).  The fix: both counters are free-running (reset only on
//      rst_n).  They converge naturally when rd catches up to wr and sit
//      at the same wrapped value through the idle gap; the next burst just
//      keeps incrementing from there.  Requires burst length < 2**(CNT_W-1)
//      beats so 2's-complement wrap never makes rd appear ahead of wr.
// =============================================================================

module lane_compactor (
    clk_in_fast, clk_out_slow, rst_n, valid_in,
    a_top0_in, a_top1_in, a_top2_in, a_top3_in,
    a_bot0_in, a_bot1_in, a_bot2_in, a_bot3_in,
    b_top0_in, b_top1_in, b_top2_in, b_top3_in,
    b_bot0_in, b_bot1_in, b_bot2_in, b_bot3_in,
    lane_len_0,  lane_len_1,  lane_len_2,  lane_len_3,
    lane_len_4,  lane_len_5,  lane_len_6,  lane_len_7,
    lane_len_8,  lane_len_9,  lane_len_10, lane_len_11,
    lane_len_12, lane_len_13, lane_len_14, lane_len_15,
    valid_out,
    a_top0, a_top1, a_top2, a_top3,
    a_bot0, a_bot1, a_bot2, a_bot3,
    b_top0, b_top1, b_top2, b_top3,
    b_bot0, b_bot1, b_bot2, b_bot3,
    burst_len_error
);
    parameter DATA_W  = 32;
    parameter CNT_W   = 8;   // beat counter width (covers >> largest expected burst)
    parameter LEN_W   = 13;  // per-lane length-limiter counter / register width

    // -------------------------------------------------------------------------
    // Ports
    // -------------------------------------------------------------------------
    input              clk_in_fast;    // write clock (= descheduler clk_out)
    input              clk_out_slow;   // read clock  (= clk_in_fast / 2)
    input              rst_n;
    input              valid_in;
    input  [DATA_W-1:0] a_top0_in, a_top1_in, a_top2_in, a_top3_in;
    input  [DATA_W-1:0] a_bot0_in, a_bot1_in, a_bot2_in, a_bot3_in;
    input  [DATA_W-1:0] b_top0_in, b_top1_in, b_top2_in, b_top3_in;
    input  [DATA_W-1:0] b_bot0_in, b_bot1_in, b_bot2_in, b_bot3_in;

    // Per-lane length limiter inputs (13-bit each).  Lane <-> bit mapping:
    //   bit 0 a_top0  bit 1 a_top1  bit 2 a_top2  bit 3 a_top3
    //   bit 4 a_bot0  bit 5 a_bot1  bit 6 a_bot2  bit 7 a_bot3
    //   bit 8 b_top0  bit 9 b_top1  bit10 b_top2  bit11 b_top3
    //   bit12 b_bot0  bit13 b_bot1  bit14 b_bot2  bit15 b_bot3
    input [LEN_W-1:0] lane_len_0,  lane_len_1,  lane_len_2,  lane_len_3;
    input [LEN_W-1:0] lane_len_4,  lane_len_5,  lane_len_6,  lane_len_7;
    input [LEN_W-1:0] lane_len_8,  lane_len_9,  lane_len_10, lane_len_11;
    input [LEN_W-1:0] lane_len_12, lane_len_13, lane_len_14, lane_len_15;

    output [15:0]      valid_out;
    output [DATA_W-1:0] a_top0, a_top1, a_top2, a_top3;
    output [DATA_W-1:0] a_bot0, a_bot1, a_bot2, a_bot3;
    output [DATA_W-1:0] b_top0, b_top1, b_top2, b_top3;
    output [DATA_W-1:0] b_bot0, b_bot1, b_bot2, b_bot3;
    // Sticky error: at valid_in falling edge, burst length was not a multiple
    // of 4 fast cycles. Sets when wr_phase != 0 at the cycle valid_in goes
    // low. Cleared on rst_n or on the next fresh_burst.
    output reg         burst_len_error;

    // -------------------------------------------------------------------------
    // clk_in_fast domain: wr_phase[1:0] counter + reg_a / reg_b capture
    // -------------------------------------------------------------------------
    reg [1:0] wr_phase;
    reg       valid_in_d1;   // for fresh-burst rising-edge detection

    // reg_a : captured on wr_phase == 0 (first beat of each group of 4)
    reg [DATA_W-1:0] reg_a_a_top0, reg_a_a_top1, reg_a_a_top2, reg_a_a_top3;
    reg [DATA_W-1:0] reg_a_a_bot0, reg_a_a_bot1, reg_a_a_bot2, reg_a_a_bot3;
    reg [DATA_W-1:0] reg_a_b_top0, reg_a_b_top1, reg_a_b_top2, reg_a_b_top3;
    reg [DATA_W-1:0] reg_a_b_bot0, reg_a_b_bot1, reg_a_b_bot2, reg_a_b_bot3;

    // reg_b : captured on wr_phase == 1 (second beat of each group of 4)
    reg [DATA_W-1:0] reg_b_a_top0, reg_b_a_top1, reg_b_a_top2, reg_b_a_top3;
    reg [DATA_W-1:0] reg_b_a_bot0, reg_b_a_bot1, reg_b_a_bot2, reg_b_a_bot3;
    reg [DATA_W-1:0] reg_b_b_top0, reg_b_b_top1, reg_b_b_top2, reg_b_b_top3;
    reg [DATA_W-1:0] reg_b_b_bot0, reg_b_b_bot1, reg_b_b_bot2, reg_b_b_bot3;

    wire fresh_burst = valid_in & ~valid_in_d1;

    // wr_phase counter (fresh burst forces phase = 0 so the first beat of a
    // burst is captured into reg_a)
    always @(posedge clk_in_fast or negedge rst_n) begin
        if (!rst_n) begin
            wr_phase    <= 2'd0;
            valid_in_d1 <= 1'b0;
        end else begin
            valid_in_d1 <= valid_in;
            if (fresh_burst) begin
                wr_phase <= 2'd1;           // consumed phase 0 this cycle
            end else if (valid_in) begin
                wr_phase <= wr_phase + 2'd1;
            end else begin
                wr_phase <= 2'd0;           // idle : pre-load phase 0
            end
        end
    end

    // reg_a capture (wr_phase == 0  OR fresh_burst)
    wire cap_a = valid_in & (fresh_burst | (wr_phase == 2'd0));
    // reg_b capture (wr_phase == 1  AND NOT fresh_burst).  Fresh-burst
    // cycle goes to reg_a, never reg_b.
    wire cap_b = valid_in & ~fresh_burst & (wr_phase == 2'd1);

    // -------------------------------------------------------------------------
    // burst_len_error : sticky flag, asserts at the clk_in_fast cycle that
    // valid_in falls (1 -> 0) if the burst was not a multiple of 4 fast
    // cycles. The compactor consumes input in groups of 4 (cap_a on phase 0,
    // cap_b on phase 1, drop phase 2/3); a non-multiple-of-4 burst leaves
    // wr_phase != 0 at end-of-burst, which means either the trailing reg_a
    // has no matching reg_b, or trailing input samples were silently dropped
    // -- both result in downstream rd_phase mis-pairing. Cleared by rst_n or
    // by the next fresh_burst.
    wire valid_in_fall = ~valid_in & valid_in_d1;
    wire burst_len_bad = valid_in_fall & (wr_phase != 2'd0);

    always @(posedge clk_in_fast or negedge rst_n) begin
        if (!rst_n) begin
            burst_len_error <= 1'b0;
        end else if (fresh_burst) begin
            burst_len_error <= 1'b0;
        end else if (burst_len_bad) begin
            burst_len_error <= 1'b1;
        end
    end

    always @(posedge clk_in_fast or negedge rst_n) begin
        if (!rst_n) begin
            reg_a_a_top0 <= {DATA_W{1'b0}}; reg_a_a_top1 <= {DATA_W{1'b0}};
            reg_a_a_top2 <= {DATA_W{1'b0}}; reg_a_a_top3 <= {DATA_W{1'b0}};
            reg_a_a_bot0 <= {DATA_W{1'b0}}; reg_a_a_bot1 <= {DATA_W{1'b0}};
            reg_a_a_bot2 <= {DATA_W{1'b0}}; reg_a_a_bot3 <= {DATA_W{1'b0}};
            reg_a_b_top0 <= {DATA_W{1'b0}}; reg_a_b_top1 <= {DATA_W{1'b0}};
            reg_a_b_top2 <= {DATA_W{1'b0}}; reg_a_b_top3 <= {DATA_W{1'b0}};
            reg_a_b_bot0 <= {DATA_W{1'b0}}; reg_a_b_bot1 <= {DATA_W{1'b0}};
            reg_a_b_bot2 <= {DATA_W{1'b0}}; reg_a_b_bot3 <= {DATA_W{1'b0}};
        end else if (cap_a) begin
            reg_a_a_top0 <= a_top0_in; reg_a_a_top1 <= a_top1_in;
            reg_a_a_top2 <= a_top2_in; reg_a_a_top3 <= a_top3_in;
            reg_a_a_bot0 <= a_bot0_in; reg_a_a_bot1 <= a_bot1_in;
            reg_a_a_bot2 <= a_bot2_in; reg_a_a_bot3 <= a_bot3_in;
            reg_a_b_top0 <= b_top0_in; reg_a_b_top1 <= b_top1_in;
            reg_a_b_top2 <= b_top2_in; reg_a_b_top3 <= b_top3_in;
            reg_a_b_bot0 <= b_bot0_in; reg_a_b_bot1 <= b_bot1_in;
            reg_a_b_bot2 <= b_bot2_in; reg_a_b_bot3 <= b_bot3_in;
        end
    end

    always @(posedge clk_in_fast or negedge rst_n) begin
        if (!rst_n) begin
            reg_b_a_top0 <= {DATA_W{1'b0}}; reg_b_a_top1 <= {DATA_W{1'b0}};
            reg_b_a_top2 <= {DATA_W{1'b0}}; reg_b_a_top3 <= {DATA_W{1'b0}};
            reg_b_a_bot0 <= {DATA_W{1'b0}}; reg_b_a_bot1 <= {DATA_W{1'b0}};
            reg_b_a_bot2 <= {DATA_W{1'b0}}; reg_b_a_bot3 <= {DATA_W{1'b0}};
            reg_b_b_top0 <= {DATA_W{1'b0}}; reg_b_b_top1 <= {DATA_W{1'b0}};
            reg_b_b_top2 <= {DATA_W{1'b0}}; reg_b_b_top3 <= {DATA_W{1'b0}};
            reg_b_b_bot0 <= {DATA_W{1'b0}}; reg_b_b_bot1 <= {DATA_W{1'b0}};
            reg_b_b_bot2 <= {DATA_W{1'b0}}; reg_b_b_bot3 <= {DATA_W{1'b0}};
        end else if (cap_b) begin
            reg_b_a_top0 <= a_top0_in; reg_b_a_top1 <= a_top1_in;
            reg_b_a_top2 <= a_top2_in; reg_b_a_top3 <= a_top3_in;
            reg_b_a_bot0 <= a_bot0_in; reg_b_a_bot1 <= a_bot1_in;
            reg_b_a_bot2 <= a_bot2_in; reg_b_a_bot3 <= a_bot3_in;
            reg_b_b_top0 <= b_top0_in; reg_b_b_top1 <= b_top1_in;
            reg_b_b_top2 <= b_top2_in; reg_b_b_top3 <= b_top3_in;
            reg_b_b_bot0 <= b_bot0_in; reg_b_b_bot1 <= b_bot1_in;
            reg_b_b_bot2 <= b_bot2_in; reg_b_b_bot3 <= b_bot3_in;
        end
    end

    // -------------------------------------------------------------------------
    // Beat counters (same-PLL, no async synchronizers).
    //
    //   beat_wr_cnt : counted in clk_in_fast domain.  Increments whenever a
    //                 beat is actually committed into reg_a or reg_b (cap_a
    //                 or cap_b).  Resets to zero ONLY on rst_n (never on
    //                 idle).  Free-running wrap at 2**CNT_W.
    //   beat_rd_cnt : counted in clk_out_slow domain.  Increments whenever an
    //                 output beat is actually issued (valid_out_next == 1).
    //                 Resets to zero ONLY on rst_n.  Free-running wrap at
    //                 2**CNT_W.
    //
    // Why free-running (no idle-clear):
    //   A previous revision cleared beat_wr_cnt the cycle valid_in fell, even
    //   when beat_rd_cnt had not yet drained.  That made pending =
    //   (beat_wr_cnt != beat_rd_cnt) spuriously true: beat_rd_cnt was still
    //   e.g. 10, but beat_wr_cnt had just dropped from 12 to 0.  The slow
    //   domain then issued phantom beats, wrapping all the way around until
    //   beat_rd_cnt finally caught up to 0 again.  By letting both counters
    //   free-run, pending can only re-assert after a real new cap_a/cap_b,
    //   and both counters stay aligned across burst boundaries automatically.
    //
    // Back-to-back burst support:
    //   After a burst ends with both counters at value N, they simply sit at
    //   N (gap of any length).  The next burst resumes incrementing from N
    //   and the slow side picks up seamlessly where it left off.
    //
    //   REQUIREMENT for correct rd_phase alignment across bursts:
    //     Each burst must commit an EVEN number of captures (cap_a + cap_b
    //     count).  Under the nominal 4:2 compactor pattern this is true iff
    //     the burst's fast-cycle count is a multiple of 4 (each group of 4
    //     fast beats emits exactly one reg_a + one reg_b, +2 to beat_wr_cnt).
    //     The current scheduler/descheduler always produces bursts that are
    //     multiples of 4 fast cycles (the nominal case is 24), so N ends
    //     even, and the next fresh_burst's first cap_a lands on an even wr
    //     value -- matching rd_phase=0 on the slow side.
    //
    //     If a future workload produces a burst with cap count that is odd
    //     (e.g. a burst of 4*k+1, 4*k+2 with fresh_burst semantics, or a
    //     4*k+3 burst), rd_phase would flip polarity across the gap and the
    //     next burst's first pair would be issued as {reg_b, reg_a}.  At
    //     that point the fix is to either force beat_rd_cnt / beat_wr_cnt
    //     to align to an even value at fresh_burst, or gate rd_phase off a
    //     per-burst toggle rather than the shared counter LSB.  Not needed
    //     for today's traffic.
    //
    // Counter width:
    //   CNT_W = 8 -> range 256.  A single burst must stay below 2**(CNT_W-1)
    //   = 128 beats so that 2's-complement wrap never makes rd appear ahead
    //   of wr.  Current design uses <= 24 beats/burst.
    //
    // Cross-domain sample:
    //   clk_out_slow = clk_in_fast / 2 from the same PLL.  Every slow rising
    //   edge aligns with a fast rising edge, so beat_wr_cnt sampled in the
    //   slow always_ff sees a stable post-flop value from the prior fast
    //   edge.  No synchronizers.
    // -------------------------------------------------------------------------
    reg [CNT_W-1:0] beat_wr_cnt;
    reg [CNT_W-1:0] beat_rd_cnt;

    always @(posedge clk_in_fast or negedge rst_n) begin
        if (!rst_n) begin
            beat_wr_cnt <= {CNT_W{1'b0}};
        end else if (cap_a || cap_b) begin
            beat_wr_cnt <= beat_wr_cnt + {{(CNT_W-1){1'b0}}, 1'b1};
        end
        // else: hold value (free-running across idle gaps)
    end

    // -------------------------------------------------------------------------
    // clk_out_slow domain: rd_phase + output MUX driven by beat_rd_cnt.
    //
    //   rd_phase = beat_rd_cnt[0]  (0 -> drive reg_a, 1 -> drive reg_b).
    //   valid_out_next = (beat_wr_cnt != beat_rd_cnt) : there is at least one
    //                    captured beat still unread.  This is asserted the
    //                    slow cycle AFTER reg_a has been written, so the
    //                    output flop sees real data, not the reset-zero.
    // -------------------------------------------------------------------------
    wire            pending        = (beat_wr_cnt != beat_rd_cnt);
    wire            valid_out_next = pending;
    wire            rd_phase_next  = beat_rd_cnt[0];

    reg             valid_out_r;
    reg [DATA_W-1:0] out_a_top0, out_a_top1, out_a_top2, out_a_top3;
    reg [DATA_W-1:0] out_a_bot0, out_a_bot1, out_a_bot2, out_a_bot3;
    reg [DATA_W-1:0] out_b_top0, out_b_top1, out_b_top2, out_b_top3;
    reg [DATA_W-1:0] out_b_bot0, out_b_bot1, out_b_bot2, out_b_bot3;

    always @(posedge clk_out_slow or negedge rst_n) begin
        if (!rst_n) begin
            beat_rd_cnt <= {CNT_W{1'b0}};
            valid_out_r <= 1'b0;
        end else begin
            valid_out_r <= valid_out_next;
            if (valid_out_next) begin
                // Issued one output beat this slow edge.
                beat_rd_cnt <= beat_rd_cnt + {{(CNT_W-1){1'b0}}, 1'b1};
            end
            // else: hold value (free-running, matches beat_wr_cnt policy).
            // When rd catches up to wr, pending -> 0 and both counters sit
            // at the same wrapped value until the next burst.
        end
    end

    // Output data MUX : only updates on cycles that will issue valid_out.
    // This keeps the bus held at the last valid beat during idle (rather
    // than reverting to reset-zero), and guarantees valid_out_r's high
    // cycles are paired with real data.
    always @(posedge clk_out_slow or negedge rst_n) begin
        if (!rst_n) begin
            out_a_top0 <= {DATA_W{1'b0}}; out_a_top1 <= {DATA_W{1'b0}};
            out_a_top2 <= {DATA_W{1'b0}}; out_a_top3 <= {DATA_W{1'b0}};
            out_a_bot0 <= {DATA_W{1'b0}}; out_a_bot1 <= {DATA_W{1'b0}};
            out_a_bot2 <= {DATA_W{1'b0}}; out_a_bot3 <= {DATA_W{1'b0}};
            out_b_top0 <= {DATA_W{1'b0}}; out_b_top1 <= {DATA_W{1'b0}};
            out_b_top2 <= {DATA_W{1'b0}}; out_b_top3 <= {DATA_W{1'b0}};
            out_b_bot0 <= {DATA_W{1'b0}}; out_b_bot1 <= {DATA_W{1'b0}};
            out_b_bot2 <= {DATA_W{1'b0}}; out_b_bot3 <= {DATA_W{1'b0}};
        end else if (valid_out_next && (rd_phase_next == 1'b0)) begin
            out_a_top0 <= reg_a_a_top0; out_a_top1 <= reg_a_a_top1;
            out_a_top2 <= reg_a_a_top2; out_a_top3 <= reg_a_a_top3;
            out_a_bot0 <= reg_a_a_bot0; out_a_bot1 <= reg_a_a_bot1;
            out_a_bot2 <= reg_a_a_bot2; out_a_bot3 <= reg_a_a_bot3;
            out_b_top0 <= reg_a_b_top0; out_b_top1 <= reg_a_b_top1;
            out_b_top2 <= reg_a_b_top2; out_b_top3 <= reg_a_b_top3;
            out_b_bot0 <= reg_a_b_bot0; out_b_bot1 <= reg_a_b_bot1;
            out_b_bot2 <= reg_a_b_bot2; out_b_bot3 <= reg_a_b_bot3;
        end else if (valid_out_next && (rd_phase_next == 1'b1)) begin
            out_a_top0 <= reg_b_a_top0; out_a_top1 <= reg_b_a_top1;
            out_a_top2 <= reg_b_a_top2; out_a_top3 <= reg_b_a_top3;
            out_a_bot0 <= reg_b_a_bot0; out_a_bot1 <= reg_b_a_bot1;
            out_a_bot2 <= reg_b_a_bot2; out_a_bot3 <= reg_b_a_bot3;
            out_b_top0 <= reg_b_b_top0; out_b_top1 <= reg_b_b_top1;
            out_b_top2 <= reg_b_b_top2; out_b_top3 <= reg_b_b_top3;
            out_b_bot0 <= reg_b_b_bot0; out_b_bot1 <= reg_b_b_bot1;
            out_b_bot2 <= reg_b_b_bot2; out_b_bot3 <= reg_b_b_bot3;
        end else begin
            // Hold last output when no new beat is being issued.
            out_a_top0 <= out_a_top0; out_a_top1 <= out_a_top1;
            out_a_top2 <= out_a_top2; out_a_top3 <= out_a_top3;
            out_a_bot0 <= out_a_bot0; out_a_bot1 <= out_a_bot1;
            out_a_bot2 <= out_a_bot2; out_a_bot3 <= out_a_bot3;
            out_b_top0 <= out_b_top0; out_b_top1 <= out_b_top1;
            out_b_top2 <= out_b_top2; out_b_top3 <= out_b_top3;
            out_b_bot0 <= out_b_bot0; out_b_bot1 <= out_b_bot1;
            out_b_bot2 <= out_b_bot2; out_b_bot3 <= out_b_bot3;
        end
    end

    // -------------------------------------------------------------------------
    // Per-lane length limiter (clk_out_slow domain)
    //
    // Each lane has a free-running 13-bit beat counter.  The counter is
    // incremented on every slow cycle that the inner compactor asserts a
    // valid beat AND the lane has not yet hit its programmed length.
    //
    // Burst boundary:
    //   "Burst" here means a contiguous run of compactor-valid cycles
    //   (valid_out_inner == 1).  When valid_out_inner falls to 0 the burst
    //   has ended and every lane counter is cleared, so the next
    //   valid_out_inner=1 starts counting from zero again.  This matches the
    //   spec: "valid_in=0 (burst end): lane_cnt[i] <= 0".  Using the
    //   compactor's own slow-side valid (valid_out_inner) rather than the
    //   fast-side valid_in keeps everything in one clock domain (no CDC).
    //
    // Per-lane gate:
    //   valid_out[i] = valid_out_inner & (lane_cnt[i] < lane_len[i])
    //
    // Data bus:
    //   The data outputs (a_top0..3, a_bot0..3, b_top0..3, b_bot0..3) are
    //   bus-shared across all lanes and are driven by the existing output
    //   MUX.  When a lane is gated off we hold the data unchanged; the
    //   downstream consumer must use valid_out[i] to decide whether the
    //   data on the corresponding lane bit is meaningful.  No extra
    //   per-lane data hold is added: the compactor already holds the bus
    //   at the last valid beat across idle gaps.
    // -------------------------------------------------------------------------
    wire valid_out_inner = valid_out_r;

    reg [LEN_W-1:0] lane_cnt [0:15];
    wire [LEN_W-1:0] lane_len [0:15];

    assign lane_len[0]  = lane_len_0;
    assign lane_len[1]  = lane_len_1;
    assign lane_len[2]  = lane_len_2;
    assign lane_len[3]  = lane_len_3;
    assign lane_len[4]  = lane_len_4;
    assign lane_len[5]  = lane_len_5;
    assign lane_len[6]  = lane_len_6;
    assign lane_len[7]  = lane_len_7;
    assign lane_len[8]  = lane_len_8;
    assign lane_len[9]  = lane_len_9;
    assign lane_len[10] = lane_len_10;
    assign lane_len[11] = lane_len_11;
    assign lane_len[12] = lane_len_12;
    assign lane_len[13] = lane_len_13;
    assign lane_len[14] = lane_len_14;
    assign lane_len[15] = lane_len_15;

    wire [15:0] lane_active;
    genvar gi;
    generate
        for (gi = 0; gi < 16; gi = gi + 1) begin : g_lane_active
            assign lane_active[gi] = (lane_cnt[gi] < lane_len[gi]);
        end
    endgenerate

    integer li;
    always @(posedge clk_out_slow or negedge rst_n) begin
        if (!rst_n) begin
            for (li = 0; li < 16; li = li + 1) begin
                lane_cnt[li] <= {LEN_W{1'b0}};
            end
        end else if (!valid_out_inner) begin
            // Burst ended (or never started) -- clear all lane counters so
            // the next contiguous valid run starts fresh.
            for (li = 0; li < 16; li = li + 1) begin
                lane_cnt[li] <= {LEN_W{1'b0}};
            end
        end else begin
            // valid_out_inner == 1 : count one beat per lane that is still
            // under its limit.  Lanes that have hit the limit hold value.
            for (li = 0; li < 16; li = li + 1) begin
                if (lane_cnt[li] < lane_len[li]) begin
                    lane_cnt[li] <= lane_cnt[li] + {{(LEN_W-1){1'b0}}, 1'b1};
                end else begin
                    lane_cnt[li] <= lane_cnt[li];
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // Outputs
    // -------------------------------------------------------------------------
    assign valid_out = {16{valid_out_inner}} & lane_active;

    assign a_top0 = out_a_top0; assign a_top1 = out_a_top1;
    assign a_top2 = out_a_top2; assign a_top3 = out_a_top3;
    assign a_bot0 = out_a_bot0; assign a_bot1 = out_a_bot1;
    assign a_bot2 = out_a_bot2; assign a_bot3 = out_a_bot3;
    assign b_top0 = out_b_top0; assign b_top1 = out_b_top1;
    assign b_top2 = out_b_top2; assign b_top3 = out_b_top3;
    assign b_bot0 = out_b_bot0; assign b_bot1 = out_b_bot1;
    assign b_bot2 = out_b_bot2; assign b_bot3 = out_b_bot3;

endmodule
