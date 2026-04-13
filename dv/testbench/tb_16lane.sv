// =============================================================================
// Testbench: tb_16lane (Descheduler)
// DUT: inplace_transpose_buf_multi_lane_descheduler (DATA_W=8, lane_mode=16L)
//
// Clock:
//   clk_in  period = 10ns  (100 MHz, fast clock)
//   clk_out period = 40ns  (25 MHz, slow clock = clk_in / 4)
//
// 16L mode: descheduler receives chunk-format serialized data and outputs
// per-lane-per-cycle format (inverse transpose).
//
// Input stimulus (simulating scheduler output after 8lane_2beat):
//   4 slow cycles × 4 phases = 16 fast beats
//   Each slow cycle represents one lane index across all 4 groups:
//     slow0: Lane0[0..3], Lane4[0..3], Lane8[0..3], Lane12[0..3]
//     slow1: Lane1[0..3], Lane5[0..3], Lane9[0..3], Lane13[0..3]
//     slow2: Lane2[0..3], Lane6[0..3], Lane10[0..3], Lane14[0..3]
//     slow3: Lane3[0..3], Lane7[0..3], Lane11[0..3], Lane15[0..3]
//
// Expected output (per-lane-per-cycle):
//   cycle0: a_top={L0[0],L1[0],L2[0],L3[0]} a_bot={L4[0]..} b_top={L8[0]..} b_bot={L12[0]..}
//   cycle1: a_top={L0[1],L1[1],L2[1],L3[1]} ...
//   cycle2: a_top={L0[2],L1[2],L2[2],L3[2]} ...
//   cycle3: a_top={L0[3],L1[3],L2[3],L3[3]} ...
//
// VCD: wave_16lane_desched.vcd
// =============================================================================

`timescale 1ns/1ps

module tb_16lane;

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
        $dumpvars(0, tb_16lane);
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

    // Stimulus: 16 fast beats (4 slow cycles × 4 phases)
    // slow0: Lane0 chunk → a_top, Lane4 chunk → a_bot, Lane8 chunk → b_top, Lane12 chunk → b_bot
    // slow1: Lane1, Lane5, Lane9, Lane13
    // slow2: Lane2, Lane6, Lane10, Lane14
    // slow3: Lane3, Lane7, Lane11, Lane15
    initial begin
        repeat(4) @(posedge clk_in);

        // --- slow cycle 0: Lane0, Lane4, Lane8, Lane12 ---
        @(posedge clk_in); valid_in = 1;
        din0=8'h10; din1=8'h11; din2=8'h12; din3=8'h13;  // a_top: Lane0[0..3]
        @(posedge clk_in);
        din0=8'h14; din1=8'h15; din2=8'h16; din3=8'h17;  // a_bot: Lane4[0..3]
        @(posedge clk_in);
        din0=8'h18; din1=8'h19; din2=8'h1a; din3=8'h1b;  // b_top: Lane8[0..3]
        @(posedge clk_in);
        din0=8'h1c; din1=8'h1d; din2=8'h1e; din3=8'h1f;  // b_bot: Lane12[0..3]

        // --- slow cycle 1: Lane1, Lane5, Lane9, Lane13 ---
        @(posedge clk_in);
        din0=8'h20; din1=8'h21; din2=8'h22; din3=8'h23;
        @(posedge clk_in);
        din0=8'h24; din1=8'h25; din2=8'h26; din3=8'h27;
        @(posedge clk_in);
        din0=8'h28; din1=8'h29; din2=8'h2a; din3=8'h2b;
        @(posedge clk_in);
        din0=8'h2c; din1=8'h2d; din2=8'h2e; din3=8'h2f;

        // --- slow cycle 2: Lane2, Lane6, Lane10, Lane14 ---
        @(posedge clk_in);
        din0=8'h30; din1=8'h31; din2=8'h32; din3=8'h33;
        @(posedge clk_in);
        din0=8'h34; din1=8'h35; din2=8'h36; din3=8'h37;
        @(posedge clk_in);
        din0=8'h38; din1=8'h39; din2=8'h3a; din3=8'h3b;
        @(posedge clk_in);
        din0=8'h3c; din1=8'h3d; din2=8'h3e; din3=8'h3f;

        // --- slow cycle 3: Lane3, Lane7, Lane11, Lane15 ---
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

    // Expected output: per-lane-per-cycle (inverse transpose)
    // a_top = {Lane0[t], Lane1[t], Lane2[t], Lane3[t]}
    // a_bot = {Lane4[t], Lane5[t], Lane6[t], Lane7[t]}
    // b_top = {Lane8[t], Lane9[t], Lane10[t], Lane11[t]}
    // b_bot = {Lane12[t], Lane13[t], Lane14[t], Lane15[t]}
    always @(posedge clk_out) begin
        if (rst_n && valid_out) begin
            $display("[DUT] a_top={%0h,%0h,%0h,%0h} a_bot={%0h,%0h,%0h,%0h} b_top={%0h,%0h,%0h,%0h} b_bot={%0h,%0h,%0h,%0h}",
                a_top0,a_top1,a_top2,a_top3, a_bot0,a_bot1,a_bot2,a_bot3,
                b_top0,b_top1,b_top2,b_top3, b_bot0,b_bot1,b_bot2,b_bot3);
            case (exp_idx)
                //        a_top                    a_bot                    b_top                    b_bot
                0: check16(8'h10,8'h20,8'h30,8'h40, 8'h14,8'h24,8'h34,8'h44, 8'h18,8'h28,8'h38,8'h48, 8'h1c,8'h2c,8'h3c,8'h4c);
                1: check16(8'h11,8'h21,8'h31,8'h41, 8'h15,8'h25,8'h35,8'h45, 8'h19,8'h29,8'h39,8'h49, 8'h1d,8'h2d,8'h3d,8'h4d);
                2: check16(8'h12,8'h22,8'h32,8'h42, 8'h16,8'h26,8'h36,8'h46, 8'h1a,8'h2a,8'h3a,8'h4a, 8'h1e,8'h2e,8'h3e,8'h4e);
                3: check16(8'h13,8'h23,8'h33,8'h43, 8'h17,8'h27,8'h37,8'h47, 8'h1b,8'h2b,8'h3b,8'h4b, 8'h1f,8'h2f,8'h3f,8'h4f);
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
            $display("[PASS] 16L descheduler test passed");
        else if (check_cnt < 4)
            $display("[WARN] Only %0d / 4 golden cycles checked", check_cnt);
        else
            $display("[FAIL] 16L descheduler test FAILED");
        $display("--------------------------------------------");
        $finish;
    end

endmodule
