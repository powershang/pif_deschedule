`timescale 1ns/1ps

// =============================================================================
// lanedata_8n_align_process  (option-B pad-to-8 rewrite)
// =============================================================================
// Burst padding preprocessor. Output length is always a multiple of 8 samples:
//   - PHY  (1 beat = 1 sample)  -> output beats is a multiple of 8
//   - VLANE(1 beat = 2 samples) -> output beats is a multiple of 4
// Padding uses only Cn/Cn+1 replay from the last captured chunk; no zero-fill.
//
//   align_mode = 1 (8N-mode):
//     Chunk size = 8 beats (PHY) or 4 beats (VLANE). A burst is already at
//     or below one chunk-alignment unit; pad the remainder up to the chunk
//     boundary. Odd rem -> error_flag = 1.
//
//   align_mode = 0 (4N-mode):
//     Chunk size = 4 beats (PHY) or 2 beats (VLANE), i.e. half the 8N chunk.
//     The 8N-alignment target is TWO chunks, so padding depends on both the
//     chunk's internal position (beat_mod_q) AND the chunk-parity counter
//     (chunk_parity_q: 0 = an even number of chunks already complete,
//      1 = an odd number complete).
//     Odd rem -> error_flag = 1.
//
//   virtual_lane_en halves the chunk size (1 beat == 2 samples). VLANE only
//   captures tail_buf[0] (a single beat carries both Cn and Cn+1), so replay
//   repeats tail_buf[0] for every pad beat.
//
// Coding style applied (see feedback_coding_style.md):
//   - Explicit FSM encoding {S_IDLE, S_INPUT, S_PAD}.
//   - Two-process FSM: sequential always just does state <= next_state.
//   - One always per related signal group.
//   - No leading default inside shared always blocks; every branch lists
//     the value explicitly.
//   - Signals that own a dedicated always only enumerate the conditions
//     that actually update them (no forced else).
//   - Implicit if-else-chain guards from legacy mega-always are lifted into
//     explicit wires (fresh_burst, burst_end_pulse, first_pad_beat, ...).
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
    localparam [1:0] S_IDLE  = 2'd0;  // no valid, no padding
    localparam [1:0] S_INPUT = 2'd1;  // valid_in=1, passing input through
    localparam [1:0] S_PAD   = 2'd2;  // emitting replay pad

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

    // =========================================================================
    // FSM: align_state (two-process)
    // =========================================================================
    reg [1:0] align_state;
    reg [1:0] align_state_d;

    reg [2:0] beat_mod_q;
    reg       chunk_parity_q;
    reg [2:0] pad_left_q;

    // rem_now : beats already consumed in the current chunk (beat_mod_q wraps
    // at chunk boundary, so this is a direct count).
    wire [2:0] rem_now = beat_mod_q;

    // pad_total_d : total pad beats required to reach the 8-sample alignment.
    //   8N modes: pad only to fill the current chunk.
    //   4N modes: pad depends on (rem_now, chunk_parity_q) - see spec above.
    // rem_is_odd_d : flags the odd-rem error (for error_flag).
    reg [2:0] pad_total_d;
    reg       rem_is_odd_d;

    always @(*) begin : p_pad_total
        if (align_mode && !vlane) begin
            // 8N PHY: chunk = 8 beats, pad to chunk boundary (8 beats).
            case (rem_now)
                3'd0:    begin pad_total_d = 3'd0; rem_is_odd_d = 1'b0; end
                3'd1:    begin pad_total_d = 3'd7; rem_is_odd_d = 1'b1; end
                3'd2:    begin pad_total_d = 3'd6; rem_is_odd_d = 1'b0; end
                3'd3:    begin pad_total_d = 3'd5; rem_is_odd_d = 1'b1; end
                3'd4:    begin pad_total_d = 3'd4; rem_is_odd_d = 1'b0; end
                3'd5:    begin pad_total_d = 3'd3; rem_is_odd_d = 1'b1; end
                3'd6:    begin pad_total_d = 3'd2; rem_is_odd_d = 1'b0; end
                3'd7:    begin pad_total_d = 3'd1; rem_is_odd_d = 1'b1; end
                default: begin pad_total_d = 3'd0; rem_is_odd_d = 1'b0; end
            endcase
        end else if (align_mode && vlane) begin
            // 8N VLANE: chunk = 4 beats, pad to chunk boundary (4 beats).
            case (rem_now)
                3'd0:    begin pad_total_d = 3'd0; rem_is_odd_d = 1'b0; end
                3'd1:    begin pad_total_d = 3'd3; rem_is_odd_d = 1'b1; end
                3'd2:    begin pad_total_d = 3'd2; rem_is_odd_d = 1'b0; end
                3'd3:    begin pad_total_d = 3'd1; rem_is_odd_d = 1'b1; end
                default: begin pad_total_d = 3'd0; rem_is_odd_d = 1'b0; end
            endcase
        end else if (!align_mode && !vlane) begin
            // 4N PHY: chunk = 4 beats, pad to TWO-chunk boundary (8 beats).
            // parity=0 : even number of chunks complete -> already 8-aligned;
            //            rem=0 -> pad 0 ; rem=r -> pad (8-r)
            // parity=1 : odd number of chunks complete -> need 4-beat top-up;
            //            rem=0 -> pad 4 ; rem=r -> pad (4-r)
            if (chunk_parity_q == 1'b0) begin
                case (rem_now)
                    3'd0:    begin pad_total_d = 3'd0; rem_is_odd_d = 1'b0; end
                    3'd1:    begin pad_total_d = 3'd7; rem_is_odd_d = 1'b1; end
                    3'd2:    begin pad_total_d = 3'd6; rem_is_odd_d = 1'b0; end
                    3'd3:    begin pad_total_d = 3'd5; rem_is_odd_d = 1'b1; end
                    default: begin pad_total_d = 3'd0; rem_is_odd_d = 1'b0; end
                endcase
            end else begin
                case (rem_now)
                    3'd0:    begin pad_total_d = 3'd4; rem_is_odd_d = 1'b0; end
                    3'd1:    begin pad_total_d = 3'd3; rem_is_odd_d = 1'b1; end
                    3'd2:    begin pad_total_d = 3'd2; rem_is_odd_d = 1'b0; end
                    3'd3:    begin pad_total_d = 3'd1; rem_is_odd_d = 1'b1; end
                    default: begin pad_total_d = 3'd0; rem_is_odd_d = 1'b0; end
                endcase
            end
        end else begin
            // 4N VLANE: chunk = 2 beats, pad to TWO-chunk boundary (4 beats).
            // parity=0 : already 4-aligned. rem=0 -> pad 0 ; rem=1 -> pad 3 (err)
            // parity=1 : one chunk complete. rem=0 -> pad 2 ; rem=1 -> pad 1 (err)
            if (chunk_parity_q == 1'b0) begin
                case (rem_now)
                    3'd0:    begin pad_total_d = 3'd0; rem_is_odd_d = 1'b0; end
                    3'd1:    begin pad_total_d = 3'd3; rem_is_odd_d = 1'b1; end
                    default: begin pad_total_d = 3'd0; rem_is_odd_d = 1'b0; end
                endcase
            end else begin
                case (rem_now)
                    3'd0:    begin pad_total_d = 3'd2; rem_is_odd_d = 1'b0; end
                    3'd1:    begin pad_total_d = 3'd1; rem_is_odd_d = 1'b1; end
                    default: begin pad_total_d = 3'd0; rem_is_odd_d = 1'b0; end
                endcase
            end
        end
    end

    // -------------------------------------------------------------------------
    // Next-state logic
    //   Any state + valid_in=1                            -> S_INPUT
    //   S_INPUT + burst_end + pad_total==0                -> S_IDLE
    //   S_INPUT + burst_end + pad_total==1                -> S_IDLE (single pad
    //                                                        beat emitted this cycle)
    //   S_INPUT + burst_end + pad_total>=2                -> S_PAD
    //   S_PAD   + pad_left_q==1                           -> S_IDLE
    //   S_PAD   + pad_left_q >1                           -> S_PAD
    //   S_IDLE                                            -> S_IDLE
    // -------------------------------------------------------------------------
    always @(*) begin : p_align_state_d
        if (valid_in) begin
            align_state_d = S_INPUT;
        end else begin
            case (align_state)
                S_INPUT: begin
                    if (pad_total_d == 3'd0)      align_state_d = S_IDLE;
                    else if (pad_total_d == 3'd1) align_state_d = S_IDLE;
                    else                          align_state_d = S_PAD;
                end
                S_PAD: begin
                    if (pad_left_q == 3'd1)       align_state_d = S_IDLE;
                    else                          align_state_d = S_PAD;
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

    // Convenience wires
    wire in_input        = (align_state == S_INPUT);
    wire in_pad          = (align_state == S_PAD);
    wire burst_end_pulse = in_input & ~valid_in;
    wire first_pad_beat  = burst_end_pulse & (pad_total_d != 3'd0);

    // =========================================================================
    // beat_mod_q : input beat position within the current chunk (wraps)
    //   fresh_burst              : 1 (we are consuming beat 0 right now)
    //   valid_in continuing      : mode-dependent wrap-increment
    //   on the last pad beat     : 0 (chunk is resolved)
    //   otherwise                : hold
    // =========================================================================
    wire [2:0] beat_mod_wrap =
          (align_mode && !vlane)  ? ((beat_mod_q == 3'd7) ? 3'd0 : beat_mod_q + 3'd1) :
          (align_mode &&  vlane)  ? ((beat_mod_q == 3'd3) ? 3'd0 : beat_mod_q + 3'd1) :
          (!align_mode && !vlane) ? ((beat_mod_q == 3'd3) ? 3'd0 : beat_mod_q + 3'd1) :
                                    ((beat_mod_q == 3'd1) ? 3'd0 : beat_mod_q + 3'd1);

    // Did the "current" input beat wrap the chunk?
    wire input_chunk_wrap =
          valid_in & ~fresh_burst &
          ( (align_mode && !vlane  && beat_mod_q == 3'd7) |
            (align_mode &&  vlane  && beat_mod_q == 3'd3) |
            (!align_mode && !vlane && beat_mod_q == 3'd3) |
            (!align_mode &&  vlane && beat_mod_q == 3'd1) );

    wire pad_last_beat = in_pad & (pad_left_q == 3'd1);
    wire pad_first_is_last = first_pad_beat & (pad_total_d == 3'd1);

    always @(posedge clk or negedge rst_n) begin : p_beat_mod
        if (!rst_n)                    beat_mod_q <= 3'd0;
        else if (fresh_burst)          beat_mod_q <= 3'd1;
        else if (valid_in)             beat_mod_q <= beat_mod_wrap;
        else if (pad_last_beat)        beat_mod_q <= 3'd0;
        else if (pad_first_is_last)    beat_mod_q <= 3'd0;
    end

    // =========================================================================
    // chunk_parity_q : counts chunks mod 2 (only meaningful in 4N modes).
    //   fresh_burst : 0
    //   input_chunk_wrap : toggle (a chunk just completed via input)
    //   first_pad_beat + (pad_total filled the current chunk) : toggle
    //     - If the pad ends up completing both chunks (reaches 8-alignment),
    //       parity stays at whatever it should be for the next burst (0).
    //   For simplicity we only toggle on input_chunk_wrap; the parity is
    //   only read at burst_end_pulse, which is evaluated BEFORE any pad is
    //   emitted, so the input-driven parity is the correct value at that
    //   decision point.
    //   After burst completion we reset parity on the next fresh_burst.
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin : p_chunk_parity
        if (!rst_n)                 chunk_parity_q <= 1'b0;
        else if (fresh_burst)       chunk_parity_q <= 1'b0;
        else if (input_chunk_wrap)  chunk_parity_q <= ~chunk_parity_q;
    end

    // =========================================================================
    // tail_buf[0] (Cn) and tail_buf[1] (Cn+1)
    //
    // Per-mode write-enable wires. Each wire corresponds to a specific
    // (align_mode, vlane) combination and captures exactly which beat_mod_q
    // slot triggers a tail_buf update in that mode. The wires are mutually
    // exclusive at runtime (only one can be high at a time because only one
    // mode is active). Debug waveform can show 6 wires and see directly which
    // mode's chunk-boundary just fired, without cross-referencing
    // align_mode/vlane/beat_mod_q.
    //
    //   8N PHY   : chunk=8 beats; tb0 at beat_mod_q==0, tb1 at beat_mod_q==1
    //   8N VLANE : chunk=4 beats; tb0 only at beat_mod_q[1:0]==0
    //   4N PHY   : chunk=4 beats; tb0 at beat_mod_q[1:0]==0, tb1 at beat_mod_q[1:0]==1
    //   4N VLANE : chunk=2 beats; tb0 only at beat_mod_q[0]==0
    //   VLANE modes: only tb0 (one beat carries both Cn and Cn+1 samples)
    //   Fresh burst: tb0 <= current din (first beat of chunk), all modes.
    // =========================================================================
    wire we_8n_phy_tb0   = valid_in & ~fresh_burst &  align_mode & ~vlane & (beat_mod_q      == 3'd0);
    wire we_8n_phy_tb1   = valid_in & ~fresh_burst &  align_mode & ~vlane & (beat_mod_q      == 3'd1);
    wire we_8n_vlane_tb0 = valid_in & ~fresh_burst &  align_mode &  vlane & (beat_mod_q[1:0] == 2'd0);
    wire we_4n_phy_tb0   = valid_in & ~fresh_burst & ~align_mode & ~vlane & (beat_mod_q[1:0] == 2'd0);
    wire we_4n_phy_tb1   = valid_in & ~fresh_burst & ~align_mode & ~vlane & (beat_mod_q[1:0] == 2'd1);
    wire we_4n_vlane_tb0 = valid_in & ~fresh_burst & ~align_mode &  vlane & (beat_mod_q[0]   == 1'b0);

    // Combined write-enables (OR of the exclusive per-mode wires).
    wire tb0_write_continuing = we_8n_phy_tb0 | we_8n_vlane_tb0 |
                                we_4n_phy_tb0 | we_4n_vlane_tb0;
    wire tb1_write_continuing = we_8n_phy_tb1 | we_4n_phy_tb1;

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
    // pad_left_q : countdown during S_PAD
    //   Loaded on first_pad_beat : pad_total_d - 1 (this cycle emits the first
    //     pad beat, so remaining = total - 1).
    //   Decremented each S_PAD cycle.
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin : p_pad_left
        if (!rst_n)                pad_left_q <= 3'd0;
        else if (first_pad_beat)   pad_left_q <= pad_total_d - 3'd1;
        else if (in_pad & (pad_left_q != 3'd0))
                                   pad_left_q <= pad_left_q - 3'd1;
    end

    // =========================================================================
    // replay_idx_q : toggles between tail_buf[0] and tail_buf[1] during S_PAD
    //   VLANE: always 0 (single beat carries both samples).
    //   PHY:
    //     first_pad_beat loads 1 (first pad = tb0 this cycle, next pad = tb1).
    //     in_pad continuing : toggle.
    // =========================================================================
    reg replay_idx_q;
    always @(posedge clk or negedge rst_n) begin : p_replay_idx
        if (!rst_n)              replay_idx_q <= 1'b0;
        else if (first_pad_beat) replay_idx_q <= vlane ? 1'b0 : 1'b1;
        else if (in_pad)         replay_idx_q <= vlane ? 1'b0 : ~replay_idx_q;
    end

    // =========================================================================
    // error_flag (self-sticky output)
    //   fresh_burst                 : clear
    //   burst_end + rem_is_odd_d    : set
    //   else                        : hold
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin : p_error_flag
        if (!rst_n)                              error_flag <= 1'b0;
        else if (fresh_burst)                    error_flag <= 1'b0;
        else if (burst_end_pulse & rem_is_odd_d) error_flag <= 1'b1;
    end

    // =========================================================================
    // valid_out : asserted while we have a real beat to emit.
    //   valid_in=1 (pass-through)            : 1
    //   first_pad_beat (burst_end -> S_PAD)  : 1
    //   in_pad                               : 1
    //   otherwise                            : 0
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin : p_valid_out
        if (!rst_n)                              valid_out <= 1'b0;
        else if (valid_in)                       valid_out <= 1'b1;
        else if (first_pad_beat)                 valid_out <= 1'b1;
        else if (in_pad)                         valid_out <= 1'b1;
        else                                     valid_out <= 1'b0;
    end

    // =========================================================================
    // dout_vec : per-cycle payload
    //   valid_in=1            : pass-through din
    //   first_pad_beat        : tail_buf[0]   (PHY & VLANE same)
    //   in_pad                : tail_buf[replay_idx_q]
    //   else                  : 0
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
        end else if (in_pad) begin
            for (i_do = 0; i_do < 16; i_do = i_do + 1)
                dout_vec[i_do] <= tail_buf[replay_idx_q][i_do];
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
