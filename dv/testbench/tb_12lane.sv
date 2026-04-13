// =============================================================================
// Testbench: tb_12lane (Descheduler)
// DUT: inplace_transpose_buf_multi_lane_descheduler (DATA_W=8, lane_mode=12L)
//
// Clock:
//   clk_in  period = 10ns  (100 MHz, fast clock)
//   clk_out period = 30ns  (33 MHz, slow clock = clk_in / 3)
//
// 12L mode: descheduler receives chunk-format serialized data (with rotation
// on odd cycles) and outputs per-lane-per-cycle format (inverse transpose).
//
// Input stimulus (as produced by scheduler with 12L rotation):
//   even cycle 0: phase0=a_top{10..13}, phase1=a_bot{14..17}, phase2=b_top{18..1b}
//   odd  cycle 1: phase0=b_top{28..2b}, phase1=a_top{20..23}, phase2=a_bot{24..27}
//   even cycle 2: phase0=a_top{30..33}, phase1=a_bot{34..37}, phase2=b_top{38..3b}
//   odd  cycle 3: phase0=b_top{48..4b}, phase1=a_top{40..43}, phase2=a_bot{44..47}
//
// After de-rotation, the chunk data represents:
//   slow0: Lane0[0..3], Lane4[0..3], Lane8[0..3]
//   slow1: Lane1[0..3], Lane5[0..3], Lane9[0..3]
//   slow2: Lane2[0..3], Lane6[0..3], Lane10[0..3]
//   slow3: Lane3[0..3], Lane7[0..3], Lane11[0..3]
//
// Expected output (per-lane-per-cycle, inverse transpose):
//   cycle0: a_top={L0[0],L1[0],L2[0],L3[0]} a_bot={L4[0],..} b_top={L8[0],..}
//   cycle1: a_top={L0[1],L1[1],L2[1],L3[1]} ...
//   cycle2: a_top={L0[2],L1[2],L2[2],L3[2]} ...
//   cycle3: a_top={L0[3],L1[3],L2[3],L3[3]} ...
//
// VCD: wave_12lane_desched.vcd
// =============================================================================

`timescale 1ns/1ps

module tb_12lane;

    localparam DATA_W       = 8;
    localparam CLK_IN_HALF  = 5;    // 10ns period (fast)
    localparam CLK_OUT_HALF = 15;   // 30ns period (slow)
    localparam SIM_END      = 900;

    // DUT signals
    logic                  clk_in, clk_out, rst_n;
    logic [1:0]            lane_mode;
    logic                  valid_in;
    logic [DATA_W-1:0]     din0, din1, din2, din3;
    logic                  valid_out;
    logic [DATA_W-1:0]     a_top0, a_top1, a_top2, a_top3;
    logic [DATA_W-1:0]     a_bot0, a_bot1, a_bot2, a_bot3;
    logic [DATA_W-1:0]     b_top0, b_top1, b_top2, b_top3;
    logic [DATA_W-1:0]     b_bot0, b_bot1, b_bot2, b_bot3;
    logic [2:0]            dbg_state;
    logic [3:0]            dbg_fifo_cnt;

    // DUT instantiation
    inplace_transpose_buf_multi_lane_descheduler #(
        .DATA_W(DATA_W)
    ) dut (
        .clk_in     (clk_in),
        .clk_out    (clk_out),
        .rst_n      (rst_n),
        .lane_mode  (lane_mode),
        .valid_in   (valid_in),
        .din0(din0), .din1(din1), .din2(din2), .din3(din3),
        .valid_out  (valid_out),
        .a_top0(a_top0), .a_top1(a_top1), .a_top2(a_top2), .a_top3(a_top3),
        .a_bot0(a_bot0), .a_bot1(a_bot1), .a_bot2(a_bot2), .a_bot3(a_bot3),
        .b_top0(b_top0), .b_top1(b_top1), .b_top2(b_top2), .b_top3(b_top3),
        .b_bot0(b_bot0), .b_bot1(b_bot1), .b_bot2(b_bot2), .b_bot3(b_bot3),
        .dbg_state(dbg_state),
        .dbg_fifo_cnt(dbg_fifo_cnt)
    );

    // Clock generation
    initial clk_in = 0;
    always #(CLK_IN_HALF) clk_in = ~clk_in;  // 10ns period (fast)

    // clk_out: posedge aligned with clk_in
    initial begin
        clk_out = 0;
        #(CLK_IN_HALF);
        forever #(CLK_OUT_HALF) clk_out = ~clk_out;  // 30ns period (slow)
    end

    // VCD dump
    initial begin
        $dumpfile("wave_12lane_desched.vcd");
        $dumpvars(0, tb_12lane);
    end

    // Reset + static setup
    initial begin
        rst_n      = 0;
        lane_mode  = 2'b10;  // 12L
        valid_in   = 0;
        {din0, din1, din2, din3} = '0;

        repeat(4) @(posedge clk_in);
        rst_n = 1;
    end

    // -------------------------------------------------------------------------
    // Stimulus: Feed serialized data with 12L rotation
    //
    // cycle 0 (even): a_top{10..13}, a_bot{14..17}, b_top{18..1b}
    // cycle 1 (odd):  b_top{28..2b}, a_top{20..23}, a_bot{24..27}
    // cycle 2 (even): a_top{30..33}, a_bot{34..37}, b_top{38..3b}
    // cycle 3 (odd):  b_top{48..4b}, a_top{40..43}, a_bot{44..47}
    // -------------------------------------------------------------------------
    initial begin
        repeat(4) @(posedge clk_in);  // wait for reset

        // --- cycle 0 (even): a_top, a_bot, b_top ---
        @(posedge clk_in);
        valid_in = 1;
        din0 = 8'h10; din1 = 8'h11; din2 = 8'h12; din3 = 8'h13;  // a_top: Lane0[0..3]
        @(posedge clk_in);
        din0 = 8'h14; din1 = 8'h15; din2 = 8'h16; din3 = 8'h17;  // a_bot: Lane4[0..3]
        @(posedge clk_in);
        din0 = 8'h18; din1 = 8'h19; din2 = 8'h1a; din3 = 8'h1b;  // b_top: Lane8[0..3]

        // --- cycle 1 (odd): b_top, a_top, a_bot (rotated!) ---
        @(posedge clk_in);
        din0 = 8'h28; din1 = 8'h29; din2 = 8'h2a; din3 = 8'h2b;  // b_top: Lane9[0..3]
        @(posedge clk_in);
        din0 = 8'h20; din1 = 8'h21; din2 = 8'h22; din3 = 8'h23;  // a_top: Lane1[0..3]
        @(posedge clk_in);
        din0 = 8'h24; din1 = 8'h25; din2 = 8'h26; din3 = 8'h27;  // a_bot: Lane5[0..3]

        // --- cycle 2 (even): a_top, a_bot, b_top ---
        @(posedge clk_in);
        din0 = 8'h30; din1 = 8'h31; din2 = 8'h32; din3 = 8'h33;  // a_top: Lane2[0..3]
        @(posedge clk_in);
        din0 = 8'h34; din1 = 8'h35; din2 = 8'h36; din3 = 8'h37;  // a_bot: Lane6[0..3]
        @(posedge clk_in);
        din0 = 8'h38; din1 = 8'h39; din2 = 8'h3a; din3 = 8'h3b;  // b_top: Lane10[0..3]

        // --- cycle 3 (odd): b_top, a_top, a_bot (rotated!) ---
        @(posedge clk_in);
        din0 = 8'h48; din1 = 8'h49; din2 = 8'h4a; din3 = 8'h4b;  // b_top: Lane11[0..3]
        @(posedge clk_in);
        din0 = 8'h40; din1 = 8'h41; din2 = 8'h42; din3 = 8'h43;  // a_top: Lane3[0..3]
        @(posedge clk_in);
        din0 = 8'h44; din1 = 8'h45; din2 = 8'h46; din3 = 8'h47;  // a_bot: Lane7[0..3]

        // De-assert
        @(posedge clk_in);
        valid_in = 0;
        {din0, din1, din2, din3} = '0;
    end

    // -------------------------------------------------------------------------
    // wclk_cnt: slow clock counter after reset
    // -------------------------------------------------------------------------
    integer wclk_cnt;
    initial wclk_cnt = 0;
    always @(posedge clk_out) begin
        if (!rst_n) wclk_cnt <= 0;
        else        wclk_cnt <= wclk_cnt + 1;
    end

    // -------------------------------------------------------------------------
    // Auto-checker
    // -------------------------------------------------------------------------
    integer exp_idx;
    initial exp_idx = 0;

    integer mismatch_cnt;
    integer check_cnt;

    initial begin
        mismatch_cnt = 0;
        check_cnt    = 0;
    end

    task check_output(
        input [DATA_W-1:0] e_at0, e_at1, e_at2, e_at3,
        input [DATA_W-1:0] e_ab0, e_ab1, e_ab2, e_ab3,
        input [DATA_W-1:0] e_bt0, e_bt1, e_bt2, e_bt3
    );
        check_cnt = check_cnt + 1;
        if (a_top0 !== e_at0) begin $display("[MISMATCH] check#%0d a_top0=%0h exp=%0h", check_cnt, a_top0, e_at0); mismatch_cnt = mismatch_cnt+1; end
        if (a_top1 !== e_at1) begin $display("[MISMATCH] check#%0d a_top1=%0h exp=%0h", check_cnt, a_top1, e_at1); mismatch_cnt = mismatch_cnt+1; end
        if (a_top2 !== e_at2) begin $display("[MISMATCH] check#%0d a_top2=%0h exp=%0h", check_cnt, a_top2, e_at2); mismatch_cnt = mismatch_cnt+1; end
        if (a_top3 !== e_at3) begin $display("[MISMATCH] check#%0d a_top3=%0h exp=%0h", check_cnt, a_top3, e_at3); mismatch_cnt = mismatch_cnt+1; end
        if (a_bot0 !== e_ab0) begin $display("[MISMATCH] check#%0d a_bot0=%0h exp=%0h", check_cnt, a_bot0, e_ab0); mismatch_cnt = mismatch_cnt+1; end
        if (a_bot1 !== e_ab1) begin $display("[MISMATCH] check#%0d a_bot1=%0h exp=%0h", check_cnt, a_bot1, e_ab1); mismatch_cnt = mismatch_cnt+1; end
        if (a_bot2 !== e_ab2) begin $display("[MISMATCH] check#%0d a_bot2=%0h exp=%0h", check_cnt, a_bot2, e_ab2); mismatch_cnt = mismatch_cnt+1; end
        if (a_bot3 !== e_ab3) begin $display("[MISMATCH] check#%0d a_bot3=%0h exp=%0h", check_cnt, a_bot3, e_ab3); mismatch_cnt = mismatch_cnt+1; end
        if (b_top0 !== e_bt0) begin $display("[MISMATCH] check#%0d b_top0=%0h exp=%0h", check_cnt, b_top0, e_bt0); mismatch_cnt = mismatch_cnt+1; end
        if (b_top1 !== e_bt1) begin $display("[MISMATCH] check#%0d b_top1=%0h exp=%0h", check_cnt, b_top1, e_bt1); mismatch_cnt = mismatch_cnt+1; end
        if (b_top2 !== e_bt2) begin $display("[MISMATCH] check#%0d b_top2=%0h exp=%0h", check_cnt, b_top2, e_bt2); mismatch_cnt = mismatch_cnt+1; end
        if (b_top3 !== e_bt3) begin $display("[MISMATCH] check#%0d b_top3=%0h exp=%0h", check_cnt, b_top3, e_bt3); mismatch_cnt = mismatch_cnt+1; end
    endtask

    // Expected output: per-lane-per-cycle (inverse transpose)
    // a_top = {Lane0[t], Lane1[t], Lane2[t], Lane3[t]}
    // a_bot = {Lane4[t], Lane5[t], Lane6[t], Lane7[t]}
    // b_top = {Lane8[t], Lane9[t], Lane10[t], Lane11[t]}
    // b_bot = all 0 (12L only has 12 lanes)
    always @(posedge clk_out) begin
        if (rst_n && valid_out) begin
            $display("[DUT] wclk_cnt=%0d valid_out=1 a_top={%0h,%0h,%0h,%0h} a_bot={%0h,%0h,%0h,%0h} b_top={%0h,%0h,%0h,%0h}",
                wclk_cnt, a_top0, a_top1, a_top2, a_top3,
                a_bot0, a_bot1, a_bot2, a_bot3,
                b_top0, b_top1, b_top2, b_top3);

            case (exp_idx)
                //                  a_top                    a_bot                    b_top
                0: check_output(8'h10,8'h20,8'h30,8'h40, 8'h14,8'h24,8'h34,8'h44, 8'h18,8'h28,8'h38,8'h48);
                1: check_output(8'h11,8'h21,8'h31,8'h41, 8'h15,8'h25,8'h35,8'h45, 8'h19,8'h29,8'h39,8'h49);
                2: check_output(8'h12,8'h22,8'h32,8'h42, 8'h16,8'h26,8'h36,8'h46, 8'h1a,8'h2a,8'h3a,8'h4a);
                3: check_output(8'h13,8'h23,8'h33,8'h43, 8'h17,8'h27,8'h37,8'h47, 8'h1b,8'h2b,8'h3b,8'h4b);
                default: $display("[WARN] Unexpected valid_out at exp_idx=%0d", exp_idx);
            endcase
            exp_idx = exp_idx + 1;
        end
    end

    // Simulation control
    initial begin
        #(SIM_END);
        $display("--------------------------------------------");
        $display("[INFO] Simulation completed at %0t ns", $time);
        $display("[INFO] Total check cycles : %0d", check_cnt);
        $display("[INFO] Total mismatches   : %0d", mismatch_cnt);
        if (mismatch_cnt == 0 && check_cnt >= 4)
            $display("[PASS] 12L descheduler test passed");
        else if (check_cnt < 4)
            $display("[WARN] Only %0d / 4 golden cycles checked - verify timing", check_cnt);
        else
            $display("[FAIL] 12L descheduler test FAILED");
        $display("--------------------------------------------");
        $finish;
    end

endmodule
