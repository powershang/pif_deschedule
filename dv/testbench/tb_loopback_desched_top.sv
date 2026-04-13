// =============================================================================
// Testbench: tb_loopback_desched_top
// End-to-end A-to-A verification:
//   din[0:15] -> scheduler_top -> descheduler(Stage1) -> reverse_transpose -> CHECK
//
// Verifies that reverse_inplace_transpose output (BEFORE compactor) exactly
// matches the original scheduler_top per-lane-per-cycle input.
//
// No compactor in this testbench -- it is out of scope.
//
// Hierarchy:
//   u_sched_top : scheduler_top       (din[0:15] -> dout[0:3])
//   u_desched   : descheduler Stage1  (4-lane fast -> chunk output)
//   u_rev_a     : reverse_transpose   (Group A: lanes 0-7)
//   u_rev_b     : reverse_transpose   (Group B: lanes 8-15)
//   checker     : compare rev outputs with stored din[0:15]
//
// Test matrix: 4 lane modes (4L, 8L, 12L, 16L), PHY mode only.
// Each mode: 16 input cycles of per-lane-per-cycle data.
// =============================================================================

`timescale 1ns/1ps

module tb_loopback_desched_top;

    localparam DATA_W        = 8;
    localparam CLK_FAST_HALF = 5;
    localparam NUM_CYCLES    = 24;
    localparam MAX_CYCLES    = 32;   // storage depth per lane

    // =========================================================================
    // Clocks & reset
    // =========================================================================
    logic clk_fast, clk_slow;
    logic rst_n;
    integer slow_half;

    initial clk_fast = 0;
    always #(CLK_FAST_HALF) clk_fast = ~clk_fast;

    initial begin
        clk_slow = 0;
        slow_half = CLK_FAST_HALF;
        #(CLK_FAST_HALF);
        forever #(slow_half) clk_slow = ~clk_slow;
    end

    // =========================================================================
    // VCD dump
    // =========================================================================
    initial begin
        $dumpfile("wave_loopback_desched_top.vcd");
        $dumpvars(0, tb_loopback_desched_top);
    end

    // =========================================================================
    // Signals
    // =========================================================================
    logic [1:0]        lane_mode;
    logic              valid_in;
    logic [DATA_W-1:0] din0,  din1,  din2,  din3;
    logic [DATA_W-1:0] din4,  din5,  din6,  din7;
    logic [DATA_W-1:0] din8,  din9,  din10, din11;
    logic [DATA_W-1:0] din12, din13, din14, din15;
    logic              align_error_flag;

    // scheduler_top -> descheduler
    logic              sched_valid_out;
    logic [DATA_W-1:0] sched_dout0, sched_dout1, sched_dout2, sched_dout3;
    logic [2:0]        sched_dbg_state;
    logic [3:0]        sched_dbg_fifo_cnt;

    // descheduler -> reverse transpose
    logic              ds_valid_out;
    logic [DATA_W-1:0] ds_a_top0, ds_a_top1, ds_a_top2, ds_a_top3;
    logic [DATA_W-1:0] ds_a_bot0, ds_a_bot1, ds_a_bot2, ds_a_bot3;
    logic [DATA_W-1:0] ds_b_top0, ds_b_top1, ds_b_top2, ds_b_top3;
    logic [DATA_W-1:0] ds_b_bot0, ds_b_bot1, ds_b_bot2, ds_b_bot3;
    logic [2:0]        ds_dbg_state;
    logic [3:0]        ds_dbg_fifo_cnt;

    // reverse transpose Group A outputs
    logic              rev_a_valid;
    logic [DATA_W-1:0] rev_a_d0, rev_a_d1, rev_a_d2, rev_a_d3;
    logic [DATA_W-1:0] rev_a_d4, rev_a_d5, rev_a_d6, rev_a_d7;

    // reverse transpose Group B outputs
    logic              rev_b_valid;
    logic [DATA_W-1:0] rev_b_d0, rev_b_d1, rev_b_d2, rev_b_d3;
    logic [DATA_W-1:0] rev_b_d4, rev_b_d5, rev_b_d6, rev_b_d7;

    // lane_cfg for reverse transpose
    wire rev_a_lane_cfg = (lane_mode == 2'b00) ? 1'b1 : 1'b0;  // LANE4 for 4L, LANE8 otherwise
    wire rev_b_lane_cfg = (lane_mode == 2'b11) ? 1'b0 : 1'b1;  // LANE8 for 16L, LANE4 otherwise
    wire rev_b_valid_in = ds_valid_out & lane_mode[1];           // only active for 12L/16L

    // =========================================================================
    // DUT: scheduler_top
    // =========================================================================
    inplace_transpose_buf_multi_lane_scheduler_top #(.DATA_W(DATA_W)) u_sched_top (
        .clk_in(clk_slow), .clk_out(clk_fast), .rst_n(rst_n),
        .valid_in(valid_in), .lane_mode(lane_mode), .virtual_lane_en(1'b0),
        .din0(din0),   .din1(din1),   .din2(din2),   .din3(din3),
        .din4(din4),   .din5(din5),   .din6(din6),   .din7(din7),
        .din8(din8),   .din9(din9),   .din10(din10), .din11(din11),
        .din12(din12), .din13(din13), .din14(din14), .din15(din15),
        .align_error_flag(align_error_flag),
        .valid_out(sched_valid_out),
        .dout0(sched_dout0), .dout1(sched_dout1),
        .dout2(sched_dout2), .dout3(sched_dout3),
        .dbg_state(sched_dbg_state), .dbg_fifo_cnt(sched_dbg_fifo_cnt)
    );

    // =========================================================================
    // DUT: descheduler Stage 1
    // =========================================================================
    inplace_transpose_buf_multi_lane_descheduler #(.DATA_W(DATA_W)) u_desched (
        .clk_in(clk_fast), .clk_out(clk_slow), .rst_n(rst_n),
        .lane_mode(lane_mode), .valid_in(sched_valid_out),
        .din0(sched_dout0), .din1(sched_dout1),
        .din2(sched_dout2), .din3(sched_dout3),
        .valid_out(ds_valid_out),
        .a_top0(ds_a_top0), .a_top1(ds_a_top1),
        .a_top2(ds_a_top2), .a_top3(ds_a_top3),
        .a_bot0(ds_a_bot0), .a_bot1(ds_a_bot1),
        .a_bot2(ds_a_bot2), .a_bot3(ds_a_bot3),
        .b_top0(ds_b_top0), .b_top1(ds_b_top1),
        .b_top2(ds_b_top2), .b_top3(ds_b_top3),
        .b_bot0(ds_b_bot0), .b_bot1(ds_b_bot1),
        .b_bot2(ds_b_bot2), .b_bot3(ds_b_bot3),
        .dbg_state(ds_dbg_state), .dbg_fifo_cnt(ds_dbg_fifo_cnt)
    );

    // =========================================================================
    // DUT: reverse_inplace_transpose Group A (lanes 0-7)
    // =========================================================================
    reverse_inplace_transpose #(.DATA_W(DATA_W)) u_rev_a (
        .clk(clk_slow), .rst_n(rst_n),
        .lane_cfg(rev_a_lane_cfg), .valid_in(ds_valid_out),
        .din_top0(ds_a_top0), .din_top1(ds_a_top1),
        .din_top2(ds_a_top2), .din_top3(ds_a_top3),
        .din_bot0(ds_a_bot0), .din_bot1(ds_a_bot1),
        .din_bot2(ds_a_bot2), .din_bot3(ds_a_bot3),
        .valid_out(rev_a_valid),
        .dout0(rev_a_d0), .dout1(rev_a_d1), .dout2(rev_a_d2), .dout3(rev_a_d3),
        .dout4(rev_a_d4), .dout5(rev_a_d5), .dout6(rev_a_d6), .dout7(rev_a_d7)
    );

    // =========================================================================
    // DUT: reverse_inplace_transpose Group B (lanes 8-15)
    // =========================================================================
    reverse_inplace_transpose #(.DATA_W(DATA_W)) u_rev_b (
        .clk(clk_slow), .rst_n(rst_n),
        .lane_cfg(rev_b_lane_cfg), .valid_in(rev_b_valid_in),
        .din_top0(ds_b_top0), .din_top1(ds_b_top1),
        .din_top2(ds_b_top2), .din_top3(ds_b_top3),
        .din_bot0(ds_b_bot0), .din_bot1(ds_b_bot1),
        .din_bot2(ds_b_bot2), .din_bot3(ds_b_bot3),
        .valid_out(rev_b_valid),
        .dout0(rev_b_d0), .dout1(rev_b_d1), .dout2(rev_b_d2), .dout3(rev_b_d3),
        .dout4(rev_b_d4), .dout5(rev_b_d5), .dout6(rev_b_d6), .dout7(rev_b_d7)
    );

    // =========================================================================
    // Expected data storage: stored[lane][cycle]
    // =========================================================================
    reg [DATA_W-1:0] stored [0:15][0:MAX_CYCLES-1];

    // =========================================================================
    // Checker
    // =========================================================================
    integer out_idx_a, out_idx_b;
    integer mismatch_cnt;
    integer check_cnt_a, check_cnt_b;
    integer checking_en;
    integer latency_skip_a, latency_skip_b;  // skip first output (9T pipeline fill)

    // Group A checker: rev_a outputs -> din lanes 0-7
    always @(posedge clk_slow) begin
        if (rst_n && checking_en && rev_a_valid) begin
            if (latency_skip_a) begin
                latency_skip_a = 0;
            end else begin
            $display("[REV_A] out_idx=%0d d={%02h,%02h,%02h,%02h,%02h,%02h,%02h,%02h}",
                out_idx_a,
                rev_a_d0, rev_a_d1, rev_a_d2, rev_a_d3,
                rev_a_d4, rev_a_d5, rev_a_d6, rev_a_d7);

            if (rev_a_d0 !== stored[0][out_idx_a]) begin
                $display("  [MISMATCH] A lane0 out_idx=%0d got=%02h exp=%02h", out_idx_a, rev_a_d0, stored[0][out_idx_a]);
                mismatch_cnt = mismatch_cnt + 1;
            end
            if (rev_a_d1 !== stored[1][out_idx_a]) begin
                $display("  [MISMATCH] A lane1 out_idx=%0d got=%02h exp=%02h", out_idx_a, rev_a_d1, stored[1][out_idx_a]);
                mismatch_cnt = mismatch_cnt + 1;
            end
            if (rev_a_d2 !== stored[2][out_idx_a]) begin
                $display("  [MISMATCH] A lane2 out_idx=%0d got=%02h exp=%02h", out_idx_a, rev_a_d2, stored[2][out_idx_a]);
                mismatch_cnt = mismatch_cnt + 1;
            end
            if (rev_a_d3 !== stored[3][out_idx_a]) begin
                $display("  [MISMATCH] A lane3 out_idx=%0d got=%02h exp=%02h", out_idx_a, rev_a_d3, stored[3][out_idx_a]);
                mismatch_cnt = mismatch_cnt + 1;
            end
            if (rev_a_d4 !== stored[4][out_idx_a]) begin
                $display("  [MISMATCH] A lane4 out_idx=%0d got=%02h exp=%02h", out_idx_a, rev_a_d4, stored[4][out_idx_a]);
                mismatch_cnt = mismatch_cnt + 1;
            end
            if (rev_a_d5 !== stored[5][out_idx_a]) begin
                $display("  [MISMATCH] A lane5 out_idx=%0d got=%02h exp=%02h", out_idx_a, rev_a_d5, stored[5][out_idx_a]);
                mismatch_cnt = mismatch_cnt + 1;
            end
            if (rev_a_d6 !== stored[6][out_idx_a]) begin
                $display("  [MISMATCH] A lane6 out_idx=%0d got=%02h exp=%02h", out_idx_a, rev_a_d6, stored[6][out_idx_a]);
                mismatch_cnt = mismatch_cnt + 1;
            end
            if (rev_a_d7 !== stored[7][out_idx_a]) begin
                $display("  [MISMATCH] A lane7 out_idx=%0d got=%02h exp=%02h", out_idx_a, rev_a_d7, stored[7][out_idx_a]);
                mismatch_cnt = mismatch_cnt + 1;
            end

            check_cnt_a = check_cnt_a + 1;
            out_idx_a = out_idx_a + 1;
            end
        end
    end

    // Group B checker: rev_b outputs -> din lanes 8-15
    always @(posedge clk_slow) begin
        if (rst_n && checking_en && rev_b_valid && lane_mode[1]) begin
            if (latency_skip_b) begin
                latency_skip_b = 0;
            end else begin
            $display("[REV_B] out_idx=%0d d={%02h,%02h,%02h,%02h,%02h,%02h,%02h,%02h}",
                out_idx_b,
                rev_b_d0, rev_b_d1, rev_b_d2, rev_b_d3,
                rev_b_d4, rev_b_d5, rev_b_d6, rev_b_d7);

            if (rev_b_d0 !== stored[8][out_idx_b]) begin
                $display("  [MISMATCH] B lane8 out_idx=%0d got=%02h exp=%02h", out_idx_b, rev_b_d0, stored[8][out_idx_b]);
                mismatch_cnt = mismatch_cnt + 1;
            end
            if (rev_b_d1 !== stored[9][out_idx_b]) begin
                $display("  [MISMATCH] B lane9 out_idx=%0d got=%02h exp=%02h", out_idx_b, rev_b_d1, stored[9][out_idx_b]);
                mismatch_cnt = mismatch_cnt + 1;
            end
            if (rev_b_d2 !== stored[10][out_idx_b]) begin
                $display("  [MISMATCH] B lane10 out_idx=%0d got=%02h exp=%02h", out_idx_b, rev_b_d2, stored[10][out_idx_b]);
                mismatch_cnt = mismatch_cnt + 1;
            end
            if (rev_b_d3 !== stored[11][out_idx_b]) begin
                $display("  [MISMATCH] B lane11 out_idx=%0d got=%02h exp=%02h", out_idx_b, rev_b_d3, stored[11][out_idx_b]);
                mismatch_cnt = mismatch_cnt + 1;
            end
            if (rev_b_d4 !== stored[12][out_idx_b]) begin
                $display("  [MISMATCH] B lane12 out_idx=%0d got=%02h exp=%02h", out_idx_b, rev_b_d4, stored[12][out_idx_b]);
                mismatch_cnt = mismatch_cnt + 1;
            end
            if (rev_b_d5 !== stored[13][out_idx_b]) begin
                $display("  [MISMATCH] B lane13 out_idx=%0d got=%02h exp=%02h", out_idx_b, rev_b_d5, stored[13][out_idx_b]);
                mismatch_cnt = mismatch_cnt + 1;
            end
            if (rev_b_d6 !== stored[14][out_idx_b]) begin
                $display("  [MISMATCH] B lane14 out_idx=%0d got=%02h exp=%02h", out_idx_b, rev_b_d6, stored[14][out_idx_b]);
                mismatch_cnt = mismatch_cnt + 1;
            end
            if (rev_b_d7 !== stored[15][out_idx_b]) begin
                $display("  [MISMATCH] B lane15 out_idx=%0d got=%02h exp=%02h", out_idx_b, rev_b_d7, stored[15][out_idx_b]);
                mismatch_cnt = mismatch_cnt + 1;
            end

            check_cnt_b = check_cnt_b + 1;
            out_idx_b = out_idx_b + 1;
            end
        end
    end

    // =========================================================================
    // Tasks
    // =========================================================================
    integer fail_total;
    initial fail_total = 0;

    task clear_inputs;
        begin
            valid_in = 0;
            din0  = 0; din1  = 0; din2  = 0; din3  = 0;
            din4  = 0; din5  = 0; din6  = 0; din7  = 0;
            din8  = 0; din9  = 0; din10 = 0; din11 = 0;
            din12 = 0; din13 = 0; din14 = 0; din15 = 0;
        end
    endtask

    task clear_stored;
        integer lane, cyc;
        begin
            for (lane = 0; lane < 16; lane = lane + 1)
                for (cyc = 0; cyc < MAX_CYCLES; cyc = cyc + 1)
                    stored[lane][cyc] = 0;
        end
    endtask

    task run_mode;
        input [255:0] name;
        input [1:0]   mode;
        input integer ratio;
        integer c;
        integer expected_a, expected_b;
        integer mode_pass;
        begin
            $display("\n========================================");
            $display("--- %0s (mode=%0b, ratio=%0d) ---", name, mode, ratio);
            $display("========================================");

            // Setup
            lane_mode = mode;
            slow_half = ratio * CLK_FAST_HALF;
            mismatch_cnt = 0;
            check_cnt_a = 0;
            check_cnt_b = 0;
            out_idx_a = 0;
            out_idx_b = 0;
            checking_en = 0;
            latency_skip_a = 1;
            latency_skip_b = 1;

            clear_inputs;
            clear_stored;

            // Reset
            rst_n = 0;
            repeat(8) @(posedge clk_fast);
            rst_n = 1;
            repeat(4) @(posedge clk_slow);

            // Enable checking
            checking_en = 1;

            // Drive 16 cycles of per-lane-per-cycle data
            // din[n] = n + cycle_idx * 16  (for active non-zero lanes)
            // din2,3,6,7,10,11,14,15 = 0 always
            // Active lanes per mode:
            //   4L:  din0, din1
            //   8L:  din0, din1, din4, din5
            //   12L: din0, din1, din4, din5, din8, din9
            //   16L: din0, din1, din4, din5, din8, din9, din12, din13
            // Drive per-lane-per-cycle data: din[n] = n + cycle * 16
            // ALL active lanes have data (not just lane 0,1 per group)
            // Active lanes per mode:
            //   4L:  din0..din3
            //   8L:  din0..din7
            //   12L: din0..din11
            //   16L: din0..din15
            for (c = 0; c < NUM_CYCLES; c = c + 1) begin
                @(posedge clk_slow);
                valid_in = 1;

                // Group A lower: lane 0-3 (always active)
                din0 = 8'(0 + c * 16);
                din1 = 8'(1 + c * 16);
                din2 = 8'(2 + c * 16);
                din3 = 8'(3 + c * 16);
                stored[0][c] = 8'(0 + c * 16);
                stored[1][c] = 8'(1 + c * 16);
                stored[2][c] = 8'(2 + c * 16);
                stored[3][c] = 8'(3 + c * 16);

                // Group A upper: lane 4-7 (active for 8L/12L/16L)
                if (mode >= 2'b01) begin
                    din4 = 8'(4 + c * 16);
                    din5 = 8'(5 + c * 16);
                    din6 = 8'(6 + c * 16);
                    din7 = 8'(7 + c * 16);
                end else begin
                    din4 = 0; din5 = 0; din6 = 0; din7 = 0;
                end
                stored[4][c] = (mode >= 2'b01) ? 8'(4 + c * 16) : 8'd0;
                stored[5][c] = (mode >= 2'b01) ? 8'(5 + c * 16) : 8'd0;
                stored[6][c] = (mode >= 2'b01) ? 8'(6 + c * 16) : 8'd0;
                stored[7][c] = (mode >= 2'b01) ? 8'(7 + c * 16) : 8'd0;

                // Group B lower: lane 8-11 (active for 12L/16L)
                if (mode >= 2'b10) begin
                    din8  = 8'(8  + c * 16);
                    din9  = 8'(9  + c * 16);
                    din10 = 8'(10 + c * 16);
                    din11 = 8'(11 + c * 16);
                end else begin
                    din8 = 0; din9 = 0; din10 = 0; din11 = 0;
                end
                stored[8][c]  = (mode >= 2'b10) ? 8'(8  + c * 16) : 8'd0;
                stored[9][c]  = (mode >= 2'b10) ? 8'(9  + c * 16) : 8'd0;
                stored[10][c] = (mode >= 2'b10) ? 8'(10 + c * 16) : 8'd0;
                stored[11][c] = (mode >= 2'b10) ? 8'(11 + c * 16) : 8'd0;

                // Group B upper: lane 12-15 (active for 16L only)
                if (mode == 2'b11) begin
                    din12 = 8'(12 + c * 16);
                    din13 = 8'(13 + c * 16);
                    din14 = 8'(14 + c * 16);
                    din15 = 8'(15 + c * 16);
                end else begin
                    din12 = 0; din13 = 0; din14 = 0; din15 = 0;
                end
                stored[12][c] = (mode == 2'b11) ? 8'(12 + c * 16) : 8'd0;
                stored[13][c] = (mode == 2'b11) ? 8'(13 + c * 16) : 8'd0;
                stored[14][c] = (mode == 2'b11) ? 8'(14 + c * 16) : 8'd0;
                stored[15][c] = (mode == 2'b11) ? 8'(15 + c * 16) : 8'd0;
            end

            // Deassert valid_in
            @(posedge clk_slow);
            clear_inputs;

            // Wait for pipeline to drain (generous: 100 slow cycles)
            repeat(100) @(posedge clk_slow);

            // Disable checking
            checking_en = 0;

            // Report
            // Pipeline fill costs 1 output (latency skip), so expect NUM_CYCLES-1
            expected_a = NUM_CYCLES - 1;
            expected_b = (mode[1]) ? (NUM_CYCLES - 1) : 0;
            mode_pass = 1;

            $display("  Group A: checked %0d / %0d expected", check_cnt_a, expected_a);
            if (expected_b > 0)
                $display("  Group B: checked %0d / %0d expected", check_cnt_b, expected_b);

            if (check_cnt_a < expected_a) begin
                $display("  FAIL: Group A output count insufficient (%0d < %0d)", check_cnt_a, expected_a);
                mode_pass = 0;
            end
            if (expected_b > 0 && check_cnt_b < expected_b) begin
                $display("  FAIL: Group B output count insufficient (%0d < %0d)", check_cnt_b, expected_b);
                mode_pass = 0;
            end
            if (mismatch_cnt > 0) begin
                $display("  FAIL: %0d mismatches detected", mismatch_cnt);
                mode_pass = 0;
            end

            if (mode_pass)
                $display("  PASS %0s", name);
            else begin
                $display("  FAIL %0s", name);
                fail_total = fail_total + 1;
            end
        end
    endtask

    // =========================================================================
    // Main test sequence
    // =========================================================================
    initial begin
        fail_total = 0;
        rst_n = 0;
        lane_mode = 2'b00;
        slow_half = CLK_FAST_HALF;
        checking_en = 0;
        clear_inputs;

        //                  name             mode    ratio
        run_mode("4L  PHY",  2'b00,  1);
        run_mode("8L  PHY",  2'b01,  2);
        run_mode("12L PHY",  2'b10,  3);
        run_mode("16L PHY",  2'b11,  4);

        $display("\n============================================");
        if (fail_total == 0)
            $display("[PASS] ALL LOOPBACK DESCHED_TOP TESTS PASSED (4 modes, %0d input cycles each)", NUM_CYCLES);
        else
            $display("[FAIL] %0d mode(s) failed", fail_total);
        $display("============================================");
        $finish;
    end

    // =========================================================================
    // Timeout
    // =========================================================================
    initial begin
        #200000;
        $display("[TIMEOUT] Simulation exceeded 200000ns");
        $finish;
    end

endmodule
