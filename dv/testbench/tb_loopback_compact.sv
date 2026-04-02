// =============================================================================
// Testbench: tb_loopback_compact
// Full chain: Scheduler → Descheduler → Lane Compactor
//
// Tests 16L mode with lane2=lane3=0 in the original input.
// The scheduler serializes, descheduler restores (with zeros in lane2/3),
// and the compactor merges 2 consecutive outputs into 1 full output.
//
// Original input (lane2=lane3=0):
//   cycle 0: a_top={10,11,0,0} a_bot={14,15,0,0} b_top={18,19,0,0} b_bot={1c,1d,0,0}
//   cycle 1: a_top={12,13,0,0} a_bot={16,17,0,0} b_top={1a,1b,0,0} b_bot={1e,1f,0,0}
//   cycle 2: a_top={20,21,0,0} a_bot={24,25,0,0} b_top={28,29,0,0} b_bot={2c,2d,0,0}
//   cycle 3: a_top={22,23,0,0} a_bot={26,27,0,0} b_top={2a,2b,0,0} b_bot={2e,2f,0,0}
//
// Expected compactor output (div2 rate, 2 cycles → 1):
//   div2 cycle 0: a_top={10,11,12,13} a_bot={14,15,16,17} b_top={18,19,1a,1b} b_bot={1c,1d,1e,1f}
//   div2 cycle 1: a_top={20,21,22,23} a_bot={24,25,26,27} b_top={28,29,2a,2b} b_bot={2c,2d,2e,2f}
//
// VCD: wave_loopback_compact.vcd
// =============================================================================

`timescale 1ns/1ps

module tb_loopback_compact;

    localparam DATA_W = 8;
    localparam CLK_FAST_HALF = 5;  // 10ns

    // Clocks
    logic clk_fast, clk_slow;

    // Scheduler (forward) ports
    logic                  rst_n;
    logic [1:0]            lane_mode;
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

    // Compactor output
    logic                  cmp_valid_out;
    logic [DATA_W-1:0]     cmp_a_top0, cmp_a_top1, cmp_a_top2, cmp_a_top3;
    logic [DATA_W-1:0]     cmp_a_bot0, cmp_a_bot1, cmp_a_bot2, cmp_a_bot3;
    logic [DATA_W-1:0]     cmp_b_top0, cmp_b_top1, cmp_b_top2, cmp_b_top3;
    logic [DATA_W-1:0]     cmp_b_bot0, cmp_b_bot1, cmp_b_bot2, cmp_b_bot3;

    // =========================================================================
    // DUT chain: Scheduler → Descheduler → Compactor
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

    lane_compactor #(.DATA_W(DATA_W)) u_cmp (
        .clk(clk_slow), .rst_n(rst_n),
        .valid_in(rev_valid_out),
        .a_top0_in(rev_a_top0), .a_top1_in(rev_a_top1), .a_top2_in(rev_a_top2), .a_top3_in(rev_a_top3),
        .a_bot0_in(rev_a_bot0), .a_bot1_in(rev_a_bot1), .a_bot2_in(rev_a_bot2), .a_bot3_in(rev_a_bot3),
        .b_top0_in(rev_b_top0), .b_top1_in(rev_b_top1), .b_top2_in(rev_b_top2), .b_top3_in(rev_b_top3),
        .b_bot0_in(rev_b_bot0), .b_bot1_in(rev_b_bot1), .b_bot2_in(rev_b_bot2), .b_bot3_in(rev_b_bot3),
        .valid_out(cmp_valid_out),
        .a_top0(cmp_a_top0), .a_top1(cmp_a_top1), .a_top2(cmp_a_top2), .a_top3(cmp_a_top3),
        .a_bot0(cmp_a_bot0), .a_bot1(cmp_a_bot1), .a_bot2(cmp_a_bot2), .a_bot3(cmp_a_bot3),
        .b_top0(cmp_b_top0), .b_top1(cmp_b_top1), .b_top2(cmp_b_top2), .b_top3(cmp_b_top3),
        .b_bot0(cmp_b_bot0), .b_bot1(cmp_b_bot1), .b_bot2(cmp_b_bot2), .b_bot3(cmp_b_bot3)
    );

    // =========================================================================
    // Clocks
    // =========================================================================
    initial clk_fast = 0;
    always #(CLK_FAST_HALF) clk_fast = ~clk_fast;  // 10ns

    // 16L: slow = fast/4 → 40ns period
    integer slow_half;
    initial slow_half = 20;

    initial begin
        clk_slow = 0;
        #(CLK_FAST_HALF);
        forever #(slow_half) clk_slow = ~clk_slow;
    end

    // VCD
    initial begin
        $dumpfile("/mnt/c/python_work/realtek_pc/PIF_schedule_reorder/wave_loopback_compact.vcd");
        $dumpvars(0, tb_loopback_compact);
    end

    // =========================================================================
    // Stimulus: 4 slow clock cycles with lane2=lane3=0
    //
    // cycle 0: a_top={10,11,0,0} a_bot={14,15,0,0} b_top={18,19,0,0} b_bot={1c,1d,0,0}
    // cycle 1: a_top={12,13,0,0} a_bot={16,17,0,0} b_top={1a,1b,0,0} b_bot={1e,1f,0,0}
    // cycle 2: a_top={20,21,0,0} a_bot={24,25,0,0} b_top={28,29,0,0} b_bot={2c,2d,0,0}
    // cycle 3: a_top={22,23,0,0} a_bot={26,27,0,0} b_top={2a,2b,0,0} b_bot={2e,2f,0,0}
    //
    // Expected compactor output (merges cycle 0+1, cycle 2+3):
    //   out 0: a_top={10,11,12,13} a_bot={14,15,16,17} b_top={18,19,1a,1b} b_bot={1c,1d,1e,1f}
    //   out 1: a_top={20,21,22,23} a_bot={24,25,26,27} b_top={28,29,2a,2b} b_bot={2c,2d,2e,2f}
    // =========================================================================
    initial begin
        rst_n          = 0;
        lane_mode      = 2'b11;  // 16L
        fwd_a_valid_in = 0;
        fwd_b_valid_in = 0;
        {fwd_a_top0,fwd_a_top1,fwd_a_top2,fwd_a_top3} = '0;
        {fwd_a_bot0,fwd_a_bot1,fwd_a_bot2,fwd_a_bot3} = '0;
        {fwd_b_top0,fwd_b_top1,fwd_b_top2,fwd_b_top3} = '0;
        {fwd_b_bot0,fwd_b_bot1,fwd_b_bot2,fwd_b_bot3} = '0;

        repeat(6) @(posedge clk_fast);
        rst_n = 1;

        // --- cycle 0 ---
        @(posedge clk_slow);
        fwd_a_valid_in = 1; fwd_b_valid_in = 1;
        fwd_a_top0=8'h10; fwd_a_top1=8'h11; fwd_a_top2=8'h00; fwd_a_top3=8'h00;
        fwd_a_bot0=8'h14; fwd_a_bot1=8'h15; fwd_a_bot2=8'h00; fwd_a_bot3=8'h00;
        fwd_b_top0=8'h18; fwd_b_top1=8'h19; fwd_b_top2=8'h00; fwd_b_top3=8'h00;
        fwd_b_bot0=8'h1c; fwd_b_bot1=8'h1d; fwd_b_bot2=8'h00; fwd_b_bot3=8'h00;

        // --- cycle 1 ---
        @(posedge clk_slow);
        fwd_a_top0=8'h12; fwd_a_top1=8'h13; fwd_a_top2=8'h00; fwd_a_top3=8'h00;
        fwd_a_bot0=8'h16; fwd_a_bot1=8'h17; fwd_a_bot2=8'h00; fwd_a_bot3=8'h00;
        fwd_b_top0=8'h1a; fwd_b_top1=8'h1b; fwd_b_top2=8'h00; fwd_b_top3=8'h00;
        fwd_b_bot0=8'h1e; fwd_b_bot1=8'h1f; fwd_b_bot2=8'h00; fwd_b_bot3=8'h00;

        // --- cycle 2 ---
        @(posedge clk_slow);
        fwd_a_top0=8'h20; fwd_a_top1=8'h21; fwd_a_top2=8'h00; fwd_a_top3=8'h00;
        fwd_a_bot0=8'h24; fwd_a_bot1=8'h25; fwd_a_bot2=8'h00; fwd_a_bot3=8'h00;
        fwd_b_top0=8'h28; fwd_b_top1=8'h29; fwd_b_top2=8'h00; fwd_b_top3=8'h00;
        fwd_b_bot0=8'h2c; fwd_b_bot1=8'h2d; fwd_b_bot2=8'h00; fwd_b_bot3=8'h00;

        // --- cycle 3 ---
        @(posedge clk_slow);
        fwd_a_top0=8'h22; fwd_a_top1=8'h23; fwd_a_top2=8'h00; fwd_a_top3=8'h00;
        fwd_a_bot0=8'h26; fwd_a_bot1=8'h27; fwd_a_bot2=8'h00; fwd_a_bot3=8'h00;
        fwd_b_top0=8'h2a; fwd_b_top1=8'h2b; fwd_b_top2=8'h00; fwd_b_top3=8'h00;
        fwd_b_bot0=8'h2e; fwd_b_bot1=8'h2f; fwd_b_bot2=8'h00; fwd_b_bot3=8'h00;

        @(posedge clk_slow);
        fwd_a_valid_in = 0; fwd_b_valid_in = 0;

        repeat(20) @(posedge clk_slow);

        $display("============================================");
        $display("[INFO] Loopback+Compact test completed");
        $display("[INFO] checks=%0d mismatches=%0d", check_cnt, mismatch_cnt);
        if (mismatch_cnt == 0 && check_cnt >= 2)
            $display("[PASS] Loopback+Compact 16L test passed");
        else if (check_cnt < 2)
            $display("[WARN] Only %0d / 2 checks completed", check_cnt);
        else
            $display("[FAIL] Loopback+Compact 16L test FAILED");
        $display("============================================");
        $finish;
    end

    // =========================================================================
    // Auto-checker: verify compactor output
    // =========================================================================
    integer mismatch_cnt, check_cnt, exp_idx;
    initial begin mismatch_cnt=0; check_cnt=0; exp_idx=0; end

    // Expected compactor outputs
    logic [DATA_W-1:0] e_at0[0:1], e_at1[0:1], e_at2[0:1], e_at3[0:1];
    logic [DATA_W-1:0] e_ab0[0:1], e_ab1[0:1], e_ab2[0:1], e_ab3[0:1];
    logic [DATA_W-1:0] e_bt0[0:1], e_bt1[0:1], e_bt2[0:1], e_bt3[0:1];
    logic [DATA_W-1:0] e_bb0[0:1], e_bb1[0:1], e_bb2[0:1], e_bb3[0:1];

    initial begin
        // div2 output 0: merge of input cycles 0+1
        e_at0[0]=8'h10; e_at1[0]=8'h11; e_at2[0]=8'h12; e_at3[0]=8'h13;
        e_ab0[0]=8'h14; e_ab1[0]=8'h15; e_ab2[0]=8'h16; e_ab3[0]=8'h17;
        e_bt0[0]=8'h18; e_bt1[0]=8'h19; e_bt2[0]=8'h1a; e_bt3[0]=8'h1b;
        e_bb0[0]=8'h1c; e_bb1[0]=8'h1d; e_bb2[0]=8'h1e; e_bb3[0]=8'h1f;
        // div2 output 1: merge of input cycles 2+3
        e_at0[1]=8'h20; e_at1[1]=8'h21; e_at2[1]=8'h22; e_at3[1]=8'h23;
        e_ab0[1]=8'h24; e_ab1[1]=8'h25; e_ab2[1]=8'h26; e_ab3[1]=8'h27;
        e_bt0[1]=8'h28; e_bt1[1]=8'h29; e_bt2[1]=8'h2a; e_bt3[1]=8'h2b;
        e_bb0[1]=8'h2c; e_bb1[1]=8'h2d; e_bb2[1]=8'h2e; e_bb3[1]=8'h2f;
    end

    always @(posedge clk_slow) begin
        if (rst_n && cmp_valid_out && exp_idx < 2) begin
            check_cnt = check_cnt + 1;
            $display("[CMP] #%0d a_top={%0h,%0h,%0h,%0h} a_bot={%0h,%0h,%0h,%0h} b_top={%0h,%0h,%0h,%0h} b_bot={%0h,%0h,%0h,%0h}",
                exp_idx,
                cmp_a_top0,cmp_a_top1,cmp_a_top2,cmp_a_top3,
                cmp_a_bot0,cmp_a_bot1,cmp_a_bot2,cmp_a_bot3,
                cmp_b_top0,cmp_b_top1,cmp_b_top2,cmp_b_top3,
                cmp_b_bot0,cmp_b_bot1,cmp_b_bot2,cmp_b_bot3);

            if (cmp_a_top0!==e_at0[exp_idx]) begin $display("[MISMATCH] a_top0=%0h exp=%0h",cmp_a_top0,e_at0[exp_idx]); mismatch_cnt=mismatch_cnt+1; end
            if (cmp_a_top1!==e_at1[exp_idx]) begin $display("[MISMATCH] a_top1=%0h exp=%0h",cmp_a_top1,e_at1[exp_idx]); mismatch_cnt=mismatch_cnt+1; end
            if (cmp_a_top2!==e_at2[exp_idx]) begin $display("[MISMATCH] a_top2=%0h exp=%0h",cmp_a_top2,e_at2[exp_idx]); mismatch_cnt=mismatch_cnt+1; end
            if (cmp_a_top3!==e_at3[exp_idx]) begin $display("[MISMATCH] a_top3=%0h exp=%0h",cmp_a_top3,e_at3[exp_idx]); mismatch_cnt=mismatch_cnt+1; end
            if (cmp_a_bot0!==e_ab0[exp_idx]) begin $display("[MISMATCH] a_bot0=%0h exp=%0h",cmp_a_bot0,e_ab0[exp_idx]); mismatch_cnt=mismatch_cnt+1; end
            if (cmp_a_bot1!==e_ab1[exp_idx]) begin $display("[MISMATCH] a_bot1=%0h exp=%0h",cmp_a_bot1,e_ab1[exp_idx]); mismatch_cnt=mismatch_cnt+1; end
            if (cmp_a_bot2!==e_ab2[exp_idx]) begin $display("[MISMATCH] a_bot2=%0h exp=%0h",cmp_a_bot2,e_ab2[exp_idx]); mismatch_cnt=mismatch_cnt+1; end
            if (cmp_a_bot3!==e_ab3[exp_idx]) begin $display("[MISMATCH] a_bot3=%0h exp=%0h",cmp_a_bot3,e_ab3[exp_idx]); mismatch_cnt=mismatch_cnt+1; end
            if (cmp_b_top0!==e_bt0[exp_idx]) begin $display("[MISMATCH] b_top0=%0h exp=%0h",cmp_b_top0,e_bt0[exp_idx]); mismatch_cnt=mismatch_cnt+1; end
            if (cmp_b_top1!==e_bt1[exp_idx]) begin $display("[MISMATCH] b_top1=%0h exp=%0h",cmp_b_top1,e_bt1[exp_idx]); mismatch_cnt=mismatch_cnt+1; end
            if (cmp_b_top2!==e_bt2[exp_idx]) begin $display("[MISMATCH] b_top2=%0h exp=%0h",cmp_b_top2,e_bt2[exp_idx]); mismatch_cnt=mismatch_cnt+1; end
            if (cmp_b_top3!==e_bt3[exp_idx]) begin $display("[MISMATCH] b_top3=%0h exp=%0h",cmp_b_top3,e_bt3[exp_idx]); mismatch_cnt=mismatch_cnt+1; end
            if (cmp_b_bot0!==e_bb0[exp_idx]) begin $display("[MISMATCH] b_bot0=%0h exp=%0h",cmp_b_bot0,e_bb0[exp_idx]); mismatch_cnt=mismatch_cnt+1; end
            if (cmp_b_bot1!==e_bb1[exp_idx]) begin $display("[MISMATCH] b_bot1=%0h exp=%0h",cmp_b_bot1,e_bb1[exp_idx]); mismatch_cnt=mismatch_cnt+1; end
            if (cmp_b_bot2!==e_bb2[exp_idx]) begin $display("[MISMATCH] b_bot2=%0h exp=%0h",cmp_b_bot2,e_bb2[exp_idx]); mismatch_cnt=mismatch_cnt+1; end
            if (cmp_b_bot3!==e_bb3[exp_idx]) begin $display("[MISMATCH] b_bot3=%0h exp=%0h",cmp_b_bot3,e_bb3[exp_idx]); mismatch_cnt=mismatch_cnt+1; end

            exp_idx = exp_idx + 1;
        end
    end

    // Monitor descheduler intermediate output
    always @(posedge clk_slow) begin
        if (rst_n && rev_valid_out) begin
            $display("[DESCHED] a_top={%0h,%0h,%0h,%0h} a_bot={%0h,%0h,%0h,%0h}",
                rev_a_top0,rev_a_top1,rev_a_top2,rev_a_top3,
                rev_a_bot0,rev_a_bot1,rev_a_bot2,rev_a_bot3);
        end
    end

endmodule
