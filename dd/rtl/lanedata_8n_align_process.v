`timescale 1ns/1ps

// =============================================================================
// Module: lanedata_8n_align_process
// Description:
//   Burst padding preprocessor. Observes a continuous valid_in burst and, if
//   the burst length is not a multiple of 8 beats, appends pad beats so the
//   total length becomes a multiple of 8 (8N).
//
//   Padding pattern (unified, independent of rem parity):
//       For rem = (burst_len mod 8) != 0, pad_total = 8 - rem beats of the form
//       { c_{N-1}, cN, c_{N-1}, cN, ... } where cN is the last input beat and
//       c_{N-1} is the beat before it. Padding starts from c_{N-1}.
//
//   Input invariant (system-level): burst length is expected to be even.
//   Even rem (0,2,4,6) => error_flag = 0.
//   Odd  rem (1,3,5,7) => error_flag = 1 (defensive guard, still pads to 8N).
//
//   virtual_lane_en is accepted for port compatibility with the old 4N module,
//   but does not alter behavior: 8N alignment is applied uniformly regardless
//   of PHY / VLANE mode.
// =============================================================================

module lanedata_8n_align_process (
    clk, rst_n, valid_in, virtual_lane_en,
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

    // Suppress unused-signal lint: virtual_lane_en is retained for port
    // compatibility but does not influence 8N behavior.
    wire _unused_virtual_lane_en;
    assign _unused_virtual_lane_en = virtual_lane_en;

    // ---------------------------------------------------------------------
    // Input / output vector buses
    // ---------------------------------------------------------------------
    reg [DATA_W-1:0] din_vec  [0:15];
    reg [DATA_W-1:0] dout_vec [0:15];

    // tail_buf is a 2-deep ring buffer storing the most recent 2 input beats.
    // tail_buf_top_q points to the slot holding the LAST beat (cN).
    // The other slot (1 - tail_buf_top_q) holds the second-to-last beat (c_{N-1}).
    reg [DATA_W-1:0] tail_buf [0:1][0:15];
    reg              tail_buf_top_q;

    // Per-burst counters / state
    reg [2:0]        beat_mod_q;     // counts input beats mod 8
    reg              pad_active_q;   // padding is currently being emitted
    reg [2:0]        pad_left_q;     // remaining pad beats (after current emit)
    reg              replay_idx_q;   // which tail_buf slot to emit this pad beat
    reg              prev_valid_q;   // valid_in from previous cycle
    reg              error_flag_q;   // sticky error flag within a burst

    // Combinational scratch (kept at module scope per project style)
    reg [2:0] rem_now;
    reg [2:0] pad_total;
    reg       last_idx;   // tail_buf slot holding cN at burst end
    reg       prev_idx;   // tail_buf slot holding c_{N-1}

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
            tail_buf_top_q <= 1'b0;
            prev_valid_q   <= 1'b0;
            error_flag_q   <= 1'b0;
            valid_out      <= 1'b0;
            error_flag     <= 1'b0;
            rem_now        = 3'd0;
            pad_total      = 3'd0;
            last_idx       = 1'b0;
            prev_idx       = 1'b0;
            for (lane_idx = 0; lane_idx < 16; lane_idx = lane_idx + 1) begin
                dout_vec[lane_idx]    <= {DATA_W{1'b0}};
                tail_buf[0][lane_idx] <= {DATA_W{1'b0}};
                tail_buf[1][lane_idx] <= {DATA_W{1'b0}};
            end
        end else begin
            // Defaults for this cycle
            valid_out  <= 1'b0;
            error_flag <= error_flag_q;
            for (lane_idx = 0; lane_idx < 16; lane_idx = lane_idx + 1)
                dout_vec[lane_idx] <= {DATA_W{1'b0}};

            if (valid_in) begin
                // ----------------- Input beat -----------------
                valid_out <= 1'b1;

                if (!prev_valid_q) begin
                    // Fresh burst: clear sticky state, seed tail_buf slot 0,
                    // set top pointer to 0, next beat will land in slot 1.
                    error_flag_q   <= 1'b0;
                    error_flag     <= 1'b0;
                    pad_active_q   <= 1'b0;
                    pad_left_q     <= 3'd0;
                    tail_buf_top_q <= 1'b0;
                    beat_mod_q     <= 3'd1;
                    for (lane_idx = 0; lane_idx < 16; lane_idx = lane_idx + 1) begin
                        dout_vec[lane_idx]    <= din_vec[lane_idx];
                        tail_buf[0][lane_idx] <= din_vec[lane_idx];
                    end
                end else begin
                    // Continuing burst: write new beat into the "other" slot,
                    // flip the top pointer to point to the newly-written slot.
                    for (lane_idx = 0; lane_idx < 16; lane_idx = lane_idx + 1) begin
                        dout_vec[lane_idx]                          <= din_vec[lane_idx];
                        tail_buf[~tail_buf_top_q][lane_idx]         <= din_vec[lane_idx];
                    end
                    tail_buf_top_q <= ~tail_buf_top_q;
                    beat_mod_q     <= (beat_mod_q == 3'd7) ? 3'd0 : (beat_mod_q + 3'd1);
                    pad_active_q   <= 1'b0;
                    pad_left_q     <= 3'd0;
                end

            end else if (pad_active_q) begin
                // ----------------- Continuing padding -----------------
                valid_out <= 1'b1;
                for (lane_idx = 0; lane_idx < 16; lane_idx = lane_idx + 1)
                    dout_vec[lane_idx] <= tail_buf[replay_idx_q][lane_idx];

                // Toggle between the two tail_buf slots each pad cycle.
                replay_idx_q <= ~replay_idx_q;

                if (pad_left_q == 3'd1) begin
                    pad_active_q <= 1'b0;
                    pad_left_q   <= 3'd0;
                    beat_mod_q   <= 3'd0;
                end else begin
                    pad_left_q <= pad_left_q - 3'd1;
                end

            end else if (prev_valid_q && !valid_in) begin
                // ----------------- Burst just ended -----------------
                rem_now   = beat_mod_q;              // 0..7
                last_idx  = tail_buf_top_q;          // slot holding cN
                prev_idx  = ~tail_buf_top_q;         // slot holding c_{N-1}
                pad_total = 3'd0;

                case (rem_now)
                    3'd0: pad_total = 3'd0;
                    3'd1: begin pad_total = 3'd7; error_flag_q <= 1'b1; error_flag <= 1'b1; end
                    3'd2: pad_total = 3'd6;
                    3'd3: begin pad_total = 3'd5; error_flag_q <= 1'b1; error_flag <= 1'b1; end
                    3'd4: pad_total = 3'd4;
                    3'd5: begin pad_total = 3'd3; error_flag_q <= 1'b1; error_flag <= 1'b1; end
                    3'd6: pad_total = 3'd2;
                    3'd7: begin pad_total = 3'd1; error_flag_q <= 1'b1; error_flag <= 1'b1; end
                endcase

                if (pad_total != 3'd0) begin
                    // Emit the first pad beat this cycle (always c_{N-1}), queue
                    // the remainder to toggle starting from cN.
                    valid_out    <= 1'b1;
                    pad_left_q   <= pad_total - 3'd1;
                    pad_active_q <= (pad_total > 3'd1);
                    // Next pad beat (if any) should emit cN => last_idx.
                    replay_idx_q <= last_idx;

                    for (lane_idx = 0; lane_idx < 16; lane_idx = lane_idx + 1)
                        dout_vec[lane_idx] <= tail_buf[prev_idx][lane_idx];
                end else begin
                    // rem == 0: perfectly aligned, no padding.
                    beat_mod_q   <= 3'd0;
                    pad_active_q <= 1'b0;
                end
            end

            prev_valid_q <= valid_in;
        end
    end

endmodule
