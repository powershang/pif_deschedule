// =============================================================================
// Module: lane_compactor
// Description: Post-compaction stage after descheduler
//   - Receives N-lane data where lane2/lane3 of each group are 0
//   - Merges 2 consecutive valid outputs into 1 full output (all 4 lanes filled)
//   - Output valid at div2 rate (every other input valid)
//   - Single clock domain (descheduler's clk_out = original slow clock)
// =============================================================================

module lane_compactor #(
    parameter DATA_W = 32
)(
    input  logic                clk,        // = descheduler clk_out (original slow clock)
    input  logic                rst_n,
    input  logic                valid_in,   // from descheduler valid_out

    // N-lane input (from descheduler; lane2/lane3 of each group = 0)
    input  logic [DATA_W-1:0]   a_top0_in, a_top1_in, a_top2_in, a_top3_in,
    input  logic [DATA_W-1:0]   a_bot0_in, a_bot1_in, a_bot2_in, a_bot3_in,
    input  logic [DATA_W-1:0]   b_top0_in, b_top1_in, b_top2_in, b_top3_in,
    input  logic [DATA_W-1:0]   b_bot0_in, b_bot1_in, b_bot2_in, b_bot3_in,

    output logic                valid_out,  // @ div2 rate

    // N-lane output (all 4 lanes filled per group)
    output logic [DATA_W-1:0]   a_top0, a_top1, a_top2, a_top3,
    output logic [DATA_W-1:0]   a_bot0, a_bot1, a_bot2, a_bot3,
    output logic [DATA_W-1:0]   b_top0, b_top1, b_top2, b_top3,
    output logic [DATA_W-1:0]   b_bot0, b_bot1, b_bot2, b_bot3
);

    // =========================================================================
    // Phase toggle: even (0) = store, odd (1) = combine and output
    // =========================================================================
    logic phase;

    // Stored lane0/lane1 from even cycle (per group)
    logic [DATA_W-1:0] st_a_top0, st_a_top1;
    logic [DATA_W-1:0] st_a_bot0, st_a_bot1;
    logic [DATA_W-1:0] st_b_top0, st_b_top1;
    logic [DATA_W-1:0] st_b_bot0, st_b_bot1;

    // Output registers
    logic              out_valid;
    logic [DATA_W-1:0] out_a_top0, out_a_top1, out_a_top2, out_a_top3;
    logic [DATA_W-1:0] out_a_bot0, out_a_bot1, out_a_bot2, out_a_bot3;
    logic [DATA_W-1:0] out_b_top0, out_b_top1, out_b_top2, out_b_top3;
    logic [DATA_W-1:0] out_b_bot0, out_b_bot1, out_b_bot2, out_b_bot3;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase     <= 1'b0;
            out_valid <= 1'b0;
            st_a_top0 <= '0; st_a_top1 <= '0;
            st_a_bot0 <= '0; st_a_bot1 <= '0;
            st_b_top0 <= '0; st_b_top1 <= '0;
            st_b_bot0 <= '0; st_b_bot1 <= '0;
            out_a_top0 <= '0; out_a_top1 <= '0; out_a_top2 <= '0; out_a_top3 <= '0;
            out_a_bot0 <= '0; out_a_bot1 <= '0; out_a_bot2 <= '0; out_a_bot3 <= '0;
            out_b_top0 <= '0; out_b_top1 <= '0; out_b_top2 <= '0; out_b_top3 <= '0;
            out_b_bot0 <= '0; out_b_bot1 <= '0; out_b_bot2 <= '0; out_b_bot3 <= '0;
        end else if (valid_in) begin
            if (!phase) begin
                // --- Even cycle: store lane0, lane1 of each group ---
                st_a_top0 <= a_top0_in; st_a_top1 <= a_top1_in;
                st_a_bot0 <= a_bot0_in; st_a_bot1 <= a_bot1_in;
                st_b_top0 <= b_top0_in; st_b_top1 <= b_top1_in;
                st_b_bot0 <= b_bot0_in; st_b_bot1 <= b_bot1_in;
                out_valid <= 1'b0;
                phase     <= 1'b1;
            end else begin
                // --- Odd cycle: combine stored (lane0,1) + current (lane0,1→lane2,3) ---
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

    // Output assignments
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
