// =============================================================================
// Testbench: tb_reverse_inplace_transpose
// DUT: reverse_inplace_transpose (DATA_W=32)
//
// Validates chunk-to-per-lane-per-cycle conversion using 8x8 ping-pong buffers.
//
// lane_cfg: 0 = LANE8 (8 rows used)
//           1 = LANE4 (4 rows, 2-beat input per lane)
//
// Input:  chunk format - each valid_in beat carries one lane's 8 samples
//         as din_top[0:3] + din_bot[0:3]
// Output: per-lane-per-cycle - each valid_out cycle carries one sample
//         from each of 8 lanes as dout0..dout7
//
// Test Cases:
//   Test 1: LANE8 basic (8 chunks, verify transposed output)
//   Test 2: LANE4 mode (4 lanes x 2 beats, verify transposed output)
//   Test 3: Continuous streaming ping-pong (16 chunks back-to-back)
//   Test 4: Fresh burst reset (partial fill then new data)
//
// VCD: wave_reverse_inplace_transpose.vcd
// =============================================================================

`timescale 1ns/1ps

module tb_reverse_inplace_transpose;

    localparam DATA_W    = 32;
    localparam CLK_HALF  = 5;
    localparam SIM_END   = 5000;

    // ---------------------------------------------------------------
    // DUT signals
    // ---------------------------------------------------------------
    logic                  clk, rst_n;
    logic                  lane_cfg;
    logic                  valid_in;
    logic [DATA_W-1:0]     din_top0, din_top1, din_top2, din_top3;
    logic [DATA_W-1:0]     din_bot0, din_bot1, din_bot2, din_bot3;
    logic                  valid_out;
    logic [DATA_W-1:0]     dout0, dout1, dout2, dout3;
    logic [DATA_W-1:0]     dout4, dout5, dout6, dout7;

    // ---------------------------------------------------------------
    // DUT instantiation
    // ---------------------------------------------------------------
    reverse_inplace_transpose #(.DATA_W(DATA_W)) dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .lane_cfg  (lane_cfg),
        .valid_in  (valid_in),
        .din_top0  (din_top0),
        .din_top1  (din_top1),
        .din_top2  (din_top2),
        .din_top3  (din_top3),
        .din_bot0  (din_bot0),
        .din_bot1  (din_bot1),
        .din_bot2  (din_bot2),
        .din_bot3  (din_bot3),
        .valid_out (valid_out),
        .dout0     (dout0),
        .dout1     (dout1),
        .dout2     (dout2),
        .dout3     (dout3),
        .dout4     (dout4),
        .dout5     (dout5),
        .dout6     (dout6),
        .dout7     (dout7)
    );

    // ---------------------------------------------------------------
    // Clock generation
    // ---------------------------------------------------------------
    initial clk = 0;
    always #(CLK_HALF) clk = ~clk;

    // ---------------------------------------------------------------
    // VCD dump
    // ---------------------------------------------------------------
    initial begin
        $dumpfile("wave_reverse_inplace_transpose.vcd");
        $dumpvars(0, tb_reverse_inplace_transpose);
    end

    // ---------------------------------------------------------------
    // Error tracking
    // ---------------------------------------------------------------
    integer mismatch_cnt;
    integer check_cnt;
    integer test_num;

    initial begin
        mismatch_cnt = 0;
        check_cnt    = 0;
        test_num     = 0;
    end

    // ---------------------------------------------------------------
    // Helper task: check one output cycle (8 dout values)
    // ---------------------------------------------------------------
    task check_output(
        input [DATA_W-1:0] exp0, exp1, exp2, exp3,
        input [DATA_W-1:0] exp4, exp5, exp6, exp7,
        input string label
    );
        check_cnt = check_cnt + 1;
        if (dout0 !== exp0) begin
            $display("[MISMATCH] %s check#%0d dout0=%0d exp=%0d", label, check_cnt, dout0, exp0);
            mismatch_cnt = mismatch_cnt + 1;
        end
        if (dout1 !== exp1) begin
            $display("[MISMATCH] %s check#%0d dout1=%0d exp=%0d", label, check_cnt, dout1, exp1);
            mismatch_cnt = mismatch_cnt + 1;
        end
        if (dout2 !== exp2) begin
            $display("[MISMATCH] %s check#%0d dout2=%0d exp=%0d", label, check_cnt, dout2, exp2);
            mismatch_cnt = mismatch_cnt + 1;
        end
        if (dout3 !== exp3) begin
            $display("[MISMATCH] %s check#%0d dout3=%0d exp=%0d", label, check_cnt, dout3, exp3);
            mismatch_cnt = mismatch_cnt + 1;
        end
        if (dout4 !== exp4) begin
            $display("[MISMATCH] %s check#%0d dout4=%0d exp=%0d", label, check_cnt, dout4, exp4);
            mismatch_cnt = mismatch_cnt + 1;
        end
        if (dout5 !== exp5) begin
            $display("[MISMATCH] %s check#%0d dout5=%0d exp=%0d", label, check_cnt, dout5, exp5);
            mismatch_cnt = mismatch_cnt + 1;
        end
        if (dout6 !== exp6) begin
            $display("[MISMATCH] %s check#%0d dout6=%0d exp=%0d", label, check_cnt, dout6, exp6);
            mismatch_cnt = mismatch_cnt + 1;
        end
        if (dout7 !== exp7) begin
            $display("[MISMATCH] %s check#%0d dout7=%0d exp=%0d", label, check_cnt, dout7, exp7);
            mismatch_cnt = mismatch_cnt + 1;
        end
    endtask

    // ---------------------------------------------------------------
    // Helper task: drive one chunk (one valid_in beat)
    // ---------------------------------------------------------------
    task drive_chunk(
        input [DATA_W-1:0] t0, t1, t2, t3,
        input [DATA_W-1:0] b0, b1, b2, b3
    );
        @(posedge clk);
        valid_in  = 1;
        din_top0  = t0; din_top1 = t1; din_top2 = t2; din_top3 = t3;
        din_bot0  = b0; din_bot1 = b1; din_bot2 = b2; din_bot3 = b3;
    endtask

    // ---------------------------------------------------------------
    // Helper task: deassert valid_in
    // ---------------------------------------------------------------
    task drive_idle();
        @(posedge clk);
        valid_in  = 0;
        din_top0  = 0; din_top1 = 0; din_top2 = 0; din_top3 = 0;
        din_bot0  = 0; din_bot1 = 0; din_bot2 = 0; din_bot3 = 0;
    endtask

    // ---------------------------------------------------------------
    // Helper task: wait for valid_out and check 8 output cycles
    //   exp[lane][sample] = base + lane*16 + sample
    //   For LANE8: all 8 lanes active
    //   For LANE4: lanes 4-7 are zero
    // ---------------------------------------------------------------
    task automatic check_transposed_block(
        input [DATA_W-1:0] base,
        input integer      active_lanes,  // 8 or 4
        input string       label
    );
        integer s;
        logic [DATA_W-1:0] e0, e1, e2, e3, e4, e5, e6, e7;

        for (s = 0; s < 8; s = s + 1) begin
            // Wait for valid_out
            while (!valid_out) @(posedge clk);

            e0 = base + 0*16 + s;
            e1 = base + 1*16 + s;
            e2 = base + 2*16 + s;
            e3 = base + 3*16 + s;
            if (active_lanes == 8) begin
                e4 = base + 4*16 + s;
                e5 = base + 5*16 + s;
                e6 = base + 6*16 + s;
                e7 = base + 7*16 + s;
            end else begin
                e4 = 0;
                e5 = 0;
                e6 = 0;
                e7 = 0;
            end

            $display("[DUT] %s cycle%0d: dout={%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d}",
                label, s, dout0, dout1, dout2, dout3, dout4, dout5, dout6, dout7);

            check_output(e0, e1, e2, e3, e4, e5, e6, e7, label);

            @(posedge clk);
        end
    endtask

    // ---------------------------------------------------------------
    // Main stimulus
    // ---------------------------------------------------------------
    initial begin
        // Reset
        rst_n    = 0;
        lane_cfg = 0;  // LANE8
        valid_in = 0;
        din_top0 = 0; din_top1 = 0; din_top2 = 0; din_top3 = 0;
        din_bot0 = 0; din_bot1 = 0; din_bot2 = 0; din_bot3 = 0;

        repeat(4) @(posedge clk);
        rst_n = 1;
        repeat(2) @(posedge clk);

        // =========================================================
        // Test 1: LANE8 mode basic
        // =========================================================
        test_num = 1;
        $display("");
        $display("============================================");
        $display("[TEST 1] LANE8 mode basic");
        $display("============================================");

        lane_cfg = 0;  // LANE8

        // Feed 8 chunks: Lane L, sample S = L*16 + S
        // Chunk 0 (Lane 0): din_top = {0,1,2,3}, din_bot = {4,5,6,7}
        drive_chunk(32'd0,  32'd1,  32'd2,  32'd3,
                    32'd4,  32'd5,  32'd6,  32'd7);
        // Chunk 1 (Lane 1): din_top = {16,17,18,19}, din_bot = {20,21,22,23}
        drive_chunk(32'd16, 32'd17, 32'd18, 32'd19,
                    32'd20, 32'd21, 32'd22, 32'd23);
        // Chunk 2 (Lane 2): din_top = {32,33,34,35}, din_bot = {36,37,38,39}
        drive_chunk(32'd32, 32'd33, 32'd34, 32'd35,
                    32'd36, 32'd37, 32'd38, 32'd39);
        // Chunk 3 (Lane 3): din_top = {48,49,50,51}, din_bot = {52,53,54,55}
        drive_chunk(32'd48, 32'd49, 32'd50, 32'd51,
                    32'd52, 32'd53, 32'd54, 32'd55);
        // Chunk 4 (Lane 4): din_top = {64,65,66,67}, din_bot = {68,69,70,71}
        drive_chunk(32'd64, 32'd65, 32'd66, 32'd67,
                    32'd68, 32'd69, 32'd70, 32'd71);
        // Chunk 5 (Lane 5): din_top = {80,81,82,83}, din_bot = {84,85,86,87}
        drive_chunk(32'd80, 32'd81, 32'd82, 32'd83,
                    32'd84, 32'd85, 32'd86, 32'd87);
        // Chunk 6 (Lane 6): din_top = {96,97,98,99}, din_bot = {100,101,102,103}
        drive_chunk(32'd96, 32'd97, 32'd98, 32'd99,
                    32'd100,32'd101,32'd102,32'd103);
        // Chunk 7 (Lane 7): din_top = {112,113,114,115}, din_bot = {116,117,118,119}
        drive_chunk(32'd112,32'd113,32'd114,32'd115,
                    32'd116,32'd117,32'd118,32'd119);

        // Deassert valid_in
        drive_idle();

        // =========================================================
        // Test 2: LANE4 mode (2-beat per lane)
        // =========================================================
        // Wait for test 1 output to flush
        repeat(20) @(posedge clk);

        test_num = 2;
        $display("");
        $display("============================================");
        $display("[TEST 2] LANE4 mode (2-beat per lane)");
        $display("============================================");

        lane_cfg = 1;  // LANE4

        // Lane 0 beat 0: din_top = {0,1,2,3}, din_bot = {0,0,0,0}
        drive_chunk(32'd0,  32'd1,  32'd2,  32'd3,
                    32'd0,  32'd0,  32'd0,  32'd0);
        // Lane 0 beat 1: din_top = {4,5,6,7}, din_bot = {0,0,0,0}
        drive_chunk(32'd4,  32'd5,  32'd6,  32'd7,
                    32'd0,  32'd0,  32'd0,  32'd0);
        // Lane 1 beat 0: din_top = {16,17,18,19}, din_bot = {0,0,0,0}
        drive_chunk(32'd16, 32'd17, 32'd18, 32'd19,
                    32'd0,  32'd0,  32'd0,  32'd0);
        // Lane 1 beat 1: din_top = {20,21,22,23}, din_bot = {0,0,0,0}
        drive_chunk(32'd20, 32'd21, 32'd22, 32'd23,
                    32'd0,  32'd0,  32'd0,  32'd0);
        // Lane 2 beat 0: din_top = {32,33,34,35}, din_bot = {0,0,0,0}
        drive_chunk(32'd32, 32'd33, 32'd34, 32'd35,
                    32'd0,  32'd0,  32'd0,  32'd0);
        // Lane 2 beat 1: din_top = {36,37,38,39}, din_bot = {0,0,0,0}
        drive_chunk(32'd36, 32'd37, 32'd38, 32'd39,
                    32'd0,  32'd0,  32'd0,  32'd0);
        // Lane 3 beat 0: din_top = {48,49,50,51}, din_bot = {0,0,0,0}
        drive_chunk(32'd48, 32'd49, 32'd50, 32'd51,
                    32'd0,  32'd0,  32'd0,  32'd0);
        // Lane 3 beat 1: din_top = {52,53,54,55}, din_bot = {0,0,0,0}
        drive_chunk(32'd52, 32'd53, 32'd54, 32'd55,
                    32'd0,  32'd0,  32'd0,  32'd0);

        // Deassert valid_in
        drive_idle();

        // =========================================================
        // Test 3: Continuous streaming (ping-pong) LANE8
        // =========================================================
        repeat(20) @(posedge clk);

        test_num = 3;
        $display("");
        $display("============================================");
        $display("[TEST 3] Continuous streaming ping-pong");
        $display("============================================");

        lane_cfg = 0;  // LANE8

        // First set: Lane L, sample S = L*16 + S (base=0)
        // Chunk 0 (Lane 0)
        drive_chunk(32'd0,  32'd1,  32'd2,  32'd3,
                    32'd4,  32'd5,  32'd6,  32'd7);
        // Chunk 1 (Lane 1)
        drive_chunk(32'd16, 32'd17, 32'd18, 32'd19,
                    32'd20, 32'd21, 32'd22, 32'd23);
        // Chunk 2 (Lane 2)
        drive_chunk(32'd32, 32'd33, 32'd34, 32'd35,
                    32'd36, 32'd37, 32'd38, 32'd39);
        // Chunk 3 (Lane 3)
        drive_chunk(32'd48, 32'd49, 32'd50, 32'd51,
                    32'd52, 32'd53, 32'd54, 32'd55);
        // Chunk 4 (Lane 4)
        drive_chunk(32'd64, 32'd65, 32'd66, 32'd67,
                    32'd68, 32'd69, 32'd70, 32'd71);
        // Chunk 5 (Lane 5)
        drive_chunk(32'd80, 32'd81, 32'd82, 32'd83,
                    32'd84, 32'd85, 32'd86, 32'd87);
        // Chunk 6 (Lane 6)
        drive_chunk(32'd96, 32'd97, 32'd98, 32'd99,
                    32'd100,32'd101,32'd102,32'd103);
        // Chunk 7 (Lane 7)
        drive_chunk(32'd112,32'd113,32'd114,32'd115,
                    32'd116,32'd117,32'd118,32'd119);

        // Second set immediately: Lane L, sample S = L*16 + S + 128 (base=128)
        // Chunk 8 (Lane 0)
        drive_chunk(32'd128, 32'd129, 32'd130, 32'd131,
                    32'd132, 32'd133, 32'd134, 32'd135);
        // Chunk 9 (Lane 1)
        drive_chunk(32'd144, 32'd145, 32'd146, 32'd147,
                    32'd148, 32'd149, 32'd150, 32'd151);
        // Chunk 10 (Lane 2)
        drive_chunk(32'd160, 32'd161, 32'd162, 32'd163,
                    32'd164, 32'd165, 32'd166, 32'd167);
        // Chunk 11 (Lane 3)
        drive_chunk(32'd176, 32'd177, 32'd178, 32'd179,
                    32'd180, 32'd181, 32'd182, 32'd183);
        // Chunk 12 (Lane 4)
        drive_chunk(32'd192, 32'd193, 32'd194, 32'd195,
                    32'd196, 32'd197, 32'd198, 32'd199);
        // Chunk 13 (Lane 5)
        drive_chunk(32'd208, 32'd209, 32'd210, 32'd211,
                    32'd212, 32'd213, 32'd214, 32'd215);
        // Chunk 14 (Lane 6)
        drive_chunk(32'd224, 32'd225, 32'd226, 32'd227,
                    32'd228, 32'd229, 32'd230, 32'd231);
        // Chunk 15 (Lane 7)
        drive_chunk(32'd240, 32'd241, 32'd242, 32'd243,
                    32'd244, 32'd245, 32'd246, 32'd247);

        // Deassert valid_in
        drive_idle();

        // =========================================================
        // Test 4: Fresh burst reset
        // =========================================================
        repeat(30) @(posedge clk);

        test_num = 4;
        $display("");
        $display("============================================");
        $display("[TEST 4] Fresh burst reset");
        $display("============================================");

        lane_cfg = 0;  // LANE8

        // Feed 4 chunks (partial fill)
        // Chunk 0 (Lane 0): values 200+
        drive_chunk(32'd200, 32'd201, 32'd202, 32'd203,
                    32'd204, 32'd205, 32'd206, 32'd207);
        // Chunk 1 (Lane 1)
        drive_chunk(32'd216, 32'd217, 32'd218, 32'd219,
                    32'd220, 32'd221, 32'd222, 32'd223);
        // Chunk 2 (Lane 2)
        drive_chunk(32'd232, 32'd233, 32'd234, 32'd235,
                    32'd236, 32'd237, 32'd238, 32'd239);
        // Chunk 3 (Lane 3)
        drive_chunk(32'd248, 32'd249, 32'd250, 32'd251,
                    32'd252, 32'd253, 32'd254, 32'd255);

        // Deassert valid_in for several cycles (gap)
        drive_idle();
        repeat(5) @(posedge clk);

        // Reassert with completely new data (fresh burst)
        // New set: Lane L, sample S = L*16 + S + 300 (base=300)
        // Chunk 0 (Lane 0)
        drive_chunk(32'd300, 32'd301, 32'd302, 32'd303,
                    32'd304, 32'd305, 32'd306, 32'd307);
        // Chunk 1 (Lane 1)
        drive_chunk(32'd316, 32'd317, 32'd318, 32'd319,
                    32'd320, 32'd321, 32'd322, 32'd323);
        // Chunk 2 (Lane 2)
        drive_chunk(32'd332, 32'd333, 32'd334, 32'd335,
                    32'd336, 32'd337, 32'd338, 32'd339);
        // Chunk 3 (Lane 3)
        drive_chunk(32'd348, 32'd349, 32'd350, 32'd351,
                    32'd352, 32'd353, 32'd354, 32'd355);
        // Chunk 4 (Lane 4)
        drive_chunk(32'd364, 32'd365, 32'd366, 32'd367,
                    32'd368, 32'd369, 32'd370, 32'd371);
        // Chunk 5 (Lane 5)
        drive_chunk(32'd380, 32'd381, 32'd382, 32'd383,
                    32'd384, 32'd385, 32'd386, 32'd387);
        // Chunk 6 (Lane 6)
        drive_chunk(32'd396, 32'd397, 32'd398, 32'd399,
                    32'd400, 32'd401, 32'd402, 32'd403);
        // Chunk 7 (Lane 7)
        drive_chunk(32'd412, 32'd413, 32'd414, 32'd415,
                    32'd416, 32'd417, 32'd418, 32'd419);

        // Deassert valid_in
        drive_idle();
    end

    // ---------------------------------------------------------------
    // Output checker process
    // ---------------------------------------------------------------
    integer out_cycle_cnt;
    integer t1_mismatch_start, t2_mismatch_start, t3_mismatch_start, t4_mismatch_start;
    integer t1_check_start, t2_check_start, t3_check_start, t4_check_start;

    initial begin
        out_cycle_cnt = 0;
        t1_mismatch_start = 0;
        t2_mismatch_start = 0;
        t3_mismatch_start = 0;
        t4_mismatch_start = 0;
        t1_check_start = 0;
        t2_check_start = 0;
        t3_check_start = 0;
        t4_check_start = 0;

        // Wait for reset
        @(posedge rst_n);

        // =============================================
        // Test 1 output check: LANE8 basic
        // 8 output cycles expected
        // Expected: cycle S => dout_L = L*16 + S
        // =============================================
        t1_check_start    = check_cnt;
        t1_mismatch_start = mismatch_cnt;

        check_transposed_block(32'd0, 8, "T1");

        $display("[TEST 1] checks=%0d mismatches=%0d",
            check_cnt - t1_check_start, mismatch_cnt - t1_mismatch_start);

        // =============================================
        // Test 2 output check: LANE4 mode
        // 8 output cycles expected
        // Expected: cycle S => dout_L = L*16 + S (L<4), dout_L=0 (L>=4)
        // =============================================
        // Wait for test 2 stimulus to arrive
        wait(test_num == 2);
        repeat(2) @(posedge clk);

        t2_check_start    = check_cnt;
        t2_mismatch_start = mismatch_cnt;

        check_transposed_block(32'd0, 4, "T2");

        $display("[TEST 2] checks=%0d mismatches=%0d",
            check_cnt - t2_check_start, mismatch_cnt - t2_mismatch_start);

        // =============================================
        // Test 3 output check: Continuous streaming (two sets)
        // First set: base=0, second set: base=128
        // =============================================
        wait(test_num == 3);
        repeat(2) @(posedge clk);

        t3_check_start    = check_cnt;
        t3_mismatch_start = mismatch_cnt;

        // First set
        check_transposed_block(32'd0, 8, "T3-set1");
        // Second set (no gap expected from ping-pong)
        check_transposed_block(32'd128, 8, "T3-set2");

        $display("[TEST 3] checks=%0d mismatches=%0d",
            check_cnt - t3_check_start, mismatch_cnt - t3_mismatch_start);

        // =============================================
        // Test 4 output check: Fresh burst reset
        // The partial fill (4 chunks) triggers a partial flush when valid
        // drops — this produces 8 output cycles (partial data, expected).
        // Then the fresh burst (base=300) produces 8 more output cycles.
        // We skip the partial flush output, then check the fresh burst.
        // =============================================
        wait(test_num == 4);
        repeat(2) @(posedge clk);

        // Skip partial flush output (8 cycles from the 4-chunk partial fill)
        check_transposed_block(32'd200, 4, "T4-partial");

        t4_check_start    = check_cnt;
        t4_mismatch_start = mismatch_cnt;

        // Check the fresh burst output (base=300)
        check_transposed_block(32'd300, 8, "T4");

        $display("[TEST 4] checks=%0d mismatches=%0d",
            check_cnt - t4_check_start, mismatch_cnt - t4_mismatch_start);
    end

    // ---------------------------------------------------------------
    // Timeout and summary
    // ---------------------------------------------------------------
    initial begin
        #(SIM_END);
        $display("");
        $display("============================================");
        $display("[SUMMARY]");
        $display("  Total check cycles : %0d", check_cnt);
        $display("  Total mismatches   : %0d", mismatch_cnt);
        $display("============================================");
        if (mismatch_cnt == 0 && check_cnt >= 40)
            $display("[PASS] reverse_inplace_transpose all tests passed (%0d checks)", check_cnt);
        else if (check_cnt < 40)
            $display("[WARN] Only %0d / 40 expected checks completed", check_cnt);
        else
            $display("[FAIL] reverse_inplace_transpose tests FAILED (%0d mismatches)", mismatch_cnt);
        $display("============================================");
        $finish;
    end

endmodule
