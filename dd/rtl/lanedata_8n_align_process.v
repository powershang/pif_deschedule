`timescale 1ns/1ps

// =============================================================================
// lanedata_8n_align_process  (refactored, coding-style pass)
// =============================================================================
// Burst padding preprocessor with dual alignment mode. Function is unchanged
// vs the prior revision:
//
//   align_mode = 1 (8N-mode):
//     Pads burst length to a multiple of 8 beats. Replay pattern alternates
//     tail_buf[0] (Cn), tail_buf[1] (Cn+1). Odd rem -> error_flag = 1.
//
//   align_mode = 0 (4N-mode):
//     Phase1 pads burst to next multiple of 4 with Cn/Cn+1 replay.
//     Phase2 unconditionally appends 4 zero beats so total output is a
//     multiple of 8. Odd rem4 -> error_flag = 1.
//
//   virtual_lane_en halves the chunk size (1 beat == 2 samples).
//
// Coding style applied (see feedback_coding_style.md):
//   - Explicit FSM encoding {S_IDLE, S_INPUT, S_PAD, S_PHASE2}; all legacy
//     flag combos (pad_active_q + phase2_active_q + prev_valid_q) are now
//     captured by `align_state`.
//   - Two-process FSM: sequential always just does state <= next_state.
//   - One always per related signal group (tail_buf, beat_mod_q, pad_left_q,
//     phase2_left_q, replay_idx_q, error_flag, dout_vec, valid_out).
//   - No leading default inside shared always blocks; every branch lists
//     the value explicitly.
//   - Signals that own a dedicated always only enumerate the conditions
//     that actually update them (no forced else).
//   - Implicit if-else-chain guards from the legacy mega-always are lifted
//     into explicit wires (fresh_burst, burst_end, chunk_beat_0, ...) so
//     the distributed always blocks share the same gating.
//   - Async-low reset + block label on every always.
// =============================================================================

module lanedata_8n_align_process (
    clk, rst_n, valid_in, align_mode, virtual_lane_en,
    din0,  din1,  din2,  din3,
    din4,  din5,  din6,  din7,
    din8,  din9,  din10, din11,
    din12, din13, din14, din15,
    valid_out,
    dout0,  dout1,  dout2,  dout3,
    dout4,  dout5,  dout6,  dout7,
    dout8,  dout9,  dout10, dout11,
    dout12, dout13, dout14, dout15,
    error_flag
);

    parameter DATA_W = 8;

    input                 clk;
    input                 rst_n;
    input                 valid_in;
    input                 align_mode;
    input                 virtual_lane_en;
    input  [DATA_W-1:0]   din0, din1, din2, din3;
    input  [DATA_W-1:0]   din4, din5, din6, din7;
    input  [DATA_W-1:0]   din8, din9, din10, din11;
    input  [DATA_W-1:0]   din12, din13, din14, din15;
    output reg            valid_out;
    output [DATA_W-1:0]   dout0, dout1, dout2, dout3;
    output [DATA_W-1:0]   dout4, dout5, dout6, dout7;
    output [DATA_W-1:0]   dout8, dout9, dout10, dout11;
    output [DATA_W-1:0]   dout12, dout13, dout14, dout15;
    output reg            error_flag;

    // -------------------------------------------------------------------------
    // FSM encoding
    // -------------------------------------------------------------------------
    localparam [1:0] S_IDLE   = 2'd0;  // no valid, no padding, no phase2
    localparam [1:0] S_INPUT  = 2'd1;  // valid_in=1, passing-through input
    localparam [1:0] S_PAD    = 2'd2;  // emitting replay pad (8N replay or 4N phase1)
    localparam [1:0] S_PHASE2 = 2'd3;  // 4N phase2 zero fill

    // =========================================================================
    // Input fan-in (comb bus aggregation)
    // =========================================================================
    reg [DATA_W-1:0] din_vec [0:15];
    always @(*) begin : p_din_pack
        din_vec[0]  = din0;
        din_vec[1]  = din1;
        din_vec[2]  = din2;
        din_vec[3]  = din3;
        din_vec[4]  = din4;
        din_vec[5]  = din5;
        din_vec[6]  = din6;
        din_vec[7]  = din7;
        din_vec[8]  = din8;
        din_vec[9]  = din9;
        din_vec[10] = din10;
        din_vec[11] = din11;
        din_vec[12] = din12;
        din_vec[13] = din13;
        din_vec[14] = din14;
        din_vec[15] = din15;
    end

    wire vlane = virtual_lane_en;

    // =========================================================================
    // prev_valid_q : detect fresh burst / burst end
    // =========================================================================
    reg prev_valid_q;
    always @(posedge clk or negedge rst_n) begin : p_prev_valid
        if (!rst_n) prev_valid_q <= 1'b0;
        else        prev_valid_q <= valid_in;
    end

    wire fresh_burst = valid_in & ~prev_valid_q;
    wire burst_end   = prev_valid_q & ~valid_in;

    // =========================================================================
    // FSM: align_state (two-process)
    // =========================================================================
    reg [1:0] align_state;
    reg [1:0] align_state_d;

    // Forward declarations (counters used by FSM transition):
    reg [2:0] beat_mod_q;
    reg [2:0] pad_left_q;
    reg [2:0] phase2_left_q;

    // rem_now = beats already consumed in the current chunk (beat_mod_q wraps
    // at chunk boundary so this is a direct count).
    wire [2:0] rem_now = beat_mod_q;

    // How many pad beats the burst-end decision needs to emit.
    // pad_total covers 8N replay pads and 4N phase1 pads; the numbers
    // differ per mode/rem but the dispatcher is a single function.
    reg [2:0] pad_total_d;
    reg       rem_is_odd_d;     // flags error
    always @(*) begin : p_pad_total
        pad_total_d  = 3'd0;
        rem_is_odd_d = 1'b0;
        if (align_mode && vlane) begin
            // 8N VLANE: chunk = 4 beat
            case (rem_now)
                3'd0: pad_total_d = 3'd0;
                3'd1: begin pad_total_d = 3'd3; rem_is_odd_d = 1'b1; end
                3'd2: pad_total_d = 3'd2;
                3'd3: begin pad_total_d = 3'd1; rem_is_odd_d = 1'b1; end
                default: pad_total_d = 3'd0;
            endcase
        end else if (align_mode && !vlane) begin
            // 8N PHY: chunk = 8 beat
            case (rem_now)
                3'd0: pad_total_d = 3'd0;
                3'd1: begin pad_total_d = 3'd7; rem_is_odd_d = 1'b1; end
                3'd2: pad_total_d = 3'd6;
                3'd3: begin pad_total_d = 3'd5; rem_is_odd_d = 1'b1; end
                3'd4: pad_total_d = 3'd4;
                3'd5: begin pad_total_d = 3'd3; rem_is_odd_d = 1'b1; end
                3'd6: pad_total_d = 3'd2;
                3'd7: begin pad_total_d = 3'd1; rem_is_odd_d = 1'b1; end
                default: pad_total_d = 3'd0;
            endcase
        end else if (!align_mode && vlane) begin
            // 4N VLANE: chunk = 2 beat
            case (rem_now)
                3'd0: pad_total_d = 3'd0;
                3'd1: begin pad_total_d = 3'd1; rem_is_odd_d = 1'b1; end
                default: pad_total_d = 3'd0;
            endcase
        end else begin
            // 4N PHY: chunk = 4 beat
            case (rem_now)
                3'd0: pad_total_d = 3'd0;
                3'd1: begin pad_total_d = 3'd3; rem_is_odd_d = 1'b1; end
                3'd2: pad_total_d = 3'd2;
                3'd3: begin pad_total_d = 3'd1; rem_is_odd_d = 1'b1; end
                default: pad_total_d = 3'd0;
            endcase
        end
    end

    // Phase2 beat count for 4N mode (after phase1 pad, or directly if rem==0).
    wire [2:0] phase2_count_full = vlane ? 3'd2 : 3'd4;

    // Next-state decision logic.
    // Key transitions:
    //   Any state + valid_in=1                 -> S_INPUT
    //   S_INPUT + burst_end + needs pad        -> S_PAD (if pad_total > 0)
    //                                           OR S_PHASE2 (4N rem==0)
    //                                           OR S_IDLE (8N rem==0)
    //   S_PAD   + pad_left_q==1 + align_mode=1 -> S_IDLE    (8N pad done)
    //   S_PAD   + pad_left_q==1 + align_mode=0 -> S_PHASE2  (4N pad->phase2)
    //   S_PHASE2 + phase2_left_q==1            -> S_IDLE
    //   S_IDLE                                  -> S_IDLE
    always @(*) begin : p_align_state_d
        if (valid_in) begin
            align_state_d = S_INPUT;
        end else begin
            case (align_state)
                S_INPUT: begin
                    // burst_end implicit (valid_in==0, last state was INPUT)
                    // If pad_total <= 1, the first (and only) pad beat is
                    // emitted in THIS cycle, so next state skips S_PAD.
                    if (align_mode) begin
                        // 8N
                        if (pad_total_d == 3'd0)      align_state_d = S_IDLE;
                        else if (pad_total_d == 3'd1) align_state_d = S_IDLE;
                        else                          align_state_d = S_PAD;
                    end else begin
                        // 4N
                        if (pad_total_d == 3'd0)      align_state_d = S_PHASE2;
                        else if (pad_total_d == 3'd1) align_state_d = S_PHASE2;
                        else                          align_state_d = S_PAD;
                    end
                end
                S_PAD: begin
                    // pad_left_q was loaded to pad_total - 1. Exit when it
                    // reaches 0 (last pad beat emitted this cycle).
                    if (pad_left_q == 3'd1) begin
                        if (align_mode)               align_state_d = S_IDLE;
                        else                          align_state_d = S_PHASE2;
                    end else begin
                        align_state_d = S_PAD;
                    end
                end
                S_PHASE2: begin
                    if (phase2_left_q == 3'd1)        align_state_d = S_IDLE;
                    else                              align_state_d = S_PHASE2;
                end
                default: begin
                    align_state_d = S_IDLE;
                end
            endcase
        end
    end

    always @(posedge clk or negedge rst_n) begin : p_align_state
        if (!rst_n) align_state <= S_IDLE;
        else        align_state <= align_state_d;
    end

    // Convenience wires for other signals to depend on the FSM cleanly.
    wire entering_input  = (align_state_d == S_INPUT);
    wire entering_pad    = (align_state_d == S_PAD);
    wire entering_phase2 = (align_state_d == S_PHASE2);
    wire in_input        = (align_state   == S_INPUT);
    wire in_pad          = (align_state   == S_PAD);
    wire in_phase2       = (align_state   == S_PHASE2);
    wire burst_end_pulse = in_input & ~valid_in;  // the cycle where burst ends

    // First pad beat is emitted on the burst_end cycle itself (FSM transitions
    // S_INPUT -> S_PAD same cycle). After that the S_PAD state covers the rest.
    wire first_pad_beat  = burst_end_pulse & (pad_total_d != 3'd0);
    // First phase2 beat (when rem==0 in 4N, we go straight to phase2 with no pad).
    wire first_phase2_beat_no_pad = burst_end_pulse & ~align_mode & (pad_total_d == 3'd0);

    // =========================================================================
    // beat_mod_q : input beat position within chunk (mod chunk_size)
    //   fresh_burst: load 1 (we're consuming beat 0 right now)
    //   valid_in continuing: wrap-increment by mode-dependent chunk size
    //   pad_left==1 transitioning out of S_PAD with 8N, or phase2 end: 0
    // =========================================================================
    wire [2:0] beat_mod_wrap =
          (align_mode && !vlane) ? ((beat_mod_q == 3'd7) ? 3'd0 : beat_mod_q + 3'd1) :
          (align_mode &&  vlane) ? ((beat_mod_q == 3'd3) ? 3'd0 : beat_mod_q + 3'd1) :
          (!align_mode && !vlane) ? ((beat_mod_q == 3'd3) ? 3'd0 : beat_mod_q + 3'd1) :
                                    ((beat_mod_q == 3'd1) ? 3'd0 : beat_mod_q + 3'd1);

    wire pad_last_beat_8n = in_pad & (pad_left_q == 3'd1) & align_mode;
    wire pad_first_is_last_8n = first_pad_beat & (pad_total_d == 3'd1) & align_mode;
    wire phase2_last_beat = in_phase2 & (phase2_left_q == 3'd1);

    always @(posedge clk or negedge rst_n) begin : p_beat_mod
        if (!rst_n)                      beat_mod_q <= 3'd0;
        else if (fresh_burst)            beat_mod_q <= 3'd1;
        else if (valid_in)               beat_mod_q <= beat_mod_wrap;
        else if (pad_last_beat_8n)       beat_mod_q <= 3'd0;
        else if (pad_first_is_last_8n)   beat_mod_q <= 3'd0;
        else if (phase2_last_beat)       beat_mod_q <= 3'd0;
    end

    // =========================================================================
    // tail_buf[0] (Cn) and tail_buf[1] (Cn+1)
    // Written only when input arrives at chunk beat 0 / beat 1.
    //   PHY:
    //     8N: tb0 at beat_mod_q==0, tb1 at beat_mod_q==1
    //     4N: tb0 at beat_mod_q[1:0]==0, tb1 at beat_mod_q[1:0]==1
    //   VLANE: only tb0 (1 beat carries both Cn and Cn+1 samples)
    //     8N: tb0 at beat_mod_q[1:0]==0
    //     4N: tb0 at beat_mod_q[0]==0
    // Fresh burst: tb0 <= current din (it is the first beat of the chunk).
    // =========================================================================
    wire tb0_cond_phy   = align_mode ? (beat_mod_q == 3'd0)
                                     : (beat_mod_q[1:0] == 2'd0);
    wire tb1_cond_phy   = align_mode ? (beat_mod_q == 3'd1)
                                     : (beat_mod_q[1:0] == 2'd1);
    wire tb0_cond_vlane = align_mode ? (beat_mod_q[1:0] == 2'd0)
                                     : (beat_mod_q[0]   == 1'b0);

    wire tb0_write_continuing = valid_in & ~fresh_burst &
                                (vlane ? tb0_cond_vlane : tb0_cond_phy);
    wire tb1_write_continuing = valid_in & ~fresh_burst & ~vlane & tb1_cond_phy;

    reg [DATA_W-1:0] tail_buf [0:1][0:15];
    integer i_tb;
    always @(posedge clk or negedge rst_n) begin : p_tail_buf
        if (!rst_n) begin
            for (i_tb = 0; i_tb < 16; i_tb = i_tb + 1) begin
                tail_buf[0][i_tb] <= {DATA_W{1'b0}};
                tail_buf[1][i_tb] <= {DATA_W{1'b0}};
            end
        end else if (fresh_burst) begin
            for (i_tb = 0; i_tb < 16; i_tb = i_tb + 1) begin
                tail_buf[0][i_tb] <= din_vec[i_tb];
            end
        end else if (tb0_write_continuing) begin
            for (i_tb = 0; i_tb < 16; i_tb = i_tb + 1) begin
                tail_buf[0][i_tb] <= din_vec[i_tb];
            end
        end else if (tb1_write_continuing) begin
            for (i_tb = 0; i_tb < 16; i_tb = i_tb + 1) begin
                tail_buf[1][i_tb] <= din_vec[i_tb];
            end
        end
    end

    // =========================================================================
    // pad_left_q : countdown for S_PAD state
    //   Loaded on burst_end when entering S_PAD: pad_total_d - 1
    //   Decremented each S_PAD cycle
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin : p_pad_left
        if (!rst_n)                pad_left_q <= 3'd0;
        else if (first_pad_beat)   pad_left_q <= pad_total_d - 3'd1;
        else if (in_pad & (pad_left_q != 3'd0))
                                   pad_left_q <= pad_left_q - 3'd1;
    end

    // =========================================================================
    // phase2_left_q : countdown for S_PHASE2 state
    //   Loaded when entering S_PHASE2:
    //     From S_PAD (pad_left==1, 4N): phase2_count_full - 1 (since THIS cycle
    //       is still a pad beat, not a phase2 beat; decrement starts next cycle)
    //     Direct from burst_end rem==0 (4N): phase2_count_full - 1 (one phase2
    //       beat already emitted on the burst_end cycle)
    // =========================================================================
    wire pad_to_phase2 = in_pad & (pad_left_q == 3'd1) & ~align_mode;
    wire pad_first_is_last_4n = first_pad_beat & (pad_total_d == 3'd1) & ~align_mode;

    always @(posedge clk or negedge rst_n) begin : p_phase2_left
        if (!rst_n)                            phase2_left_q <= 3'd0;
        else if (pad_first_is_last_4n)         phase2_left_q <= phase2_count_full;
        else if (pad_to_phase2)                phase2_left_q <= phase2_count_full;
        else if (first_phase2_beat_no_pad)     phase2_left_q <= phase2_count_full - 3'd1;
        else if (in_phase2 & (phase2_left_q != 3'd0))
                                               phase2_left_q <= phase2_left_q - 3'd1;
    end

    // =========================================================================
    // replay_idx_q : toggles between tail_buf[0] and tail_buf[1] during S_PAD
    //   VLANE: always 0 (single beat carries both samples)
    //   PHY: burst_end loads 1 (first pad is tb0, second pad is tb1), then
    //        toggles each S_PAD cycle
    // =========================================================================
    reg replay_idx_q;
    always @(posedge clk or negedge rst_n) begin : p_replay_idx
        if (!rst_n)               replay_idx_q <= 1'b0;
        else if (first_pad_beat)  replay_idx_q <= vlane ? 1'b0 : 1'b1;
        else if (in_pad)          replay_idx_q <= vlane ? 1'b0 : ~replay_idx_q;
    end

    // =========================================================================
    // error_flag (single reg, self-sticky)
    //   fresh_burst: clear
    //   burst_end with rem_is_odd_d: set
    //   otherwise: hold
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin : p_error_flag
        if (!rst_n)                              error_flag <= 1'b0;
        else if (fresh_burst)                    error_flag <= 1'b0;
        else if (burst_end_pulse & rem_is_odd_d) error_flag <= 1'b1;
    end

    // =========================================================================
    // valid_out : high for every cycle that emits a real beat
    //   valid_in=1                       : input beat            (S_INPUT)
    //   first_pad_beat                   : first pad beat        (S_INPUT -> S_PAD)
    //   first_phase2_beat_no_pad         : direct phase2 start   (S_INPUT -> S_PHASE2)
    //   in_pad                           : pad continuation      (S_PAD)
    //   in_phase2                        : phase2 continuation   (S_PHASE2)
    //   else                             : 0
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin : p_valid_out
        if (!rst_n)                              valid_out <= 1'b0;
        else if (valid_in)                       valid_out <= 1'b1;
        else if (first_pad_beat)                 valid_out <= 1'b1;
        else if (first_phase2_beat_no_pad)       valid_out <= 1'b1;
        else if (in_pad)                         valid_out <= 1'b1;
        else if (in_phase2)                      valid_out <= 1'b1;
        else                                     valid_out <= 1'b0;
    end

    // =========================================================================
    // dout_vec : per-cycle payload select
    //   valid_in=1 (S_INPUT input beat): pass through din
    //   first_pad_beat (burst_end -> S_PAD same cycle): tail_buf[0]
    //   first_phase2_beat_no_pad: zeros
    //   in_pad continuing: tail_buf[replay_idx_q]
    //   in_phase2 continuing: zeros
    //   else: zeros
    // =========================================================================
    reg [DATA_W-1:0] dout_vec [0:15];
    integer i_do;

    always @(posedge clk or negedge rst_n) begin : p_dout
        if (!rst_n) begin
            for (i_do = 0; i_do < 16; i_do = i_do + 1)
                dout_vec[i_do] <= {DATA_W{1'b0}};
        end else if (valid_in) begin
            for (i_do = 0; i_do < 16; i_do = i_do + 1)
                dout_vec[i_do] <= din_vec[i_do];
        end else if (first_pad_beat) begin
            for (i_do = 0; i_do < 16; i_do = i_do + 1)
                dout_vec[i_do] <= tail_buf[0][i_do];
        end else if (first_phase2_beat_no_pad) begin
            for (i_do = 0; i_do < 16; i_do = i_do + 1)
                dout_vec[i_do] <= {DATA_W{1'b0}};
        end else if (in_pad) begin
            for (i_do = 0; i_do < 16; i_do = i_do + 1)
                dout_vec[i_do] <= tail_buf[replay_idx_q][i_do];
        end else if (in_phase2) begin
            for (i_do = 0; i_do < 16; i_do = i_do + 1)
                dout_vec[i_do] <= {DATA_W{1'b0}};
        end else begin
            for (i_do = 0; i_do < 16; i_do = i_do + 1)
                dout_vec[i_do] <= {DATA_W{1'b0}};
        end
    end

    // -------------------------------------------------------------------------
    // Module outputs
    // -------------------------------------------------------------------------
    assign dout0  = dout_vec[0];
    assign dout1  = dout_vec[1];
    assign dout2  = dout_vec[2];
    assign dout3  = dout_vec[3];
    assign dout4  = dout_vec[4];
    assign dout5  = dout_vec[5];
    assign dout6  = dout_vec[6];
    assign dout7  = dout_vec[7];
    assign dout8  = dout_vec[8];
    assign dout9  = dout_vec[9];
    assign dout10 = dout_vec[10];
    assign dout11 = dout_vec[11];
    assign dout12 = dout_vec[12];
    assign dout13 = dout_vec[13];
    assign dout14 = dout_vec[14];
    assign dout15 = dout_vec[15];

endmodule
