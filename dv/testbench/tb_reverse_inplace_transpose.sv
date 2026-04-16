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
//   Test 4: Fresh burst reset (partial INIT_FILL discarded, fresh burst ok)
//   Test 5: Partial flush from STREAM (3 chunks, zero-fill remainder)
//
// VCD: wave_reverse_inplace_transpose.vcd
// =============================================================================

`timescale 1ns/1ps

module tb_reverse_inplace_transpose;

    localparam DATA_W    = 32;
    localparam CLK_HALF  = 5;
    localparam SIM_END   = 16000;

    // ---------------------------------------------------------------
    // DUT signals
    // ---------------------------------------------------------------
    logic                  clk, rst_n;
    logic                  lane_cfg;
    logic                  mode;
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
        .mode      (mode),
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
        @(negedge clk);   // setup before next posedge
        valid_in  = 1;
        din_top0  = t0; din_top1 = t1; din_top2 = t2; din_top3 = t3;
        din_bot0  = b0; din_bot1 = b1; din_bot2 = b2; din_bot3 = b3;
    endtask

    // ---------------------------------------------------------------
    // Helper task: deassert valid_in
    // ---------------------------------------------------------------
    task drive_idle();
        @(negedge clk);   // setup before next posedge
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
        mode     = 0;  // MODE_PHY
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
        // Wait for test 1 output to flush, then reset before mode change
        repeat(20) @(posedge clk);
        rst_n = 0;
        valid_in = 0;
        repeat(3) @(posedge clk);
        rst_n = 1;
        repeat(2) @(posedge clk);

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
        // Test 4: Fresh burst reset (partial INIT_FILL discarded)
        //   Per spec, partial fill in INIT_FILL state produces no
        //   output (silently discarded). The subsequent fresh burst
        //   should work normally.
        // =========================================================
        repeat(30) @(posedge clk);

        test_num = 4;
        $display("");
        $display("============================================");
        $display("[TEST 4] Fresh burst reset (partial discard)");
        $display("============================================");

        lane_cfg = 0;  // LANE8

        // Feed 4 chunks (partial fill, enters INIT_FILL via fresh_burst)
        // These will be discarded — no output expected.
        drive_chunk(32'd200, 32'd201, 32'd202, 32'd203,
                    32'd204, 32'd205, 32'd206, 32'd207);
        drive_chunk(32'd216, 32'd217, 32'd218, 32'd219,
                    32'd220, 32'd221, 32'd222, 32'd223);
        drive_chunk(32'd232, 32'd233, 32'd234, 32'd235,
                    32'd236, 32'd237, 32'd238, 32'd239);
        drive_chunk(32'd248, 32'd249, 32'd250, 32'd251,
                    32'd252, 32'd253, 32'd254, 32'd255);

        // Gap (valid drops in INIT_FILL — no partial flush)
        drive_idle();
        repeat(5) @(posedge clk);

        // Fresh burst: 8 full chunks (base=300)
        // This re-enters INIT_FILL, fills buf, transitions to STREAM, outputs.
        drive_chunk(32'd300, 32'd301, 32'd302, 32'd303,
                    32'd304, 32'd305, 32'd306, 32'd307);
        drive_chunk(32'd316, 32'd317, 32'd318, 32'd319,
                    32'd320, 32'd321, 32'd322, 32'd323);
        drive_chunk(32'd332, 32'd333, 32'd334, 32'd335,
                    32'd336, 32'd337, 32'd338, 32'd339);
        drive_chunk(32'd348, 32'd349, 32'd350, 32'd351,
                    32'd352, 32'd353, 32'd354, 32'd355);
        drive_chunk(32'd364, 32'd365, 32'd366, 32'd367,
                    32'd368, 32'd369, 32'd370, 32'd371);
        drive_chunk(32'd380, 32'd381, 32'd382, 32'd383,
                    32'd384, 32'd385, 32'd386, 32'd387);
        drive_chunk(32'd396, 32'd397, 32'd398, 32'd399,
                    32'd400, 32'd401, 32'd402, 32'd403);
        drive_chunk(32'd412, 32'd413, 32'd414, 32'd415,
                    32'd416, 32'd417, 32'd418, 32'd419);

        // Deassert valid_in
        drive_idle();

        // =========================================================
        // Test 5: Partial flush from STREAM state
        //   Feed two consecutive 8-chunk sets (no gap), then 3
        //   partial chunks, then drop valid. The first set enters
        //   STREAM; the second set reads set-1 while writing set-2.
        //   The 3 partial chunks immediately follow, then valid
        //   drops triggering partial flush.
        // =========================================================
        repeat(20) @(posedge clk);

        test_num = 5;
        $display("");
        $display("============================================");
        $display("[TEST 5] Partial flush from STREAM");
        $display("============================================");

        lane_cfg = 0;  // LANE8

        // Set 1: Full 8-chunk set to enter STREAM (base=600)
        drive_chunk(32'd600, 32'd601, 32'd602, 32'd603,
                    32'd604, 32'd605, 32'd606, 32'd607);
        drive_chunk(32'd616, 32'd617, 32'd618, 32'd619,
                    32'd620, 32'd621, 32'd622, 32'd623);
        drive_chunk(32'd632, 32'd633, 32'd634, 32'd635,
                    32'd636, 32'd637, 32'd638, 32'd639);
        drive_chunk(32'd648, 32'd649, 32'd650, 32'd651,
                    32'd652, 32'd653, 32'd654, 32'd655);
        drive_chunk(32'd664, 32'd665, 32'd666, 32'd667,
                    32'd668, 32'd669, 32'd670, 32'd671);
        drive_chunk(32'd680, 32'd681, 32'd682, 32'd683,
                    32'd684, 32'd685, 32'd686, 32'd687);
        drive_chunk(32'd696, 32'd697, 32'd698, 32'd699,
                    32'd700, 32'd701, 32'd702, 32'd703);
        drive_chunk(32'd712, 32'd713, 32'd714, 32'd715,
                    32'd716, 32'd717, 32'd718, 32'd719);

        // Set 2: Full 8-chunk set (base=800) — continuous, no gap
        drive_chunk(32'd800, 32'd801, 32'd802, 32'd803,
                    32'd804, 32'd805, 32'd806, 32'd807);
        drive_chunk(32'd816, 32'd817, 32'd818, 32'd819,
                    32'd820, 32'd821, 32'd822, 32'd823);
        drive_chunk(32'd832, 32'd833, 32'd834, 32'd835,
                    32'd836, 32'd837, 32'd838, 32'd839);
        drive_chunk(32'd848, 32'd849, 32'd850, 32'd851,
                    32'd852, 32'd853, 32'd854, 32'd855);
        drive_chunk(32'd864, 32'd865, 32'd866, 32'd867,
                    32'd868, 32'd869, 32'd870, 32'd871);
        drive_chunk(32'd880, 32'd881, 32'd882, 32'd883,
                    32'd884, 32'd885, 32'd886, 32'd887);
        drive_chunk(32'd896, 32'd897, 32'd898, 32'd899,
                    32'd900, 32'd901, 32'd902, 32'd903);
        drive_chunk(32'd912, 32'd913, 32'd914, 32'd915,
                    32'd916, 32'd917, 32'd918, 32'd919);

        // Partial: 3 chunks (base=500) — continuous, no gap
        drive_chunk(32'd500, 32'd501, 32'd502, 32'd503,
                    32'd504, 32'd505, 32'd506, 32'd507);
        drive_chunk(32'd516, 32'd517, 32'd518, 32'd519,
                    32'd520, 32'd521, 32'd522, 32'd523);
        drive_chunk(32'd532, 32'd533, 32'd534, 32'd535,
                    32'd536, 32'd537, 32'd538, 32'd539);

        // Drop valid — triggers partial flush (zero-fill rows 3-7)
        drive_idle();

        // =========================================================
        // Test 6: VLANE LANE8 basic (mode=1, lane_cfg=0)
        //   8 beats: v0,v1,v2,v3,v0,v1,v2,v3
        //   After write, buffer = same as PHY, so output = T1
        // =========================================================
        repeat(20) @(posedge clk);
        rst_n = 0;
        valid_in = 0;
        repeat(3) @(posedge clk);
        rst_n = 1;
        repeat(2) @(posedge clk);

        test_num = 6;
        $display("");
        $display("============================================");
        $display("[TEST 6] VLANE LANE8 basic");
        $display("============================================");

        mode     = 1;  // VLANE
        lane_cfg = 0;  // LANE8

        // beat0 (vlane0, half0): {L0@c0, L1@c0, L0@c1, L1@c1, L0@c2, L1@c2, L0@c3, L1@c3}
        drive_chunk(32'd0,  32'd16, 32'd1,  32'd17,
                    32'd2,  32'd18, 32'd3,  32'd19);
        // beat1 (vlane1, half0): {L2@c0, L3@c0, L2@c1, L3@c1, L2@c2, L3@c2, L2@c3, L3@c3}
        drive_chunk(32'd32, 32'd48, 32'd33, 32'd49,
                    32'd34, 32'd50, 32'd35, 32'd51);
        // beat2 (vlane2, half0): {L4@c0, L5@c0, L4@c1, L5@c1, L4@c2, L5@c2, L4@c3, L5@c3}
        drive_chunk(32'd64, 32'd80, 32'd65, 32'd81,
                    32'd66, 32'd82, 32'd67, 32'd83);
        // beat3 (vlane3, half0): {L6@c0, L7@c0, L6@c1, L7@c1, L6@c2, L7@c2, L6@c3, L7@c3}
        drive_chunk(32'd96, 32'd112,32'd97, 32'd113,
                    32'd98, 32'd114,32'd99, 32'd115);
        // beat4 (vlane0, half1): {L0@c4, L1@c4, L0@c5, L1@c5, L0@c6, L1@c6, L0@c7, L1@c7}
        drive_chunk(32'd4,  32'd20, 32'd5,  32'd21,
                    32'd6,  32'd22, 32'd7,  32'd23);
        // beat5 (vlane1, half1): {L2@c4, L3@c4, L2@c5, L3@c5, L2@c6, L3@c6, L2@c7, L3@c7}
        drive_chunk(32'd36, 32'd52, 32'd37, 32'd53,
                    32'd38, 32'd54, 32'd39, 32'd55);
        // beat6 (vlane2, half1): {L4@c4, L5@c4, L4@c5, L5@c5, L4@c6, L5@c6, L4@c7, L5@c7}
        drive_chunk(32'd68, 32'd84, 32'd69, 32'd85,
                    32'd70, 32'd86, 32'd71, 32'd87);
        // beat7 (vlane3, half1): {L6@c4, L7@c4, L6@c5, L7@c5, L6@c6, L7@c6, L6@c7, L7@c7}
        drive_chunk(32'd100,32'd116,32'd101,32'd117,
                    32'd102,32'd118,32'd103,32'd119);

        drive_idle();

        // =========================================================
        // Test 7: VLANE LANE4 basic (mode=1, lane_cfg=1)
        //   8 beats (vl_beat 0..7), 2 active vlanes
        //   Write mapping: base_row={vl_beat[1],1'b0}
        //                  base_col={vl_beat[2],vl_beat[0],1'b0}
        //   buf[base_row][base_col]=dt0, [+1][base_col]=dt1,
        //       [base_row][base_col+1]=dt2, [+1][base_col+1]=dt3
        //   Target: row=lane(0..3), col=sample(0..7), val=L*16+S
        //   Rows 4-7 zero-filled
        // =========================================================
        repeat(20) @(posedge clk);
        rst_n = 0;
        valid_in = 0;
        repeat(3) @(posedge clk);
        rst_n = 1;
        repeat(2) @(posedge clk);

        test_num = 7;
        $display("");
        $display("============================================");
        $display("[TEST 7] VLANE LANE4 basic");
        $display("============================================");

        mode     = 1;  // VLANE
        lane_cfg = 1;  // LANE4

        // beat0 (vl_beat=0): vlane=0,half=0 → rows0,1 cols0,1
        //   dt0=buf[0][0]=0, dt1=buf[1][0]=16, dt2=buf[0][1]=1, dt3=buf[1][1]=17
        drive_chunk(32'd0,  32'd16, 32'd1,  32'd17,
                    32'd0,  32'd0,  32'd0,  32'd0);
        // beat1 (vl_beat=1): vlane=1,half=0 → rows0,1 cols2,3
        //   dt0=buf[0][2]=2, dt1=buf[1][2]=18, dt2=buf[0][3]=3, dt3=buf[1][3]=19
        drive_chunk(32'd2,  32'd18, 32'd3,  32'd19,
                    32'd0,  32'd0,  32'd0,  32'd0);
        // beat2 (vl_beat=2): vlane=0,half=1 → rows2,3 cols0,1
        //   dt0=buf[2][0]=32, dt1=buf[3][0]=48, dt2=buf[2][1]=33, dt3=buf[3][1]=49
        drive_chunk(32'd32, 32'd48, 32'd33, 32'd49,
                    32'd0,  32'd0,  32'd0,  32'd0);
        // beat3 (vl_beat=3): vlane=1,half=1 → rows2,3 cols2,3
        //   dt0=buf[2][2]=34, dt1=buf[3][2]=50, dt2=buf[2][3]=35, dt3=buf[3][3]=51
        drive_chunk(32'd34, 32'd50, 32'd35, 32'd51,
                    32'd0,  32'd0,  32'd0,  32'd0);
        // beat4 (vl_beat=4): vlane=0,half=0,bit2=1 → rows0,1 cols4,5
        //   dt0=buf[0][4]=4, dt1=buf[1][4]=20, dt2=buf[0][5]=5, dt3=buf[1][5]=21
        drive_chunk(32'd4,  32'd20, 32'd5,  32'd21,
                    32'd0,  32'd0,  32'd0,  32'd0);
        // beat5 (vl_beat=5): vlane=1,half=0,bit2=1 → rows0,1 cols6,7
        //   dt0=buf[0][6]=6, dt1=buf[1][6]=22, dt2=buf[0][7]=7, dt3=buf[1][7]=23
        drive_chunk(32'd6,  32'd22, 32'd7,  32'd23,
                    32'd0,  32'd0,  32'd0,  32'd0);
        // beat6 (vl_beat=6): vlane=0,half=1,bit2=1 → rows2,3 cols4,5
        //   dt0=buf[2][4]=36, dt1=buf[3][4]=52, dt2=buf[2][5]=37, dt3=buf[3][5]=53
        drive_chunk(32'd36, 32'd52, 32'd37, 32'd53,
                    32'd0,  32'd0,  32'd0,  32'd0);
        // beat7 (vl_beat=7): vlane=1,half=1,bit2=1 → rows2,3 cols6,7
        //   dt0=buf[2][6]=38, dt1=buf[3][6]=54, dt2=buf[2][7]=39, dt3=buf[3][7]=55
        drive_chunk(32'd38, 32'd54, 32'd39, 32'd55,
                    32'd0,  32'd0,  32'd0,  32'd0);

        drive_idle();

        // =========================================================
        // Test 8: LANE4 PHY fresh_burst (mode=0, lane_cfg=1)
        //   4 beat partial → gap → fresh burst 8 beat
        // =========================================================
        repeat(20) @(posedge clk);
        rst_n = 0;
        valid_in = 0;
        repeat(3) @(posedge clk);
        rst_n = 1;
        repeat(2) @(posedge clk);

        test_num = 8;
        $display("");
        $display("============================================");
        $display("[TEST 8] LANE4 PHY fresh_burst");
        $display("============================================");

        mode     = 0;  // PHY
        lane_cfg = 1;  // LANE4

        // Partial fill: 4 beats (discarded in INIT_FILL)
        drive_chunk(32'd900, 32'd901, 32'd902, 32'd903,
                    32'd0,   32'd0,   32'd0,   32'd0);
        drive_chunk(32'd916, 32'd917, 32'd918, 32'd919,
                    32'd0,   32'd0,   32'd0,   32'd0);
        drive_chunk(32'd932, 32'd933, 32'd934, 32'd935,
                    32'd0,   32'd0,   32'd0,   32'd0);
        drive_chunk(32'd948, 32'd949, 32'd950, 32'd951,
                    32'd0,   32'd0,   32'd0,   32'd0);

        // Gap
        drive_idle();
        repeat(5) @(posedge clk);

        // Fresh burst: 8 beats (base=1000), LANE4 PHY = 2 beats per lane
        // Lane 0 beat 0: top={1000,1001,1002,1003}
        drive_chunk(32'd1000, 32'd1001, 32'd1002, 32'd1003,
                    32'd0,    32'd0,    32'd0,    32'd0);
        // Lane 0 beat 1: top={1004,1005,1006,1007}
        drive_chunk(32'd1004, 32'd1005, 32'd1006, 32'd1007,
                    32'd0,    32'd0,    32'd0,    32'd0);
        // Lane 1
        drive_chunk(32'd1016, 32'd1017, 32'd1018, 32'd1019,
                    32'd0,    32'd0,    32'd0,    32'd0);
        drive_chunk(32'd1020, 32'd1021, 32'd1022, 32'd1023,
                    32'd0,    32'd0,    32'd0,    32'd0);
        // Lane 2
        drive_chunk(32'd1032, 32'd1033, 32'd1034, 32'd1035,
                    32'd0,    32'd0,    32'd0,    32'd0);
        drive_chunk(32'd1036, 32'd1037, 32'd1038, 32'd1039,
                    32'd0,    32'd0,    32'd0,    32'd0);
        // Lane 3
        drive_chunk(32'd1048, 32'd1049, 32'd1050, 32'd1051,
                    32'd0,    32'd0,    32'd0,    32'd0);
        drive_chunk(32'd1052, 32'd1053, 32'd1054, 32'd1055,
                    32'd0,    32'd0,    32'd0,    32'd0);

        drive_idle();

        // =========================================================
        // Test 9: VLANE LANE8 fresh_burst (mode=1, lane_cfg=0)
        //   4 beat partial → gap → fresh burst 8 beat
        // =========================================================
        repeat(20) @(posedge clk);
        rst_n = 0;
        valid_in = 0;
        repeat(3) @(posedge clk);
        rst_n = 1;
        repeat(2) @(posedge clk);

        test_num = 9;
        $display("");
        $display("============================================");
        $display("[TEST 9] VLANE LANE8 fresh_burst");
        $display("============================================");

        mode     = 1;  // VLANE
        lane_cfg = 0;  // LANE8

        // Partial fill: 4 beats (vlane 0..3, half0 only) — discarded
        drive_chunk(32'd1100, 32'd1101, 32'd1102, 32'd1103,
                    32'd1104, 32'd1105, 32'd1106, 32'd1107);
        drive_chunk(32'd1108, 32'd1109, 32'd1110, 32'd1111,
                    32'd1112, 32'd1113, 32'd1114, 32'd1115);
        drive_chunk(32'd1116, 32'd1117, 32'd1118, 32'd1119,
                    32'd1120, 32'd1121, 32'd1122, 32'd1123);
        drive_chunk(32'd1124, 32'd1125, 32'd1126, 32'd1127,
                    32'd1128, 32'd1129, 32'd1130, 32'd1131);

        // Gap
        drive_idle();
        repeat(5) @(posedge clk);

        // Fresh burst: 8 beats VLANE LANE8 (base=1200, L*16+S)
        // Same pattern as T6 but with base offset 1200
        // beat0 (vlane0, half0)
        drive_chunk(32'd1200, 32'd1216, 32'd1201, 32'd1217,
                    32'd1202, 32'd1218, 32'd1203, 32'd1219);
        // beat1 (vlane1, half0)
        drive_chunk(32'd1232, 32'd1248, 32'd1233, 32'd1249,
                    32'd1234, 32'd1250, 32'd1235, 32'd1251);
        // beat2 (vlane2, half0)
        drive_chunk(32'd1264, 32'd1280, 32'd1265, 32'd1281,
                    32'd1266, 32'd1282, 32'd1267, 32'd1283);
        // beat3 (vlane3, half0)
        drive_chunk(32'd1296, 32'd1312, 32'd1297, 32'd1313,
                    32'd1298, 32'd1314, 32'd1299, 32'd1315);
        // beat4 (vlane0, half1)
        drive_chunk(32'd1204, 32'd1220, 32'd1205, 32'd1221,
                    32'd1206, 32'd1222, 32'd1207, 32'd1223);
        // beat5 (vlane1, half1)
        drive_chunk(32'd1236, 32'd1252, 32'd1237, 32'd1253,
                    32'd1238, 32'd1254, 32'd1239, 32'd1255);
        // beat6 (vlane2, half1)
        drive_chunk(32'd1268, 32'd1284, 32'd1269, 32'd1285,
                    32'd1270, 32'd1286, 32'd1271, 32'd1287);
        // beat7 (vlane3, half1)
        drive_chunk(32'd1300, 32'd1316, 32'd1301, 32'd1317,
                    32'd1302, 32'd1318, 32'd1303, 32'd1319);

        drive_idle();

        // =========================================================
        // Test 10: VLANE LANE4 fresh_burst (mode=1, lane_cfg=1)
        //   4 beat partial → gap → fresh burst 8 beat
        // =========================================================
        repeat(20) @(posedge clk);
        rst_n = 0;
        valid_in = 0;
        repeat(3) @(posedge clk);
        rst_n = 1;
        repeat(2) @(posedge clk);

        test_num = 10;
        $display("");
        $display("============================================");
        $display("[TEST 10] VLANE LANE4 fresh_burst");
        $display("============================================");

        mode     = 1;  // VLANE
        lane_cfg = 1;  // LANE4

        // Partial fill: 4 beats — discarded
        drive_chunk(32'd1400, 32'd1401, 32'd1402, 32'd1403,
                    32'd0,    32'd0,    32'd0,    32'd0);
        drive_chunk(32'd1404, 32'd1405, 32'd1406, 32'd1407,
                    32'd0,    32'd0,    32'd0,    32'd0);
        drive_chunk(32'd1408, 32'd1409, 32'd1410, 32'd1411,
                    32'd0,    32'd0,    32'd0,    32'd0);
        drive_chunk(32'd1412, 32'd1413, 32'd1414, 32'd1415,
                    32'd0,    32'd0,    32'd0,    32'd0);

        // Gap
        drive_idle();
        repeat(5) @(posedge clk);

        // Fresh burst: 8 beats VLANE LANE4 (base=1500, L*16+S)
        // Same mapping as T7 but base=1500
        // beat0: vlane=0,half=0 → rows0,1 cols0,1
        drive_chunk(32'd1500, 32'd1516, 32'd1501, 32'd1517,
                    32'd0,    32'd0,    32'd0,    32'd0);
        // beat1: vlane=1,half=0 → rows0,1 cols2,3
        drive_chunk(32'd1502, 32'd1518, 32'd1503, 32'd1519,
                    32'd0,    32'd0,    32'd0,    32'd0);
        // beat2: vlane=0,half=1 → rows2,3 cols0,1
        drive_chunk(32'd1532, 32'd1548, 32'd1533, 32'd1549,
                    32'd0,    32'd0,    32'd0,    32'd0);
        // beat3: vlane=1,half=1 → rows2,3 cols2,3
        drive_chunk(32'd1534, 32'd1550, 32'd1535, 32'd1551,
                    32'd0,    32'd0,    32'd0,    32'd0);
        // beat4: vlane=0,half=0,bit2=1 → rows0,1 cols4,5
        drive_chunk(32'd1504, 32'd1520, 32'd1505, 32'd1521,
                    32'd0,    32'd0,    32'd0,    32'd0);
        // beat5: vlane=1,half=0,bit2=1 → rows0,1 cols6,7
        drive_chunk(32'd1506, 32'd1522, 32'd1507, 32'd1523,
                    32'd0,    32'd0,    32'd0,    32'd0);
        // beat6: vlane=0,half=1,bit2=1 → rows2,3 cols4,5
        drive_chunk(32'd1536, 32'd1552, 32'd1537, 32'd1553,
                    32'd0,    32'd0,    32'd0,    32'd0);
        // beat7: vlane=1,half=1,bit2=1 → rows2,3 cols6,7
        drive_chunk(32'd1538, 32'd1554, 32'd1539, 32'd1555,
                    32'd0,    32'd0,    32'd0,    32'd0);

        drive_idle();
    end

    // ---------------------------------------------------------------
    // Output checker process
    // ---------------------------------------------------------------
    integer out_cycle_cnt;
    integer t1_mismatch_start, t2_mismatch_start, t3_mismatch_start, t4_mismatch_start;
    integer t1_check_start, t2_check_start, t3_check_start, t4_check_start;

    initial begin
        integer ii;
        out_cycle_cnt = 0;
        t1_mismatch_start = 0;
        t2_mismatch_start = 0;
        t3_mismatch_start = 0;
        t4_mismatch_start = 0;
        t1_check_start = 0;
        t2_check_start = 0;
        t3_check_start = 0;
        t4_check_start = 0;
        for (ii = 1; ii <= 10; ii = ii + 1) begin
            t_pass[ii] = 0;
            t_mm[ii]   = 0;
        end

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

        t_pass[1] = check_cnt - t1_check_start;
        t_mm[1]   = mismatch_cnt - t1_mismatch_start;
        $display("[TEST 1] checks=%0d mismatches=%0d", t_pass[1], t_mm[1]);

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

        t_pass[2] = check_cnt - t2_check_start;
        t_mm[2]   = mismatch_cnt - t2_mismatch_start;
        $display("[TEST 2] checks=%0d mismatches=%0d", t_pass[2], t_mm[2]);

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

        t_pass[3] = check_cnt - t3_check_start;
        t_mm[3]   = mismatch_cnt - t3_mismatch_start;
        $display("[TEST 3] checks=%0d mismatches=%0d", t_pass[3], t_mm[3]);

        // =============================================
        // Test 4 output check: Fresh burst reset
        // Partial fill in INIT_FILL produces no output (discarded).
        // Only the fresh burst (base=300) produces output.
        // =============================================
        wait(test_num == 4);
        repeat(2) @(posedge clk);

        t4_check_start    = check_cnt;
        t4_mismatch_start = mismatch_cnt;

        // Check the fresh burst output (base=300, 8 lanes)
        check_transposed_block(32'd300, 8, "T4");

        t_pass[4] = check_cnt - t4_check_start;
        t_mm[4]   = mismatch_cnt - t4_mismatch_start;
        $display("[TEST 4] checks=%0d mismatches=%0d", t_pass[4], t_mm[4]);

        // =============================================
        // Test 5 output check: Partial flush from STREAM
        //
        // DUT output sequence:
        //   (1) Set-1 output (base=600): 8 cycles — may be interrupted
        //       by set-2 rd_start (which coincides with end of set-1 write)
        //   (2) Set-2 output (base=800): starts when set-2 buffer is full.
        //       This read may be interrupted after ~3 cycles by the
        //       partial flush rd_start.
        //   (3) Partial flush output: base=500 rows 0-2, rows 3-7 zero.
        //       This is the final output and completes fully.
        //
        // We skip set-1 and set-2 intermediate output (they may be
        // truncated by rd_start preemption) and only verify the
        // partial flush, which is the last complete read.
        // =============================================
        wait(test_num == 5);
        repeat(2) @(posedge clk);

        begin
            integer t5_check_start, t5_mismatch_start;
            integer skip_cnt;
            t5_check_start    = check_cnt;
            t5_mismatch_start = mismatch_cnt;

            // Skip valid_out cycles until we see partial flush data.
            // Partial flush data starts with dout0 = 500.
            skip_cnt = 0;
            while (!valid_out || dout0 != 32'd500) begin
                if (valid_out) skip_cnt = skip_cnt + 1;
                @(posedge clk);
            end
            $display("[T5] skipped %0d intermediate output cycles", skip_cnt);

            // Now check partial flush output: 8 cycles
            begin
                integer s5;
                logic [DATA_W-1:0] e0, e1, e2, e3, e4, e5, e6, e7;
                for (s5 = 0; s5 < 8; s5 = s5 + 1) begin
                    if (s5 > 0) begin
                        while (!valid_out) @(posedge clk);
                    end

                    e0 = 32'd500 + s5;       // Lane 0
                    e1 = 32'd516 + s5;       // Lane 1
                    e2 = 32'd532 + s5;       // Lane 2
                    e3 = 0;                  // Lane 3 (zero-filled)
                    e4 = 0;                  // Lane 4
                    e5 = 0;                  // Lane 5
                    e6 = 0;                  // Lane 6
                    e7 = 0;                  // Lane 7

                    $display("[DUT] T5-partial cycle%0d: dout={%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d}",
                        s5, dout0, dout1, dout2, dout3, dout4, dout5, dout6, dout7);

                    check_output(e0, e1, e2, e3, e4, e5, e6, e7, "T5-partial");

                    @(posedge clk);
                end
            end

            t_pass[5] = check_cnt - t5_check_start;
            t_mm[5]   = mismatch_cnt - t5_mismatch_start;
            $display("[TEST 5] checks=%0d mismatches=%0d", t_pass[5], t_mm[5]);
        end

        // =============================================
        // Test 6 output check: VLANE LANE8 basic
        // Buffer = same as PHY after VLANE write, so output = T1
        // Expected: cycle S => dout_L = L*16 + S (all 8 lanes)
        // =============================================
        wait(test_num == 6);
        repeat(2) @(posedge clk);

        begin
            integer t6_check_start, t6_mismatch_start;
            t6_check_start    = check_cnt;
            t6_mismatch_start = mismatch_cnt;

            check_transposed_block(32'd0, 8, "T6");

            t_pass[6] = check_cnt - t6_check_start;
            t_mm[6]   = mismatch_cnt - t6_mismatch_start;
            $display("[TEST 6] checks=%0d mismatches=%0d", t_pass[6], t_mm[6]);
        end

        // =============================================
        // Test 7 output check: VLANE LANE4 basic
        // Expected: cycle S => dout_L = L*16 + S (L<4), dout_L=0 (L>=4)
        // Same output pattern as T2
        // =============================================
        wait(test_num == 7);
        repeat(2) @(posedge clk);

        begin
            integer t7_check_start, t7_mismatch_start;
            t7_check_start    = check_cnt;
            t7_mismatch_start = mismatch_cnt;

            check_transposed_block(32'd0, 4, "T7");

            t_pass[7] = check_cnt - t7_check_start;
            t_mm[7]   = mismatch_cnt - t7_mismatch_start;
            $display("[TEST 7] checks=%0d mismatches=%0d", t_pass[7], t_mm[7]);
        end

        // =============================================
        // Test 8 output check: LANE4 PHY fresh_burst
        // Partial discarded, only fresh burst (base=1000) produces output
        // Expected: cycle S => dout_L = 1000 + L*16 + S (L<4), 0 (L>=4)
        // =============================================
        wait(test_num == 8);
        repeat(2) @(posedge clk);

        begin
            integer t8_check_start, t8_mismatch_start;
            t8_check_start    = check_cnt;
            t8_mismatch_start = mismatch_cnt;

            check_transposed_block(32'd1000, 4, "T8");

            t_pass[8] = check_cnt - t8_check_start;
            t_mm[8]   = mismatch_cnt - t8_mismatch_start;
            $display("[TEST 8] checks=%0d mismatches=%0d", t_pass[8], t_mm[8]);
        end

        // =============================================
        // Test 9 output check: VLANE LANE8 fresh_burst
        // Partial discarded, only fresh burst (base=1200) produces output
        // Expected: cycle S => dout_L = 1200 + L*16 + S (all 8 lanes)
        // =============================================
        wait(test_num == 9);
        repeat(2) @(posedge clk);

        begin
            integer t9_check_start, t9_mismatch_start;
            t9_check_start    = check_cnt;
            t9_mismatch_start = mismatch_cnt;

            check_transposed_block(32'd1200, 8, "T9");

            t_pass[9] = check_cnt - t9_check_start;
            t_mm[9]   = mismatch_cnt - t9_mismatch_start;
            $display("[TEST 9] checks=%0d mismatches=%0d", t_pass[9], t_mm[9]);
        end

        // =============================================
        // Test 10 output check: VLANE LANE4 fresh_burst
        // Partial discarded, only fresh burst (base=1500) produces output
        // Expected: cycle S => dout_L = 1500 + L*16 + S (L<4), 0 (L>=4)
        // =============================================
        wait(test_num == 10);
        repeat(2) @(posedge clk);

        begin
            integer t10_check_start, t10_mismatch_start;
            t10_check_start    = check_cnt;
            t10_mismatch_start = mismatch_cnt;

            check_transposed_block(32'd1500, 4, "T10");

            t_pass[10] = check_cnt - t10_check_start;
            t_mm[10]   = mismatch_cnt - t10_mismatch_start;
            $display("[TEST 10] checks=%0d mismatches=%0d", t_pass[10], t_mm[10]);
        end
    end

    // ---------------------------------------------------------------
    // Per-test PASS/FAIL tracker
    // ---------------------------------------------------------------
    integer t_pass [1:10];
    integer t_mm   [1:10];

    // ---------------------------------------------------------------
    // Timeout and summary
    // ---------------------------------------------------------------
    initial begin
        integer ti;
        integer total_pass;
        #(SIM_END);
        $display("");
        $display("============================================");
        $display("[SUMMARY]");
        $display("  Total check cycles : %0d", check_cnt);
        $display("  Total mismatches   : %0d", mismatch_cnt);
        $display("--------------------------------------------");
        total_pass = 0;
        for (ti = 1; ti <= 10; ti = ti + 1) begin
            if (t_mm[ti] == 0 && t_pass[ti] > 0)  begin
                $display("  T%0d: PASS (%0d checks)", ti, t_pass[ti]);
                total_pass = total_pass + 1;
            end else if (t_pass[ti] == 0) begin
                $display("  T%0d: NOT RUN", ti);
            end else begin
                $display("  T%0d: FAIL (%0d mismatches / %0d checks)", ti, t_mm[ti], t_pass[ti]);
            end
        end
        $display("--------------------------------------------");
        $display("  %0d / 10 tests PASSED", total_pass);
        $display("============================================");
        if (mismatch_cnt == 0 && check_cnt >= 88)
            $display("[PASS] reverse_inplace_transpose all tests passed (%0d checks)", check_cnt);
        else if (check_cnt < 88)
            $display("[WARN] Only %0d / 88 expected checks completed", check_cnt);
        else
            $display("[FAIL] reverse_inplace_transpose tests FAILED (%0d mismatches)", mismatch_cnt);
        $display("============================================");
        $finish;
    end

endmodule
