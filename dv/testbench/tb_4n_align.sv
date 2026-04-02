`timescale 1ns/1ps

// =============================================================================
// Testbench: tb_4n_align
// DUT: lanedata_4n_align_process
//
// Tests all pad scenarios:
//   PHY:   len=4(rem0), len=6(rem2), len=5(rem1,err), len=3(rem3,err)
//   VLANE: len=4(even), len=6(even), len=5(odd,err), len=3(odd,err)
//
// Checks:
//   1. valid_out is continuous (no gap) from first to last
//   2. Total output length matches expected 4N / even
//   3. Pad content matches spec (PHY: repeat last 2, VLANE: repeat last 1)
//   4. error_flag correct
// =============================================================================

module tb_4n_align;

    parameter DATA_W = 8;
    parameter CLK_HALF = 5;

    logic              clk, rst_n;
    logic              valid_in, virtual_lane_en;
    logic [DATA_W-1:0] din  [0:15];
    logic [DATA_W-1:0] dout [0:15];
    logic              valid_out;
    logic              error_flag;

    // Flatten for DUT connection
    lanedata_4n_align_process #(.DATA_W(DATA_W)) dut (
        .clk(clk), .rst_n(rst_n),
        .valid_in(valid_in), .virtual_lane_en(virtual_lane_en),
        .din0 (din[0]),  .din1 (din[1]),  .din2 (din[2]),  .din3 (din[3]),
        .din4 (din[4]),  .din5 (din[5]),  .din6 (din[6]),  .din7 (din[7]),
        .din8 (din[8]),  .din9 (din[9]),  .din10(din[10]), .din11(din[11]),
        .din12(din[12]), .din13(din[13]), .din14(din[14]), .din15(din[15]),
        .valid_out(valid_out),
        .dout0 (dout[0]),  .dout1 (dout[1]),  .dout2 (dout[2]),  .dout3 (dout[3]),
        .dout4 (dout[4]),  .dout5 (dout[5]),  .dout6 (dout[6]),  .dout7 (dout[7]),
        .dout8 (dout[8]),  .dout9 (dout[9]),  .dout10(dout[10]), .dout11(dout[11]),
        .dout12(dout[12]), .dout13(dout[13]), .dout14(dout[14]), .dout15(dout[15]),
        .error_flag(error_flag)
    );

    initial clk = 0;
    always #(CLK_HALF) clk = ~clk;

    initial begin
        $dumpfile("/mnt/c/python_work/realtek_pc/PIF_schedule_reorder/wave_4n_align.vcd");
        $dumpvars(0, tb_4n_align);
    end

    // =========================================================================
    // Output capture
    // =========================================================================
    integer              cap_count;
    reg  [DATA_W-1:0]   cap_d0 [0:63];
    integer              cap_gap;       // detect any gap in valid_out
    integer              cap_started;
    integer              cap_seen_end;  // valid_out went 0 after being 1

    always @(posedge clk) begin
        if (rst_n && cap_started) begin
            if (valid_out) begin
                cap_d0[cap_count] = dout[0];
                cap_count = cap_count + 1;
                if (cap_seen_end)
                    cap_gap = 1;
            end else if (cap_count > 0) begin
                cap_seen_end = 1;
            end
        end
    end

    // =========================================================================
    // Tasks
    // =========================================================================
    integer fail_count;
    initial fail_count = 0;

    task do_reset;
        begin
            rst_n = 0;
            valid_in = 0;
            virtual_lane_en = 0;
            for (int i = 0; i < 16; i++) din[i] = '0;
            cap_count = 0;
            cap_gap = 0;
            cap_seen_end = 0;
            cap_started = 0;
            repeat(3) @(posedge clk);
            rst_n = 1;
            @(posedge clk);
        end
    endtask

    task drive_burst;
        input integer len;
        input integer base_val;
        integer i;
        begin
            for (i = 0; i < len; i++) begin
                @(posedge clk);
                #1;
                valid_in = 1;
                din[0] = base_val + i;
                // Use lane0 only for checking, other lanes follow same pattern
                for (int l = 1; l < 16; l++)
                    din[l] = base_val + i + l * 16;
            end
            @(posedge clk);
            #1;
            valid_in = 0;
            for (int l = 0; l < 16; l++) din[l] = '0;
        end
    endtask

    task run_test;
        input [255:0]  test_name;
        input          vlan_en;
        input integer  burst_len;
        input integer  exp_out_len;
        input          exp_error;
        // exp_pad_d0: expected pad pattern for lane0 (last N values)
        integer i;
        integer pad_start;
        begin
            $display("\n--- %0s ---", test_name);
            do_reset;
            virtual_lane_en = vlan_en;
            cap_started = 1;

            drive_burst(burst_len, 8'h10);

            // Wait for output to drain
            repeat(10) @(posedge clk);
            cap_started = 0;

            // Check 1: output count
            if (cap_count !== exp_out_len) begin
                $display("  FAIL output count: got %0d, expected %0d", cap_count, exp_out_len);
                fail_count = fail_count + 1;
            end else begin
                $display("  PASS output count = %0d", cap_count);
            end

            // Check 2: no gap
            if (cap_gap) begin
                $display("  FAIL valid_out had a gap (not continuous)");
                fail_count = fail_count + 1;
            end else begin
                $display("  PASS valid_out continuous");
            end

            // Check 3: error flag
            if (error_flag !== exp_error) begin
                $display("  FAIL error_flag: got %0b, expected %0b", error_flag, exp_error);
                fail_count = fail_count + 1;
            end else begin
                $display("  PASS error_flag = %0b", error_flag);
            end

            // Check 4: passthrough data (first burst_len values)
            pad_start = burst_len;
            for (i = 0; i < burst_len && i < cap_count; i++) begin
                if (cap_d0[i] !== (8'h10 + i)) begin
                    $display("  FAIL data[%0d]: got %0h, expected %0h", i, cap_d0[i], 8'h10 + i);
                    fail_count = fail_count + 1;
                    pad_start = -1;  // skip pad check
                end
            end
            if (pad_start >= 0)
                $display("  PASS passthrough data[0:%0d]", burst_len - 1);

            // Check 5: pad content
            if (pad_start >= 0 && cap_count > burst_len) begin
                if (!vlan_en) begin
                    // PHY: repeat last 2 beats
                    for (i = pad_start; i < cap_count; i++) begin
                        logic [DATA_W-1:0] exp_val;
                        integer offset;
                        offset = (i - pad_start);
                        if (exp_out_len - burst_len == 2) begin
                            // rem=2: repeat last 2 (D[last-1], D[last])
                            exp_val = 8'h10 + burst_len - 2 + offset;
                        end else begin
                            // rem=1,3 error: repeat last beat
                            exp_val = 8'h10 + burst_len - 1;
                        end
                        if (cap_d0[i] !== exp_val) begin
                            $display("  FAIL pad[%0d]: got %0h, expected %0h", i, cap_d0[i], exp_val);
                            fail_count = fail_count + 1;
                        end
                    end
                    $display("  checked PHY pad[%0d:%0d]", pad_start, cap_count - 1);
                end else begin
                    // VLANE: repeat last 1 beat
                    for (i = pad_start; i < cap_count; i++) begin
                        if (cap_d0[i] !== (8'h10 + burst_len - 1)) begin
                            $display("  FAIL pad[%0d]: got %0h, expected %0h",
                                     i, cap_d0[i], 8'h10 + burst_len - 1);
                            fail_count = fail_count + 1;
                        end
                    end
                    $display("  checked VLANE pad[%0d:%0d]", pad_start, cap_count - 1);
                end
            end
        end
    endtask

    // =========================================================================
    // Main
    // =========================================================================
    initial begin
        fail_count = 0;

        //                     name                 vlan  len  exp_out  exp_err
        // PHY mode
        run_test("PHY len=4  rem=0 no-pad",         0,   4,   4,       0);
        run_test("PHY len=8  rem=0 no-pad",         0,   8,   8,       0);
        run_test("PHY len=6  rem=2 pad-2",          0,   6,   8,       0);
        run_test("PHY len=10 rem=2 pad-2",          0,  10,  12,       0);
        run_test("PHY len=5  rem=1 err pad-3",      0,   5,   8,       1);
        run_test("PHY len=3  rem=3 err pad-1",      0,   3,   4,       1);
        run_test("PHY len=7  rem=3 err pad-1",      0,   7,   8,       1);

        // VLANE mode
        run_test("VLANE len=4 even no-pad",          1,   4,   4,       0);
        run_test("VLANE len=6 even no-pad",          1,   6,   6,       0);
        run_test("VLANE len=2 even no-pad",          1,   2,   2,       0);
        run_test("VLANE len=5 odd err pad-1",        1,   5,   6,       1);
        run_test("VLANE len=3 odd err pad-1",        1,   3,   4,       1);
        run_test("VLANE len=7 odd err pad-1",        1,   7,   8,       1);

        $display("\n============================================");
        if (fail_count == 0)
            $display("ALL 4N-ALIGN TESTS PASSED");
        else
            $display("4N-ALIGN TESTS: %0d FAILURE(S)", fail_count);
        $display("============================================");
        $finish;
    end

endmodule
