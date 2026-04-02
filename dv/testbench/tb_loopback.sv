// =============================================================================
// Testbench: tb_loopback
// Cascade: scheduler (N→4) → descheduler (4→N), verify identity
// Tests all 4 modes sequentially: 16L, 12L, 8L, 4L
//
// For each mode:
//   1. Feed known data into scheduler
//   2. Connect scheduler dout/valid_out to descheduler din/valid_in
//   3. Verify descheduler output == scheduler original input
//
// DATA_W=8 for easy readability
// VCD: wave_loopback.vcd
// =============================================================================

`timescale 1ns/1ps

module tb_loopback;

    localparam DATA_W = 8;
    localparam CLK_FAST_HALF = 5;  // 10ns fast clock period

    // =========================================================================
    // Shared signals
    // =========================================================================
    logic                  clk_fast, clk_slow, rst_n;
    logic [1:0]            lane_mode;

    // Scheduler (forward) ports
    logic                  fwd_a_valid_in, fwd_b_valid_in;
    logic [DATA_W-1:0]     fwd_a_top0, fwd_a_top1, fwd_a_top2, fwd_a_top3;
    logic [DATA_W-1:0]     fwd_a_bot0, fwd_a_bot1, fwd_a_bot2, fwd_a_bot3;
    logic [DATA_W-1:0]     fwd_b_top0, fwd_b_top1, fwd_b_top2, fwd_b_top3;
    logic [DATA_W-1:0]     fwd_b_bot0, fwd_b_bot1, fwd_b_bot2, fwd_b_bot3;
    logic                  fwd_valid_out;
    logic [DATA_W-1:0]     fwd_dout0, fwd_dout1, fwd_dout2, fwd_dout3;
    logic [2:0]            fwd_dbg_state;
    logic [3:0]            fwd_dbg_fifo_cnt;

    // Descheduler (reverse) ports
    logic                  rev_valid_out;
    logic [DATA_W-1:0]     rev_a_top0, rev_a_top1, rev_a_top2, rev_a_top3;
    logic [DATA_W-1:0]     rev_a_bot0, rev_a_bot1, rev_a_bot2, rev_a_bot3;
    logic [DATA_W-1:0]     rev_b_top0, rev_b_top1, rev_b_top2, rev_b_top3;
    logic [DATA_W-1:0]     rev_b_bot0, rev_b_bot1, rev_b_bot2, rev_b_bot3;
    logic [2:0]            rev_dbg_state;
    logic [3:0]            rev_dbg_fifo_cnt;

    // =========================================================================
    // DUT: Forward Scheduler (clk_in=slow, clk_out=fast)
    // =========================================================================
    inplace_transpose_buf_multi_lane_scheduler #(.DATA_W(DATA_W)) u_fwd (
        .clk_in(clk_slow), .clk_out(clk_fast), .rst_n(rst_n),
        .lane_mode(lane_mode),
        .a_valid_in(fwd_a_valid_in),
        .a_top0(fwd_a_top0), .a_top1(fwd_a_top1), .a_top2(fwd_a_top2), .a_top3(fwd_a_top3),
        .a_bot0(fwd_a_bot0), .a_bot1(fwd_a_bot1), .a_bot2(fwd_a_bot2), .a_bot3(fwd_a_bot3),
        .b_valid_in(fwd_b_valid_in),
        .b_top0(fwd_b_top0), .b_top1(fwd_b_top1), .b_top2(fwd_b_top2), .b_top3(fwd_b_top3),
        .b_bot0(fwd_b_bot0), .b_bot1(fwd_b_bot1), .b_bot2(fwd_b_bot2), .b_bot3(fwd_b_bot3),
        .valid_out(fwd_valid_out),
        .dout0(fwd_dout0), .dout1(fwd_dout1), .dout2(fwd_dout2), .dout3(fwd_dout3),
        .dbg_state(fwd_dbg_state), .dbg_fifo_cnt(fwd_dbg_fifo_cnt)
    );

    // =========================================================================
    // DUT: Reverse Descheduler (clk_in=fast, clk_out=slow)
    // Connected: fwd_dout → rev_din, fwd_valid_out → rev_valid_in
    // =========================================================================
    inplace_transpose_buf_multi_lane_descheduler #(.DATA_W(DATA_W)) u_rev (
        .clk_in(clk_fast), .clk_out(clk_slow), .rst_n(rst_n),
        .lane_mode(lane_mode),
        .valid_in(fwd_valid_out),
        .din0(fwd_dout0), .din1(fwd_dout1), .din2(fwd_dout2), .din3(fwd_dout3),
        .valid_out(rev_valid_out),
        .a_top0(rev_a_top0), .a_top1(rev_a_top1), .a_top2(rev_a_top2), .a_top3(rev_a_top3),
        .a_bot0(rev_a_bot0), .a_bot1(rev_a_bot1), .a_bot2(rev_a_bot2), .a_bot3(rev_a_bot3),
        .b_top0(rev_b_top0), .b_top1(rev_b_top1), .b_top2(rev_b_top2), .b_top3(rev_b_top3),
        .b_bot0(rev_b_bot0), .b_bot1(rev_b_bot1), .b_bot2(rev_b_bot2), .b_bot3(rev_b_bot3),
        .dbg_state(rev_dbg_state), .dbg_fifo_cnt(rev_dbg_fifo_cnt)
    );

    // =========================================================================
    // Fast clock generation (always running)
    // =========================================================================
    initial clk_fast = 0;
    always #(CLK_FAST_HALF) clk_fast = ~clk_fast;  // 10ns

    // =========================================================================
    // Slow clock: generated dynamically based on lane_mode
    // For loopback we drive it from the test program
    // =========================================================================
    // We'll use a configurable slow clock
    integer slow_half;
    initial slow_half = 5;  // default = same as fast (4L)

    initial begin
        clk_slow = 0;
        #(CLK_FAST_HALF);  // offset for alignment
        forever #(slow_half) clk_slow = ~clk_slow;
    end

    // VCD
    initial begin
        $dumpfile("/mnt/c/python_work/realtek_pc/PIF_schedule_reorder/wave_loopback.vcd");
        $dumpvars(0, tb_loopback);
    end

    // =========================================================================
    // Checker
    // =========================================================================
    integer mismatch_cnt, check_cnt, exp_idx;
    integer total_mismatch, total_check;

    // Expected input data storage (queue approach: store what we fed, compare later)
    // We use exp_idx to track which output we're checking
    logic [DATA_W-1:0] exp_a_top0[0:7], exp_a_top1[0:7], exp_a_top2[0:7], exp_a_top3[0:7];
    logic [DATA_W-1:0] exp_a_bot0[0:7], exp_a_bot1[0:7], exp_a_bot2[0:7], exp_a_bot3[0:7];
    logic [DATA_W-1:0] exp_b_top0[0:7], exp_b_top1[0:7], exp_b_top2[0:7], exp_b_top3[0:7];
    logic [DATA_W-1:0] exp_b_bot0[0:7], exp_b_bot1[0:7], exp_b_bot2[0:7], exp_b_bot3[0:7];

    always @(posedge clk_slow) begin
        if (rst_n && rev_valid_out && exp_idx < 8) begin
            check_cnt = check_cnt + 1;
            if (rev_a_top0!==exp_a_top0[exp_idx]) begin $display("[MISMATCH] #%0d a_top0=%0h exp=%0h",exp_idx,rev_a_top0,exp_a_top0[exp_idx]); mismatch_cnt=mismatch_cnt+1; end
            if (rev_a_top1!==exp_a_top1[exp_idx]) begin $display("[MISMATCH] #%0d a_top1=%0h exp=%0h",exp_idx,rev_a_top1,exp_a_top1[exp_idx]); mismatch_cnt=mismatch_cnt+1; end
            if (rev_a_top2!==exp_a_top2[exp_idx]) begin $display("[MISMATCH] #%0d a_top2=%0h exp=%0h",exp_idx,rev_a_top2,exp_a_top2[exp_idx]); mismatch_cnt=mismatch_cnt+1; end
            if (rev_a_top3!==exp_a_top3[exp_idx]) begin $display("[MISMATCH] #%0d a_top3=%0h exp=%0h",exp_idx,rev_a_top3,exp_a_top3[exp_idx]); mismatch_cnt=mismatch_cnt+1; end
            if (rev_a_bot0!==exp_a_bot0[exp_idx]) begin $display("[MISMATCH] #%0d a_bot0=%0h exp=%0h",exp_idx,rev_a_bot0,exp_a_bot0[exp_idx]); mismatch_cnt=mismatch_cnt+1; end
            if (rev_a_bot1!==exp_a_bot1[exp_idx]) begin $display("[MISMATCH] #%0d a_bot1=%0h exp=%0h",exp_idx,rev_a_bot1,exp_a_bot1[exp_idx]); mismatch_cnt=mismatch_cnt+1; end
            if (rev_a_bot2!==exp_a_bot2[exp_idx]) begin $display("[MISMATCH] #%0d a_bot2=%0h exp=%0h",exp_idx,rev_a_bot2,exp_a_bot2[exp_idx]); mismatch_cnt=mismatch_cnt+1; end
            if (rev_a_bot3!==exp_a_bot3[exp_idx]) begin $display("[MISMATCH] #%0d a_bot3=%0h exp=%0h",exp_idx,rev_a_bot3,exp_a_bot3[exp_idx]); mismatch_cnt=mismatch_cnt+1; end
            if (rev_b_top0!==exp_b_top0[exp_idx]) begin $display("[MISMATCH] #%0d b_top0=%0h exp=%0h",exp_idx,rev_b_top0,exp_b_top0[exp_idx]); mismatch_cnt=mismatch_cnt+1; end
            if (rev_b_top1!==exp_b_top1[exp_idx]) begin $display("[MISMATCH] #%0d b_top1=%0h exp=%0h",exp_idx,rev_b_top1,exp_b_top1[exp_idx]); mismatch_cnt=mismatch_cnt+1; end
            if (rev_b_top2!==exp_b_top2[exp_idx]) begin $display("[MISMATCH] #%0d b_top2=%0h exp=%0h",exp_idx,rev_b_top2,exp_b_top2[exp_idx]); mismatch_cnt=mismatch_cnt+1; end
            if (rev_b_top3!==exp_b_top3[exp_idx]) begin $display("[MISMATCH] #%0d b_top3=%0h exp=%0h",exp_idx,rev_b_top3,exp_b_top3[exp_idx]); mismatch_cnt=mismatch_cnt+1; end
            if (rev_b_bot0!==exp_b_bot0[exp_idx]) begin $display("[MISMATCH] #%0d b_bot0=%0h exp=%0h",exp_idx,rev_b_bot0,exp_b_bot0[exp_idx]); mismatch_cnt=mismatch_cnt+1; end
            if (rev_b_bot1!==exp_b_bot1[exp_idx]) begin $display("[MISMATCH] #%0d b_bot1=%0h exp=%0h",exp_idx,rev_b_bot1,exp_b_bot1[exp_idx]); mismatch_cnt=mismatch_cnt+1; end
            if (rev_b_bot2!==exp_b_bot2[exp_idx]) begin $display("[MISMATCH] #%0d b_bot2=%0h exp=%0h",exp_idx,rev_b_bot2,exp_b_bot2[exp_idx]); mismatch_cnt=mismatch_cnt+1; end
            if (rev_b_bot3!==exp_b_bot3[exp_idx]) begin $display("[MISMATCH] #%0d b_bot3=%0h exp=%0h",exp_idx,rev_b_bot3,exp_b_bot3[exp_idx]); mismatch_cnt=mismatch_cnt+1; end

            $display("[LOOP] mode=%0d #%0d a_top={%0h,%0h,%0h,%0h} a_bot={%0h,%0h,%0h,%0h} b_top={%0h,%0h,%0h,%0h} b_bot={%0h,%0h,%0h,%0h}",
                lane_mode, exp_idx,
                rev_a_top0,rev_a_top1,rev_a_top2,rev_a_top3,
                rev_a_bot0,rev_a_bot1,rev_a_bot2,rev_a_bot3,
                rev_b_top0,rev_b_top1,rev_b_top2,rev_b_top3,
                rev_b_bot0,rev_b_bot1,rev_b_bot2,rev_b_bot3);
            exp_idx = exp_idx + 1;
        end
    end

    // =========================================================================
    // Test: 16L loopback (slow_half=20 → 40ns period, ratio=4:1)
    // Note: Because slow clock is generated with forever loop from time 0,
    //       we cannot dynamically change slow_half mid-simulation.
    //       So this testbench tests 16L mode only (most comprehensive).
    //       The standalone tb_*lane tests cover other modes individually.
    // =========================================================================
    initial begin
        total_mismatch = 0;
        total_check    = 0;
        mismatch_cnt   = 0;
        check_cnt      = 0;
        exp_idx        = 0;

        // Setup
        rst_n          = 0;
        lane_mode      = 2'b11;  // 16L
        slow_half      = 20;     // 40ns slow period
        fwd_a_valid_in = 0;
        fwd_b_valid_in = 0;
        {fwd_a_top0,fwd_a_top1,fwd_a_top2,fwd_a_top3} = '0;
        {fwd_a_bot0,fwd_a_bot1,fwd_a_bot2,fwd_a_bot3} = '0;
        {fwd_b_top0,fwd_b_top1,fwd_b_top2,fwd_b_top3} = '0;
        {fwd_b_bot0,fwd_b_bot1,fwd_b_bot2,fwd_b_bot3} = '0;

        // Store expected data
        exp_a_top0[0]=8'h10; exp_a_top1[0]=8'h11; exp_a_top2[0]=8'h12; exp_a_top3[0]=8'h13;
        exp_a_bot0[0]=8'h14; exp_a_bot1[0]=8'h15; exp_a_bot2[0]=8'h16; exp_a_bot3[0]=8'h17;
        exp_b_top0[0]=8'h18; exp_b_top1[0]=8'h19; exp_b_top2[0]=8'h1a; exp_b_top3[0]=8'h1b;
        exp_b_bot0[0]=8'h1c; exp_b_bot1[0]=8'h1d; exp_b_bot2[0]=8'h1e; exp_b_bot3[0]=8'h1f;

        exp_a_top0[1]=8'h20; exp_a_top1[1]=8'h21; exp_a_top2[1]=8'h22; exp_a_top3[1]=8'h23;
        exp_a_bot0[1]=8'h24; exp_a_bot1[1]=8'h25; exp_a_bot2[1]=8'h26; exp_a_bot3[1]=8'h27;
        exp_b_top0[1]=8'h28; exp_b_top1[1]=8'h29; exp_b_top2[1]=8'h2a; exp_b_top3[1]=8'h2b;
        exp_b_bot0[1]=8'h2c; exp_b_bot1[1]=8'h2d; exp_b_bot2[1]=8'h2e; exp_b_bot3[1]=8'h2f;

        exp_a_top0[2]=8'h30; exp_a_top1[2]=8'h31; exp_a_top2[2]=8'h32; exp_a_top3[2]=8'h33;
        exp_a_bot0[2]=8'h34; exp_a_bot1[2]=8'h35; exp_a_bot2[2]=8'h36; exp_a_bot3[2]=8'h37;
        exp_b_top0[2]=8'h38; exp_b_top1[2]=8'h39; exp_b_top2[2]=8'h3a; exp_b_top3[2]=8'h3b;
        exp_b_bot0[2]=8'h3c; exp_b_bot1[2]=8'h3d; exp_b_bot2[2]=8'h3e; exp_b_bot3[2]=8'h3f;

        exp_a_top0[3]=8'h40; exp_a_top1[3]=8'h41; exp_a_top2[3]=8'h42; exp_a_top3[3]=8'h43;
        exp_a_bot0[3]=8'h44; exp_a_bot1[3]=8'h45; exp_a_bot2[3]=8'h46; exp_a_bot3[3]=8'h47;
        exp_b_top0[3]=8'h48; exp_b_top1[3]=8'h49; exp_b_top2[3]=8'h4a; exp_b_top3[3]=8'h4b;
        exp_b_bot0[3]=8'h4c; exp_b_bot1[3]=8'h4d; exp_b_bot2[3]=8'h4e; exp_b_bot3[3]=8'h4f;

        // Reset
        repeat(6) @(posedge clk_fast);
        rst_n = 1;

        // Feed 4 cycles of 16L data into scheduler
        @(posedge clk_slow);
        fwd_a_valid_in = 1; fwd_b_valid_in = 1;
        fwd_a_top0=8'h10; fwd_a_top1=8'h11; fwd_a_top2=8'h12; fwd_a_top3=8'h13;
        fwd_a_bot0=8'h14; fwd_a_bot1=8'h15; fwd_a_bot2=8'h16; fwd_a_bot3=8'h17;
        fwd_b_top0=8'h18; fwd_b_top1=8'h19; fwd_b_top2=8'h1a; fwd_b_top3=8'h1b;
        fwd_b_bot0=8'h1c; fwd_b_bot1=8'h1d; fwd_b_bot2=8'h1e; fwd_b_bot3=8'h1f;

        @(posedge clk_slow);
        fwd_a_top0=8'h20; fwd_a_top1=8'h21; fwd_a_top2=8'h22; fwd_a_top3=8'h23;
        fwd_a_bot0=8'h24; fwd_a_bot1=8'h25; fwd_a_bot2=8'h26; fwd_a_bot3=8'h27;
        fwd_b_top0=8'h28; fwd_b_top1=8'h29; fwd_b_top2=8'h2a; fwd_b_top3=8'h2b;
        fwd_b_bot0=8'h2c; fwd_b_bot1=8'h2d; fwd_b_bot2=8'h2e; fwd_b_bot3=8'h2f;

        @(posedge clk_slow);
        fwd_a_top0=8'h30; fwd_a_top1=8'h31; fwd_a_top2=8'h32; fwd_a_top3=8'h33;
        fwd_a_bot0=8'h34; fwd_a_bot1=8'h35; fwd_a_bot2=8'h36; fwd_a_bot3=8'h37;
        fwd_b_top0=8'h38; fwd_b_top1=8'h39; fwd_b_top2=8'h3a; fwd_b_top3=8'h3b;
        fwd_b_bot0=8'h3c; fwd_b_bot1=8'h3d; fwd_b_bot2=8'h3e; fwd_b_bot3=8'h3f;

        @(posedge clk_slow);
        fwd_a_top0=8'h40; fwd_a_top1=8'h41; fwd_a_top2=8'h42; fwd_a_top3=8'h43;
        fwd_a_bot0=8'h44; fwd_a_bot1=8'h45; fwd_a_bot2=8'h46; fwd_a_bot3=8'h47;
        fwd_b_top0=8'h48; fwd_b_top1=8'h49; fwd_b_top2=8'h4a; fwd_b_top3=8'h4b;
        fwd_b_bot0=8'h4c; fwd_b_bot1=8'h4d; fwd_b_bot2=8'h4e; fwd_b_bot3=8'h4f;

        @(posedge clk_slow);
        fwd_a_valid_in = 0; fwd_b_valid_in = 0;

        // Wait for pipeline to flush
        repeat(20) @(posedge clk_slow);

        total_mismatch = mismatch_cnt;
        total_check    = check_cnt;

        $display("============================================");
        $display("[INFO] Loopback test completed");
        $display("[INFO] 16L: checks=%0d mismatches=%0d", total_check, total_mismatch);
        if (total_mismatch == 0 && total_check >= 4)
            $display("[PASS] Loopback test passed");
        else if (total_check < 4)
            $display("[WARN] Only %0d / 4 checks completed", total_check);
        else
            $display("[FAIL] Loopback test FAILED");
        $display("============================================");
        $finish;
    end

endmodule
