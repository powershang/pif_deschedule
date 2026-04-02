`timescale 1ns/1ps

module lanedata_4n_align_process (
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

    reg [DATA_W-1:0] din_vec  [0:15];
    reg [DATA_W-1:0] dout_vec [0:15];
    reg [DATA_W-1:0] tail_buf [0:3][0:15];
    reg [1:0]        beat_mod_q;
    reg              pad_active_q;
    reg [1:0]        replay_idx_q;
    reg [1:0]        replay_base_q;
    reg              replay_two_q;
    reg [1:0]        pad_left_q;
    reg              prev_valid_q;
    reg              error_flag_q;

    // Local variables used in always block (moved to module scope for Verilog)
    reg [1:0] rem_now;
    reg [1:0] last_idx;
    reg [1:0] pad_total;

    integer lane_idx;

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

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            beat_mod_q    <= 2'd0;
            pad_active_q  <= 1'b0;
            replay_idx_q  <= 2'd0;
            replay_base_q <= 2'd0;
            replay_two_q  <= 1'b0;
            pad_left_q    <= 2'd0;
            prev_valid_q  <= 1'b0;
            error_flag_q  <= 1'b0;
            valid_out     <= 1'b0;
            error_flag    <= 1'b0;
            for (lane_idx = 0; lane_idx < 16; lane_idx = lane_idx + 1) begin
                dout_vec[lane_idx]    <= 0;
                tail_buf[0][lane_idx] <= 0;
                tail_buf[1][lane_idx] <= 0;
                tail_buf[2][lane_idx] <= 0;
                tail_buf[3][lane_idx] <= 0;
            end
        end else begin
            valid_out  <= 1'b0;
            error_flag <= error_flag_q;
            for (lane_idx = 0; lane_idx < 16; lane_idx = lane_idx + 1)
                dout_vec[lane_idx] <= 0;

            if (valid_in) begin
                valid_out <= 1'b1;
                if (!prev_valid_q) begin
                    // Fresh burst: reset state, write tail_buf[0], advance to 1
                    error_flag_q  <= 1'b0;
                    error_flag    <= 1'b0;
                    pad_active_q  <= 1'b0;
                    pad_left_q    <= 2'd0;
                    replay_two_q  <= 1'b0;
                    for (lane_idx = 0; lane_idx < 16; lane_idx = lane_idx + 1) begin
                        dout_vec[lane_idx]      <= din_vec[lane_idx];
                        tail_buf[0][lane_idx]   <= din_vec[lane_idx];
                    end
                    beat_mod_q <= 2'd1;
                end else begin
                    // Continuing burst
                    for (lane_idx = 0; lane_idx < 16; lane_idx = lane_idx + 1) begin
                        dout_vec[lane_idx]             <= din_vec[lane_idx];
                        tail_buf[beat_mod_q][lane_idx] <= din_vec[lane_idx];
                    end
                    beat_mod_q   <= (beat_mod_q == 2'd3) ? 2'd0 : (beat_mod_q + 2'd1);
                    pad_active_q <= 1'b0;
                    pad_left_q   <= 2'd0;
                end

            end else if (pad_active_q) begin
                valid_out <= 1'b1;
                for (lane_idx = 0; lane_idx < 16; lane_idx = lane_idx + 1)
                    dout_vec[lane_idx] <= tail_buf[replay_idx_q][lane_idx];
                if (pad_left_q == 2'd1) begin
                    pad_active_q <= 1'b0;
                    pad_left_q   <= 2'd0;
                    beat_mod_q   <= 2'd0;
                end else begin
                    pad_left_q <= pad_left_q - 2'd1;
                end
                if (replay_two_q) begin
                    if (replay_idx_q == replay_base_q)
                        replay_idx_q <= replay_base_q + 2'd1;
                    else
                        replay_idx_q <= replay_base_q;
                end

            end else if (prev_valid_q && !valid_in) begin
                rem_now  = beat_mod_q;
                last_idx = beat_mod_q - 2'd1;
                pad_total = 2'd0;

                if (virtual_lane_en) begin
                    if (rem_now[0]) begin
                        pad_total = 2'd1;
                        error_flag_q <= 1'b1;
                        error_flag   <= 1'b1;
                    end
                end else begin
                    case (rem_now)
                        2'd0: pad_total = 2'd0;
                        2'd1: begin pad_total = 2'd3; error_flag_q <= 1'b1; error_flag <= 1'b1; end
                        2'd2: pad_total = 2'd2;
                        2'd3: begin pad_total = 2'd1; error_flag_q <= 1'b1; error_flag <= 1'b1; end
                    endcase
                end

                if (pad_total != 2'd0) begin
                    valid_out    <= 1'b1;
                    pad_left_q   <= pad_total - 2'd1;
                    pad_active_q <= (pad_total > 2'd1);

                    if (virtual_lane_en) begin
                        replay_idx_q  <= last_idx;
                        replay_base_q <= last_idx;
                        replay_two_q  <= 1'b0;
                        for (lane_idx = 0; lane_idx < 16; lane_idx = lane_idx + 1)
                            dout_vec[lane_idx] <= tail_buf[last_idx][lane_idx];
                    end else begin
                        if (rem_now == 2'd2) begin
                            replay_idx_q  <= last_idx;
                            replay_base_q <= last_idx - 2'd1;
                            replay_two_q  <= 1'b1;
                            for (lane_idx = 0; lane_idx < 16; lane_idx = lane_idx + 1)
                                dout_vec[lane_idx] <= tail_buf[last_idx - 2'd1][lane_idx];
                        end else begin
                            replay_idx_q  <= last_idx;
                            replay_base_q <= last_idx;
                            replay_two_q  <= 1'b0;
                            for (lane_idx = 0; lane_idx < 16; lane_idx = lane_idx + 1)
                                dout_vec[lane_idx] <= tail_buf[last_idx][lane_idx];
                        end
                    end
                end else begin
                    beat_mod_q   <= 2'd0;
                    pad_active_q <= 1'b0;
                end
            end

            prev_valid_q <= valid_in;
        end
    end

endmodule
