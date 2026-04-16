`timescale 1ns/1ps

// =============================================================================
// Module: lanedata_8n_align_process
// Description:
//   Burst padding preprocessor with dual alignment mode.
//
//   align_mode = 1 (8N-mode):
//     Pads burst length to a multiple of 8 beats.
//     Replay pattern: tail_buf[0] (Cn), tail_buf[1] (Cn+1) alternating.
//     Odd rem => error_flag = 1.
//
//   align_mode = 0 (4N-mode):
//     Phase 1: Pads burst to next multiple of 4 using Cn/Cn+1 replay.
//     Phase 2: Unconditionally appends 4 zero beats.
//     Total output is always a multiple of 8.
//     Odd rem4 => error_flag = 1.
//
//   tail_buf semantics (new):
//     tail_buf[0] = Cn  (beat 0 of current chunk)
//     tail_buf[1] = Cn+1 (beat 1 of current chunk)
//     Written only at beat_mod_q == 0 and beat_mod_q == 1 within a chunk.
//
//   virtual_lane_en is retained for port compatibility but does not alter behavior.
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

    input              clk;
    input              rst_n;
    input              valid_in;
    input              align_mode;
    input              virtual_lane_en;
    input  [DATA_W-1:0] din0, din1, din2, din3;
    input  [DATA_W-1:0] din4, din5, din6, din7;
    input  [DATA_W-1:0] din8, din9, din10, din11;
    input  [DATA_W-1:0] din12, din13, din14, din15;
    output reg          valid_out;
    output [DATA_W-1:0] dout0, dout1, dout2, dout3;
    output [DATA_W-1:0] dout4, dout5, dout6, dout7;
    output [DATA_W-1:0] dout8, dout9, dout10, dout11;
    output [DATA_W-1:0] dout12, dout13, dout14, dout15;
    output reg          error_flag;

    // virtual_lane_en is now used: VLANE halves chunk size (1 beat = 2 samples).

    // ---------------------------------------------------------------------
    // Input / output vector buses
    // ---------------------------------------------------------------------
    reg [DATA_W-1:0] din_vec  [0:15];
    reg [DATA_W-1:0] dout_vec [0:15];

    // tail_buf[0] = Cn (chunk beat 0), tail_buf[1] = Cn+1 (chunk beat 1)
    reg [DATA_W-1:0] tail_buf [0:1][0:15];

    // Per-burst counters / state
    reg [2:0]        beat_mod_q;     // counts input beats mod 8
    reg              pad_active_q;   // padding replay is being emitted
    reg [2:0]        pad_left_q;     // remaining pad beats (including current emit)
    reg              replay_idx_q;   // 0 => emit tail_buf[0], 1 => emit tail_buf[1]
    reg              prev_valid_q;   // valid_in from previous cycle
    reg              error_flag_q;   // sticky error flag within a burst

    // 4N-mode phase2 state
    reg              phase2_active_q; // emitting zero-fill phase2
    reg [2:0]        phase2_left_q;   // remaining phase2 zero beats

    // Combinational scratch
    reg [2:0] rem_now;
    reg [2:0] pad_total;
    reg [1:0] rem4;
    reg [2:0] pad_phase1;

    // Chunk size in beats depends on mode:
    //   8N PHY:   8 beat    8N VLANE:  4 beat
    //   4N PHY:   4 beat    4N VLANE:  2 beat
    // VLANE halves chunk size because 1 beat = 2 samples.
    wire vlane = virtual_lane_en;

    integer lane_idx;

    // ---------------------------------------------------------------------
    // Input fan-in / output fan-out
    // ---------------------------------------------------------------------
    always @(*) begin
        din_vec[0]  = din0;  din_vec[1]  = din1;  din_vec[2]  = din2;  din_vec[3]  = din3;
        din_vec[4]  = din4;  din_vec[5]  = din5;  din_vec[6]  = din6;  din_vec[7]  = din7;
        din_vec[8]  = din8;  din_vec[9]  = din9;  din_vec[10] = din10; din_vec[11] = din11;
        din_vec[12] = din12; din_vec[13] = din13; din_vec[14] = din14; din_vec[15] = din15;
    end

    assign dout0  = dout_vec[0];  assign dout1  = dout_vec[1];
    assign dout2  = dout_vec[2];  assign dout3  = dout_vec[3];
    assign dout4  = dout_vec[4];  assign dout5  = dout_vec[5];
    assign dout6  = dout_vec[6];  assign dout7  = dout_vec[7];
    assign dout8  = dout_vec[8];  assign dout9  = dout_vec[9];
    assign dout10 = dout_vec[10]; assign dout11 = dout_vec[11];
    assign dout12 = dout_vec[12]; assign dout13 = dout_vec[13];
    assign dout14 = dout_vec[14]; assign dout15 = dout_vec[15];

    // ---------------------------------------------------------------------
    // Main sequential logic
    // ---------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            beat_mod_q     <= 3'd0;
            pad_active_q   <= 1'b0;
            pad_left_q     <= 3'd0;
            replay_idx_q   <= 1'b0;
            prev_valid_q   <= 1'b0;
            error_flag_q   <= 1'b0;
            valid_out      <= 1'b0;
            error_flag     <= 1'b0;
            phase2_active_q <= 1'b0;
            phase2_left_q  <= 3'd0;
            for (lane_idx = 0; lane_idx < 16; lane_idx = lane_idx + 1) begin
                dout_vec[lane_idx]    <= {DATA_W{1'b0}};
                tail_buf[0][lane_idx] <= {DATA_W{1'b0}};
                tail_buf[1][lane_idx] <= {DATA_W{1'b0}};
            end
        end else begin
            // Defaults for this cycle
            valid_out  <= 1'b0;
            error_flag <= error_flag_q;
            for (lane_idx = 0; lane_idx < 16; lane_idx = lane_idx + 1) begin
                dout_vec[lane_idx] <= {DATA_W{1'b0}};
            end

            if (valid_in) begin
                // ----------------- Input beat -----------------
                valid_out <= 1'b1;

                if (!prev_valid_q) begin
                    // Fresh burst: clear sticky state, seed tail_buf[0] with Cn
                    error_flag_q    <= 1'b0;
                    error_flag      <= 1'b0;
                    pad_active_q    <= 1'b0;
                    pad_left_q      <= 3'd0;
                    phase2_active_q <= 1'b0;
                    phase2_left_q   <= 3'd0;
                    beat_mod_q      <= 3'd1;
                    for (lane_idx = 0; lane_idx < 16; lane_idx = lane_idx + 1) begin
                        dout_vec[lane_idx]    <= din_vec[lane_idx];
                        tail_buf[0][lane_idx] <= din_vec[lane_idx]; // Cn
                    end
                end else begin
                    // Continuing burst: pass through data
                    for (lane_idx = 0; lane_idx < 16; lane_idx = lane_idx + 1) begin
                        dout_vec[lane_idx] <= din_vec[lane_idx];
                    end

                    // tail_buf write: at each chunk's beat 0 (and beat 1 for PHY).
                    //
                    // Chunk sizes in beats:
                    //   8N PHY:  8 beat → write buf[0] at mod8==0, buf[1] at mod8==1
                    //   8N VLANE:4 beat → write buf[0] at mod4==0 only (1 beat has Cn+Cn+1)
                    //   4N PHY:  4 beat → write buf[0] at mod4==0, buf[1] at mod4==1
                    //   4N VLANE:2 beat → write buf[0] at mod2==0 only
                    //
                    // is_chunk_beat0: this beat is the first beat of a new chunk
                    // is_chunk_beat1: PHY only, second beat of chunk (for tail_buf[1])
                    if (vlane) begin
                        // VLANE: 1 beat = 2 samples (Cn in din0, Cn+1 in din1)
                        // Only write tail_buf[0] at chunk start; no tail_buf[1] needed
                        if (align_mode ? (beat_mod_q[1:0] == 2'd0) : (beat_mod_q[0] == 1'b0)) begin
                            for (lane_idx = 0; lane_idx < 16; lane_idx = lane_idx + 1) begin
                                tail_buf[0][lane_idx] <= din_vec[lane_idx];
                            end
                        end else begin
                            // No tail_buf update
                        end
                    end else begin
                        // PHY: 1 beat = 1 sample, need 2 beats for Cn + Cn+1
                        if (align_mode ? (beat_mod_q == 3'd0) : (beat_mod_q[1:0] == 2'd0)) begin
                            for (lane_idx = 0; lane_idx < 16; lane_idx = lane_idx + 1) begin
                                tail_buf[0][lane_idx] <= din_vec[lane_idx];
                            end
                        end else if (align_mode ? (beat_mod_q == 3'd1) : (beat_mod_q[1:0] == 2'd1)) begin
                            for (lane_idx = 0; lane_idx < 16; lane_idx = lane_idx + 1) begin
                                tail_buf[1][lane_idx] <= din_vec[lane_idx];
                            end
                        end else begin
                            // No tail_buf update for remaining beats in chunk
                        end
                    end

                    // beat_mod_q wraps at chunk boundary (in beats):
                    //   8N PHY:   8 beat (wrap at 7)
                    //   8N VLANE: 4 beat (wrap at 3)
                    //   4N PHY:   4 beat (wrap at 3)
                    //   4N VLANE: 2 beat (wrap at 1)
                    if (align_mode && !vlane) begin
                        // 8N PHY: mod 8
                        beat_mod_q <= (beat_mod_q == 3'd7) ? 3'd0 : (beat_mod_q + 3'd1);
                    end else if (align_mode && vlane) begin
                        // 8N VLANE: mod 4
                        beat_mod_q <= (beat_mod_q == 3'd3) ? 3'd0 : (beat_mod_q + 3'd1);
                    end else if (!align_mode && !vlane) begin
                        // 4N PHY: mod 4
                        beat_mod_q <= (beat_mod_q == 3'd3) ? 3'd0 : (beat_mod_q + 3'd1);
                    end else begin
                        // 4N VLANE: mod 2
                        beat_mod_q <= (beat_mod_q == 3'd1) ? 3'd0 : (beat_mod_q + 3'd1);
                    end
                    pad_active_q <= 1'b0;
                    pad_left_q   <= 3'd0;
                end

            end else if (pad_active_q) begin
                // ----------------- Continuing replay padding -----------------
                valid_out <= 1'b1;
                for (lane_idx = 0; lane_idx < 16; lane_idx = lane_idx + 1) begin
                    dout_vec[lane_idx] <= tail_buf[replay_idx_q][lane_idx];
                end

                // PHY: toggle between tail_buf[0] and tail_buf[1] (Cn, Cn+1 alternating)
                // VLANE: stay on tail_buf[0] (one beat carries both Cn and Cn+1)
                replay_idx_q <= vlane ? 1'b0 : ~replay_idx_q;

                if (pad_left_q == 3'd1) begin
                    pad_active_q <= 1'b0;
                    pad_left_q   <= 3'd0;
                    // In 4N-mode, transition to phase2 (zero fill)
                    if (!align_mode) begin
                        phase2_active_q <= 1'b1;
                        phase2_left_q   <= vlane ? 3'd2 : 3'd4;
                    end else begin
                        beat_mod_q <= 3'd0;
                    end
                end else begin
                    pad_left_q <= pad_left_q - 3'd1;
                end

            end else if (phase2_active_q) begin
                // ----------------- 4N-mode phase2: zero fill -----------------
                valid_out <= 1'b1;
                for (lane_idx = 0; lane_idx < 16; lane_idx = lane_idx + 1) begin
                    dout_vec[lane_idx] <= {DATA_W{1'b0}};
                end

                if (phase2_left_q == 3'd1) begin
                    phase2_active_q <= 1'b0;
                    phase2_left_q   <= 3'd0;
                    beat_mod_q      <= 3'd0;
                end else begin
                    phase2_left_q <= phase2_left_q - 3'd1;
                end

            end else if (prev_valid_q && !valid_in) begin
                // ----------------- Burst just ended -----------------
                // beat_mod_q already wraps at chunk boundary, so rem_now
                // directly gives beats remaining in current chunk.
                rem_now = beat_mod_q;

                if (align_mode) begin
                    // ===== 8N-mode (PHY chunk=8 beat, VLANE chunk=4 beat) =====
                    // Compute pad_total from rem_now. Chunk sizes differ but
                    // beat_mod_q wraps correctly for each.
                    pad_total = 3'd0;
                    if (vlane) begin
                        // 8N VLANE: chunk = 4 beat
                        case (rem_now)
                            3'd0: pad_total = 3'd0;
                            3'd1: begin pad_total = 3'd3; error_flag_q <= 1'b1; error_flag <= 1'b1; end
                            3'd2: pad_total = 3'd2;
                            3'd3: begin pad_total = 3'd1; error_flag_q <= 1'b1; error_flag <= 1'b1; end
                            default: pad_total = 3'd0;
                        endcase
                    end else begin
                        // 8N PHY: chunk = 8 beat
                        case (rem_now)
                            3'd0: pad_total = 3'd0;
                            3'd1: begin pad_total = 3'd7; error_flag_q <= 1'b1; error_flag <= 1'b1; end
                            3'd2: pad_total = 3'd6;
                            3'd3: begin pad_total = 3'd5; error_flag_q <= 1'b1; error_flag <= 1'b1; end
                            3'd4: pad_total = 3'd4;
                            3'd5: begin pad_total = 3'd3; error_flag_q <= 1'b1; error_flag <= 1'b1; end
                            3'd6: pad_total = 3'd2;
                            3'd7: begin pad_total = 3'd1; error_flag_q <= 1'b1; error_flag <= 1'b1; end
                            default: pad_total = 3'd0;
                        endcase
                    end

                    if (pad_total != 3'd0) begin
                        // Emit first pad beat from tail_buf[0] (Cn)
                        valid_out    <= 1'b1;
                        pad_left_q   <= pad_total - 3'd1;
                        pad_active_q <= (pad_total > 3'd1);
                        // PHY: next beat from tail_buf[1] (Cn+1), toggle thereafter
                        // VLANE: stay on tail_buf[0] (one beat has both Cn and Cn+1)
                        replay_idx_q <= vlane ? 1'b0 : 1'b1;

                        for (lane_idx = 0; lane_idx < 16; lane_idx = lane_idx + 1) begin
                            dout_vec[lane_idx] <= tail_buf[0][lane_idx];
                        end

                        if (pad_total == 3'd1) begin
                            beat_mod_q <= 3'd0;
                        end else begin
                            // pad_active_q handles the rest
                        end
                    end else begin
                        // rem == 0: perfectly aligned
                        beat_mod_q   <= 3'd0;
                        pad_active_q <= 1'b0;
                    end

                end else begin
                    // ===== 4N-mode (PHY chunk=4 beat, VLANE chunk=2 beat) =====
                    // beat_mod_q wraps at chunk boundary, rem_now is direct.
                    pad_phase1 = 3'd0;
                    if (vlane) begin
                        // 4N VLANE: chunk = 2 beat
                        case (rem_now)
                            3'd0: pad_phase1 = 3'd0;
                            3'd1: begin pad_phase1 = 3'd1; error_flag_q <= 1'b1; error_flag <= 1'b1; end
                            default: pad_phase1 = 3'd0;
                        endcase
                    end else begin
                        // 4N PHY: chunk = 4 beat
                        case (rem_now)
                            3'd0: pad_phase1 = 3'd0;
                            3'd1: begin pad_phase1 = 3'd3; error_flag_q <= 1'b1; error_flag <= 1'b1; end
                            3'd2: pad_phase1 = 3'd2;
                            3'd3: begin pad_phase1 = 3'd1; error_flag_q <= 1'b1; error_flag <= 1'b1; end
                            default: pad_phase1 = 3'd0;
                        endcase
                    end

                    if (pad_phase1 != 3'd0) begin
                        // Emit first phase1 pad beat from tail_buf[0] (Cn)
                        valid_out    <= 1'b1;
                        pad_left_q   <= pad_phase1 - 3'd1;
                        pad_active_q <= (pad_phase1 > 3'd1);
                        replay_idx_q <= vlane ? 1'b0 : 1'b1;

                        for (lane_idx = 0; lane_idx < 16; lane_idx = lane_idx + 1) begin
                            dout_vec[lane_idx] <= tail_buf[0][lane_idx];
                        end

                        if (pad_phase1 == 3'd1) begin
                            // Phase1 done in this single beat, go to phase2
                            pad_active_q    <= 1'b0;
                            phase2_active_q <= 1'b1;
                            // Phase2 = fill rest of 8-beat output:
                            // 4N PHY:  4 zero beats
                            // 4N VLANE: 2 zero beats (4N chunk=2 beat → 8N=4 beat → need 2 more)
                            phase2_left_q   <= vlane ? 3'd2 : 3'd4;
                        end else begin
                            // pad_active_q handles rest of phase1, then transitions to phase2
                        end
                    end else begin
                        // rem == 0: phase1 needs no replay, go directly to phase2
                        // Phase2 zero beats: PHY=4, VLANE=2
                        phase2_active_q <= 1'b1;
                        phase2_left_q   <= vlane ? 3'd1 : 3'd3;
                        valid_out <= 1'b1;
                        for (lane_idx = 0; lane_idx < 16; lane_idx = lane_idx + 1) begin
                            dout_vec[lane_idx] <= {DATA_W{1'b0}};
                        end
                    end
                end
            end else begin
                // Idle: no valid_in, no padding
            end

            prev_valid_q <= valid_in;
        end
    end

endmodule
