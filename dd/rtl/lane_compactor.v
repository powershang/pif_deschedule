`timescale 1ns/1ps

// Lane compactor: merges 2 consecutive valid outputs into 1 full output
module lane_compactor (
    clk, rst_n, valid_in,
    a_top0_in, a_top1_in, a_top2_in, a_top3_in,
    a_bot0_in, a_bot1_in, a_bot2_in, a_bot3_in,
    b_top0_in, b_top1_in, b_top2_in, b_top3_in,
    b_bot0_in, b_bot1_in, b_bot2_in, b_bot3_in,
    valid_out,
    a_top0, a_top1, a_top2, a_top3,
    a_bot0, a_bot1, a_bot2, a_bot3,
    b_top0, b_top1, b_top2, b_top3,
    b_bot0, b_bot1, b_bot2, b_bot3
);
    parameter DATA_W = 32;

    input              clk, rst_n, valid_in;
    input  [DATA_W-1:0] a_top0_in, a_top1_in, a_top2_in, a_top3_in;
    input  [DATA_W-1:0] a_bot0_in, a_bot1_in, a_bot2_in, a_bot3_in;
    input  [DATA_W-1:0] b_top0_in, b_top1_in, b_top2_in, b_top3_in;
    input  [DATA_W-1:0] b_bot0_in, b_bot1_in, b_bot2_in, b_bot3_in;
    output             valid_out;
    output [DATA_W-1:0] a_top0, a_top1, a_top2, a_top3;
    output [DATA_W-1:0] a_bot0, a_bot1, a_bot2, a_bot3;
    output [DATA_W-1:0] b_top0, b_top1, b_top2, b_top3;
    output [DATA_W-1:0] b_bot0, b_bot1, b_bot2, b_bot3;

    reg phase;
    reg prev_valid;
    reg [DATA_W-1:0] st_a_top0, st_a_top1, st_a_bot0, st_a_bot1;
    reg [DATA_W-1:0] st_b_top0, st_b_top1, st_b_bot0, st_b_bot1;
    reg              out_valid;
    reg [DATA_W-1:0] out_a_top0, out_a_top1, out_a_top2, out_a_top3;
    reg [DATA_W-1:0] out_a_bot0, out_a_bot1, out_a_bot2, out_a_bot3;
    reg [DATA_W-1:0] out_b_top0, out_b_top1, out_b_top2, out_b_top3;
    reg [DATA_W-1:0] out_b_bot0, out_b_bot1, out_b_bot2, out_b_bot3;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase      <= 1'b0;
            prev_valid <= 1'b0;
            out_valid  <= 1'b0;
            st_a_top0  <= 0; st_a_top1  <= 0;
            st_a_bot0  <= 0; st_a_bot1  <= 0;
            st_b_top0  <= 0; st_b_top1  <= 0;
            st_b_bot0  <= 0; st_b_bot1  <= 0;
            out_a_top0 <= 0; out_a_top1 <= 0; out_a_top2 <= 0; out_a_top3 <= 0;
            out_a_bot0 <= 0; out_a_bot1 <= 0; out_a_bot2 <= 0; out_a_bot3 <= 0;
            out_b_top0 <= 0; out_b_top1 <= 0; out_b_top2 <= 0; out_b_top3 <= 0;
            out_b_bot0 <= 0; out_b_bot1 <= 0; out_b_bot2 <= 0; out_b_bot3 <= 0;
        end else begin
            prev_valid <= valid_in;
            if (valid_in) begin
                // Fresh burst: force phase to even (store phase)
                if (!prev_valid)
                    phase <= 1'b0;

                if (!phase || !prev_valid) begin
                    // Even phase (or fresh burst): store lane0/lane1
                    st_a_top0 <= a_top0_in; st_a_top1 <= a_top1_in;
                    st_a_bot0 <= a_bot0_in; st_a_bot1 <= a_bot1_in;
                    st_b_top0 <= b_top0_in; st_b_top1 <= b_top1_in;
                    st_b_bot0 <= b_bot0_in; st_b_bot1 <= b_bot1_in;
                    out_valid <= 1'b0;
                    phase     <= 1'b1;
                end else begin
                    // Odd phase: combine stored + current
                    out_a_top0 <= st_a_top0; out_a_top1 <= st_a_top1;
                    out_a_top2 <= a_top0_in; out_a_top3 <= a_top1_in;
                    out_a_bot0 <= st_a_bot0; out_a_bot1 <= st_a_bot1;
                    out_a_bot2 <= a_bot0_in; out_a_bot3 <= a_bot1_in;
                    out_b_top0 <= st_b_top0; out_b_top1 <= st_b_top1;
                    out_b_top2 <= b_top0_in; out_b_top3 <= b_top1_in;
                    out_b_bot0 <= st_b_bot0; out_b_bot1 <= st_b_bot1;
                    out_b_bot2 <= b_bot0_in; out_b_bot3 <= b_bot1_in;
                    out_valid <= 1'b1;
                    phase     <= 1'b0;
                end
            end else begin
                out_valid <= 1'b0;
            end
        end
    end

    assign valid_out = out_valid;
    assign a_top0 = out_a_top0; assign a_top1 = out_a_top1;
    assign a_top2 = out_a_top2; assign a_top3 = out_a_top3;
    assign a_bot0 = out_a_bot0; assign a_bot1 = out_a_bot1;
    assign a_bot2 = out_a_bot2; assign a_bot3 = out_a_bot3;
    assign b_top0 = out_b_top0; assign b_top1 = out_b_top1;
    assign b_top2 = out_b_top2; assign b_top3 = out_b_top3;
    assign b_bot0 = out_b_bot0; assign b_bot1 = out_b_bot1;
    assign b_bot2 = out_b_bot2; assign b_bot3 = out_b_bot3;

endmodule
