// =============================================================================
// Testbench: tb_desched_16lane (Descheduler Stage1)
// DUT: inplace_transpose_buf_multi_lane_descheduler (DATA_W=8, lane_mode=16L)
//
// Clock:
//   clk_in  period = 10ns  (100 MHz, fast clock)
//   clk_out period = 40ns  (25 MHz, slow clock = clk_in / 4)
//
// 16L mode: descheduler receives 4 fast-clock phases per slow cycle.
// No rotation in 16L mode. Stage1 outputs chunk format directly.
//
// Input stimulus (simulating scheduler output):
//   slow0: phase0={10..13}, phase1={14..17}, phase2={18..1b}, phase3={1c..1f}
//   slow1: phase0={20..23}, phase1={24..27}, phase2={28..2b}, phase3={2c..2f}
//   slow2: phase0={30..33}, phase1={34..37}, phase2={38..3b}, phase3={3c..3f}
//   slow3: phase0={40..43}, phase1={44..47}, phase2={48..4b}, phase3={4c..4f}
//
// Direct mapping (no rotation): phase0->a_top, phase1->a_bot, phase2->b_top, phase3->b_bot
//
// Expected chunk-format output per slow cycle:
//   slow0: a_top={10,11,12,13} a_bot={14,15,16,17} b_top={18,19,1a,1b} b_bot={1c,1d,1e,1f}
//   slow1: a_top={20,21,22,23} a_bot={24,25,26,27} b_top={28,29,2a,2b} b_bot={2c,2d,2e,2f}
//   slow2: a_top={30,31,32,33} a_bot={34,35,36,37} b_top={38,39,3a,3b} b_bot={3c,3d,3e,3f}
//   slow3: a_top={40,41,42,43} a_bot={44,45,46,47} b_top={48,49,4a,4b} b_bot={4c,4d,4e,4f}
//
// VCD: wave_16lane_desched.vcd
// =============================================================================

`timescale 1ns/1ps

module tb_desched_16lane;

    localparam DATA_W       = 8;
    localparam CLK_IN_HALF  = 5;    // 10ns period (fast)
    localparam CLK_OUT_HALF = 20;   // 40ns period (slow)
    localparam SIM_END      = 900;

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

    inplace_transpose_buf_multi_lane_descheduler #(.DATA_W(DATA_W)) dut (
        .clk_in(clk_in), .clk_out(clk_out), .rst_n(rst_n),
        .lane_mode(lane_mode), .valid_in(valid_in),
        .din0(din0), .din1(din1), .din2(din2), .din3(din3),
        .valid_out(valid_out),
        .a_top0(a_top0), .a_top1(a_top1), .a_top2(a_top2), .a_top3(a_top3),
        .a_bot0(a_bot0), .a_bot1(a_bot1), .a_bot2(a_bot2), .a_bot3(a_bot3),
        .b_top0(b_top0), .b_top1(b_top1), .b_top2(b_top2), .b_top3(b_top3),
        .b_bot0(b_bot0), .b_bot1(b_bot1), .b_bot2(b_bot2), .b_bot3(b_bot3),
        .dbg_state(dbg_state), .dbg_fifo_cnt(dbg_fifo_cnt)
    );

    // Clock generation
    initial clk_in = 0;
    always #(CLK_IN_HALF) clk_in = ~clk_in;

    initial begin
        clk_out = 0;
        #(CLK_IN_HALF);
        forever #(CLK_OUT_HALF) clk_out = ~clk_out;
    end

    initial begin
        $dumpfile("wave_16lane_desched.vcd");
        $dumpvars(0, tb_desched_16lane);
    end

    // Reset
    initial begin
        rst_n     = 0;
        lane_mode = 2'b11;  // 16L
        valid_in  = 0;
        {din0, din1, din2, din3} = '0;
        repeat(4) @(posedge clk_in);
        rst_n = 1;
    end

    // Stimulus: 16 fast beats (4 slow cycles x 4 phases)
    // No rotation in 16L mode.
    initial begin
        repeat(4) @(posedge clk_in);

        // --- slow cycle 0 ---
        @(posedge clk_in); valid_in = 1;
        din0=8'h10; din1=8'h11; din2=8'h12; din3=8'h13;  // phase0 -> a_top
        @(posedge clk_in);
        din0=8'h14; din1=8'h15; din2=8'h16; din3=8'h17;  // phase1 -> a_bot
        @(posedge clk_in);
        din0=8'h18; din1=8'h19; din2=8'h1a; din3=8'h1b;  // phase2 -> b_top
        @(posedge clk_in);
        din0=8'h1c; din1=8'h1d; din2=8'h1e; din3=8'h1f;  // phase3 -> b_bot

        // --- slow cycle 1 ---
        @(posedge clk_in);
        din0=8'h20; din1=8'h21; din2=8'h22; din3=8'h23;
        @(posedge clk_in);
        din0=8'h24; din1=8'h25; din2=8'h26; din3=8'h27;
        @(posedge clk_in);
        din0=8'h28; din1=8'h29; din2=8'h2a; din3=8'h2b;
        @(posedge clk_in);
        din0=8'h2c; din1=8'h2d; din2=8'h2e; din3=8'h2f;

        // --- slow cycle 2 ---
        @(posedge clk_in);
        din0=8'h30; din1=8'h31; din2=8'h32; din3=8'h33;
        @(posedge clk_in);
        din0=8'h34; din1=8'h35; din2=8'h36; din3=8'h37;
        @(posedge clk_in);
        din0=8'h38; din1=8'h39; din2=8'h3a; din3=8'h3b;
        @(posedge clk_in);
        din0=8'h3c; din1=8'h3d; din2=8'h3e; din3=8'h3f;

        // --- slow cycle 3 ---
        @(posedge clk_in);
        din0=8'h40; din1=8'h41; din2=8'h42; din3=8'h43;
        @(posedge clk_in);
        din0=8'h44; din1=8'h45; din2=8'h46; din3=8'h47;
        @(posedge clk_in);
        din0=8'h48; din1=8'h49; din2=8'h4a; din3=8'h4b;
        @(posedge clk_in);
        din0=8'h4c; din1=8'h4d; din2=8'h4e; din3=8'h4f;

        @(posedge clk_in);
        valid_in = 0;
        {din0, din1, din2, din3} = '0;
    end

    // Auto-checker
    integer mismatch_cnt, check_cnt, exp_idx;
    initial begin mismatch_cnt = 0; check_cnt = 0; exp_idx = 0; end

    task check16(
        input [DATA_W-1:0] e_at0,e_at1,e_at2,e_at3,
        input [DATA_W-1:0] e_ab0,e_ab1,e_ab2,e_ab3,
        input [DATA_W-1:0] e_bt0,e_bt1,e_bt2,e_bt3,
        input [DATA_W-1:0] e_bb0,e_bb1,e_bb2,e_bb3
    );
        check_cnt = check_cnt + 1;
        if (a_top0!==e_at0) begin $display("[MISMATCH] #%0d a_top0=%0h exp=%0h",check_cnt,a_top0,e_at0); mismatch_cnt=mismatch_cnt+1; end
        if (a_top1!==e_at1) begin $display("[MISMATCH] #%0d a_top1=%0h exp=%0h",check_cnt,a_top1,e_at1); mismatch_cnt=mismatch_cnt+1; end
        if (a_top2!==e_at2) begin $display("[MISMATCH] #%0d a_top2=%0h exp=%0h",check_cnt,a_top2,e_at2); mismatch_cnt=mismatch_cnt+1; end
        if (a_top3!==e_at3) begin $display("[MISMATCH] #%0d a_top3=%0h exp=%0h",check_cnt,a_top3,e_at3); mismatch_cnt=mismatch_cnt+1; end
        if (a_bot0!==e_ab0) begin $display("[MISMATCH] #%0d a_bot0=%0h exp=%0h",check_cnt,a_bot0,e_ab0); mismatch_cnt=mismatch_cnt+1; end
        if (a_bot1!==e_ab1) begin $display("[MISMATCH] #%0d a_bot1=%0h exp=%0h",check_cnt,a_bot1,e_ab1); mismatch_cnt=mismatch_cnt+1; end
        if (a_bot2!==e_ab2) begin $display("[MISMATCH] #%0d a_bot2=%0h exp=%0h",check_cnt,a_bot2,e_ab2); mismatch_cnt=mismatch_cnt+1; end
        if (a_bot3!==e_ab3) begin $display("[MISMATCH] #%0d a_bot3=%0h exp=%0h",check_cnt,a_bot3,e_ab3); mismatch_cnt=mismatch_cnt+1; end
        if (b_top0!==e_bt0) begin $display("[MISMATCH] #%0d b_top0=%0h exp=%0h",check_cnt,b_top0,e_bt0); mismatch_cnt=mismatch_cnt+1; end
        if (b_top1!==e_bt1) begin $display("[MISMATCH] #%0d b_top1=%0h exp=%0h",check_cnt,b_top1,e_bt1); mismatch_cnt=mismatch_cnt+1; end
        if (b_top2!==e_bt2) begin $display("[MISMATCH] #%0d b_top2=%0h exp=%0h",check_cnt,b_top2,e_bt2); mismatch_cnt=mismatch_cnt+1; end
        if (b_top3!==e_bt3) begin $display("[MISMATCH] #%0d b_top3=%0h exp=%0h",check_cnt,b_top3,e_bt3); mismatch_cnt=mismatch_cnt+1; end
        if (b_bot0!==e_bb0) begin $display("[MISMATCH] #%0d b_bot0=%0h exp=%0h",check_cnt,b_bot0,e_bb0); mismatch_cnt=mismatch_cnt+1; end
        if (b_bot1!==e_bb1) begin $display("[MISMATCH] #%0d b_bot1=%0h exp=%0h",check_cnt,b_bot1,e_bb1); mismatch_cnt=mismatch_cnt+1; end
        if (b_bot2!==e_bb2) begin $display("[MISMATCH] #%0d b_bot2=%0h exp=%0h",check_cnt,b_bot2,e_bb2); mismatch_cnt=mismatch_cnt+1; end
        if (b_bot3!==e_bb3) begin $display("[MISMATCH] #%0d b_bot3=%0h exp=%0h",check_cnt,b_bot3,e_bb3); mismatch_cnt=mismatch_cnt+1; end
    endtask

    // --- DUT output monitor (always active) ---
    always @(posedge clk_out) begin
        if (rst_n && valid_out) begin
            $display("[DUT] a_top={%0h,%0h,%0h,%0h} a_bot={%0h,%0h,%0h,%0h} b_top={%0h,%0h,%0h,%0h} b_bot={%0h,%0h,%0h,%0h}",
                a_top0,a_top1,a_top2,a_top3, a_bot0,a_bot1,a_bot2,a_bot3,
                b_top0,b_top1,b_top2,b_top3, b_bot0,b_bot1,b_bot2,b_bot3);
        end
    end

    // Golden checker: chunk-format output, direct phase mapping (no rotation)
    always @(posedge clk_out) begin
        if (rst_n && valid_out) begin
            case (exp_idx)
                // slow0: phase0->a_top, phase1->a_bot, phase2->b_top, phase3->b_bot
                0: check16(
                    8'h10, 8'h11, 8'h12, 8'h13,  // a_top
                    8'h14, 8'h15, 8'h16, 8'h17,  // a_bot
                    8'h18, 8'h19, 8'h1a, 8'h1b,  // b_top
                    8'h1c, 8'h1d, 8'h1e, 8'h1f   // b_bot
                );
                // slow1
                1: check16(
                    8'h20, 8'h21, 8'h22, 8'h23,
                    8'h24, 8'h25, 8'h26, 8'h27,
                    8'h28, 8'h29, 8'h2a, 8'h2b,
                    8'h2c, 8'h2d, 8'h2e, 8'h2f
                );
                // slow2
                2: check16(
                    8'h30, 8'h31, 8'h32, 8'h33,
                    8'h34, 8'h35, 8'h36, 8'h37,
                    8'h38, 8'h39, 8'h3a, 8'h3b,
                    8'h3c, 8'h3d, 8'h3e, 8'h3f
                );
                // slow3
                3: check16(
                    8'h40, 8'h41, 8'h42, 8'h43,
                    8'h44, 8'h45, 8'h46, 8'h47,
                    8'h48, 8'h49, 8'h4a, 8'h4b,
                    8'h4c, 8'h4d, 8'h4e, 8'h4f
                );
                default: $display("[WARN] Unexpected valid_out at exp_idx=%0d", exp_idx);
            endcase
            exp_idx = exp_idx + 1;
        end
    end

    integer wclk_cnt;
    initial wclk_cnt = 0;
    always @(posedge clk_out) begin
        if (!rst_n) wclk_cnt <= 0;
        else        wclk_cnt <= wclk_cnt + 1;
    end

    initial begin
        #(SIM_END);
        $display("--------------------------------------------");
        $display("[INFO] Simulation completed at %0t ns", $time);
        $display("[INFO] Total check cycles : %0d", check_cnt);
        $display("[INFO] Total mismatches   : %0d", mismatch_cnt);
        if (mismatch_cnt == 0 && check_cnt >= 4)
            $display("[PASS] 16L descheduler chunk-format test passed");
        else if (check_cnt < 4)
            $display("[WARN] Only %0d / 4 golden cycles checked", check_cnt);
        else
            $display("[FAIL] 16L descheduler chunk-format test FAILED");
        $display("--------------------------------------------");
        $finish;
    end

endmodule
