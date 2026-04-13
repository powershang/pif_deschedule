// =============================================================================
// Testbench: tb_4lane (Descheduler)
// DUT: inplace_transpose_buf_multi_lane_descheduler (DATA_W=8, lane_mode=4L)
//
// Clock:
//   clk_in = clk_out = 10ns period (same clock, 4L mode)
//
// 4L mode: descheduler receives chunk-format serialized data and outputs
// per-lane-per-cycle format (inverse transpose).
//
// Input stimulus (simulating scheduler output after chunk accumulation):
//   Represents 2 lanes (Lane0, Lane1) with lane2/lane3=0.
//   4 beats from 8lane_2beat LANE4 PHY mode:
//     beat0: Lane0 sample[0..3] = {10,11,12,13}
//     beat1: Lane0 sample[4..7] = {14,15,16,17}
//     beat2: Lane1 sample[0..3] = {20,21,22,23}
//     beat3: Lane1 sample[4..7] = {24,25,26,27}
//
// Expected output (per-lane-per-cycle, inverse transpose):
//   cycle0: a_top = {Lane0[0], Lane1[0], 0, 0} = {10, 20, 0, 0}
//   cycle1: a_top = {Lane0[1], Lane1[1], 0, 0} = {11, 21, 0, 0}
//   cycle2: a_top = {Lane0[2], Lane1[2], 0, 0} = {12, 22, 0, 0}
//   cycle3: a_top = {Lane0[3], Lane1[3], 0, 0} = {13, 23, 0, 0}
//   cycle4: a_top = {Lane0[4], Lane1[4], 0, 0} = {14, 24, 0, 0}
//   cycle5: a_top = {Lane0[5], Lane1[5], 0, 0} = {15, 25, 0, 0}
//   cycle6: a_top = {Lane0[6], Lane1[6], 0, 0} = {16, 26, 0, 0}
//   cycle7: a_top = {Lane0[7], Lane1[7], 0, 0} = {17, 27, 0, 0}
//
// VCD: wave_4lane_desched.vcd
// =============================================================================

`timescale 1ns/1ps

module tb_4lane;

    localparam DATA_W      = 8;
    localparam CLK_HALF    = 5;   // 10ns period
    localparam SIM_END     = 600;

    logic                  clk, rst_n;
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

    // 4L: clk_in = clk_out (same clock)
    inplace_transpose_buf_multi_lane_descheduler #(.DATA_W(DATA_W)) dut (
        .clk_in(clk), .clk_out(clk), .rst_n(rst_n),
        .lane_mode(lane_mode), .valid_in(valid_in),
        .din0(din0), .din1(din1), .din2(din2), .din3(din3),
        .valid_out(valid_out),
        .a_top0(a_top0), .a_top1(a_top1), .a_top2(a_top2), .a_top3(a_top3),
        .a_bot0(a_bot0), .a_bot1(a_bot1), .a_bot2(a_bot2), .a_bot3(a_bot3),
        .b_top0(b_top0), .b_top1(b_top1), .b_top2(b_top2), .b_top3(b_top3),
        .b_bot0(b_bot0), .b_bot1(b_bot1), .b_bot2(b_bot2), .b_bot3(b_bot3),
        .dbg_state(dbg_state), .dbg_fifo_cnt(dbg_fifo_cnt)
    );

    initial clk = 0;
    always #(CLK_HALF) clk = ~clk;

    initial begin
        $dumpfile("wave_4lane_desched.vcd");
        $dumpvars(0, tb_4lane);
    end

    initial begin
        rst_n     = 0;
        lane_mode = 2'b00;  // 4L
        valid_in  = 0;
        {din0, din1, din2, din3} = '0;
        repeat(4) @(posedge clk);
        rst_n = 1;
    end

    // Stimulus: 4 beats representing 2 lanes × 8 samples (LANE4 PHY chunk)
    // Lane0 = {10,11,12,13,14,15,16,17}, Lane1 = {20,21,22,23,24,25,26,27}
    initial begin
        repeat(4) @(posedge clk);

        // beat0: Lane0 sample[0..3]
        @(posedge clk); valid_in = 1;
        din0=8'h10; din1=8'h11; din2=8'h12; din3=8'h13;
        // beat1: Lane0 sample[4..7]
        @(posedge clk);
        din0=8'h14; din1=8'h15; din2=8'h16; din3=8'h17;
        // beat2: Lane1 sample[0..3]
        @(posedge clk);
        din0=8'h20; din1=8'h21; din2=8'h22; din3=8'h23;
        // beat3: Lane1 sample[4..7]
        @(posedge clk);
        din0=8'h24; din1=8'h25; din2=8'h26; din3=8'h27;

        @(posedge clk);
        valid_in = 0;
        {din0, din1, din2, din3} = '0;
    end

    integer mismatch_cnt, check_cnt, exp_idx;
    initial begin mismatch_cnt=0; check_cnt=0; exp_idx=0; end

    integer clk_cnt;
    initial clk_cnt = 0;
    always @(posedge clk) begin
        if (!rst_n) clk_cnt <= 0;
        else        clk_cnt <= clk_cnt + 1;
    end

    task check4(input [DATA_W-1:0] e0, e1, e2, e3);
        check_cnt = check_cnt + 1;
        if (a_top0!==e0) begin $display("[MISMATCH] #%0d a_top0=%0h exp=%0h",check_cnt,a_top0,e0); mismatch_cnt=mismatch_cnt+1; end
        if (a_top1!==e1) begin $display("[MISMATCH] #%0d a_top1=%0h exp=%0h",check_cnt,a_top1,e1); mismatch_cnt=mismatch_cnt+1; end
        if (a_top2!==e2) begin $display("[MISMATCH] #%0d a_top2=%0h exp=%0h",check_cnt,a_top2,e2); mismatch_cnt=mismatch_cnt+1; end
        if (a_top3!==e3) begin $display("[MISMATCH] #%0d a_top3=%0h exp=%0h",check_cnt,a_top3,e3); mismatch_cnt=mismatch_cnt+1; end
    endtask

    // Expected output: per-lane-per-cycle (inverse transpose)
    // 4 toggles accumulated: beat0=Lane0_top, beat1=Lane0_bot, beat2=Lane1_top, beat3=Lane1_bot
    // acc[0]={10,11,12,13}  acc[1]={14,15,16,17}  acc[2]={20,21,22,23}  acc[3]={24,25,26,27}
    // Transpose cycle t: a_top = {acc[0][t], acc[1][t], acc[2][t], acc[3][t]}
    always @(posedge clk) begin
        if (rst_n && valid_out) begin
            $display("[DUT] clk=%0d a_top={%0h,%0h,%0h,%0h}", clk_cnt, a_top0,a_top1,a_top2,a_top3);
            case (exp_idx)
                0: check4(8'h10, 8'h14, 8'h20, 8'h24);  // L0[0], L0[4], L1[0], L1[4]
                1: check4(8'h11, 8'h15, 8'h21, 8'h25);  // L0[1], L0[5], L1[1], L1[5]
                2: check4(8'h12, 8'h16, 8'h22, 8'h26);  // L0[2], L0[6], L1[2], L1[6]
                3: check4(8'h13, 8'h17, 8'h23, 8'h27);  // L0[3], L0[7], L1[3], L1[7]
                default: $display("[WARN] Unexpected valid_out at exp_idx=%0d", exp_idx);
            endcase
            exp_idx = exp_idx + 1;
        end
    end

    initial begin
        #(SIM_END);
        $display("--------------------------------------------");
        $display("[INFO] Total check cycles : %0d", check_cnt);
        $display("[INFO] Total mismatches   : %0d", mismatch_cnt);
        if (mismatch_cnt == 0 && check_cnt >= 4)
            $display("[PASS] 4L descheduler test passed");
        else if (check_cnt < 4)
            $display("[WARN] Only %0d / 4 checked", check_cnt);
        else
            $display("[FAIL] 4L descheduler test FAILED");
        $display("--------------------------------------------");
        $finish;
    end

endmodule
