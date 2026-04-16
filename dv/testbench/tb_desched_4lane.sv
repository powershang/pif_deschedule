// =============================================================================
// Testbench: tb_desched_4lane (Descheduler Stage1 — Chunk Format Output)
// DUT: inplace_transpose_buf_multi_lane_descheduler (DATA_W=8, lane_mode=4L)
//
// Clock:
//   clk_in = clk_out = 10ns period (same clock, 4L mode, ratio 1:1)
//
// 4L mode spec (Stage1 chunk output):
//   - Scheduler sends 1 phase per cycle on din[0:3]
//   - Descheduler receives 1 phase, toggles, outputs a_top[0:3] = din[0:3]
//   - a_bot = 0, b_top = 0, b_bot = 0
//   - Each valid_out pulse carries one 4-sample chunk (passthrough)
//
// Input stimulus: 4 beats
//   beat0: din = {10,11,12,13}
//   beat1: din = {14,15,16,17}
//   beat2: din = {20,21,22,23}
//   beat3: din = {24,25,26,27}
//
// Expected output (chunk format, 4 valid_out pulses):
//   out0: a_top = {10,11,12,13}  a_bot = {0,0,0,0}
//   out1: a_top = {14,15,16,17}  a_bot = {0,0,0,0}
//   out2: a_top = {20,21,22,23}  a_bot = {0,0,0,0}
//   out3: a_top = {24,25,26,27}  a_bot = {0,0,0,0}
//
// VCD: wave_4lane_desched.vcd
// =============================================================================

`timescale 1ns/1ps

module tb_desched_4lane;

    localparam DATA_W      = 8;
    localparam CLK_HALF    = 5;   // 10ns period
    localparam SIM_END     = 600;
    localparam NUM_BEATS   = 4;

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
        $dumpvars(0, tb_desched_4lane);
    end

    // ---------- Reset + config ----------
    initial begin
        rst_n     = 0;
        lane_mode = 2'b00;  // 4L
        valid_in  = 0;
        {din0, din1, din2, din3} = '0;
        repeat(4) @(posedge clk);
        rst_n = 1;
    end

    // ---------- Stimulus: 4 beats (chunk data) ----------
    // Record input stimulus into golden arrays for checker
    reg [DATA_W-1:0] stim_din0 [0:NUM_BEATS-1];
    reg [DATA_W-1:0] stim_din1 [0:NUM_BEATS-1];
    reg [DATA_W-1:0] stim_din2 [0:NUM_BEATS-1];
    reg [DATA_W-1:0] stim_din3 [0:NUM_BEATS-1];

    initial begin
        stim_din0[0]=8'h10; stim_din1[0]=8'h11; stim_din2[0]=8'h12; stim_din3[0]=8'h13;
        stim_din0[1]=8'h14; stim_din1[1]=8'h15; stim_din2[1]=8'h16; stim_din3[1]=8'h17;
        stim_din0[2]=8'h20; stim_din1[2]=8'h21; stim_din2[2]=8'h22; stim_din3[2]=8'h23;
        stim_din0[3]=8'h24; stim_din1[3]=8'h25; stim_din2[3]=8'h26; stim_din3[3]=8'h27;
    end

    initial begin
        repeat(4) @(posedge clk);  // wait for reset

        @(posedge clk); valid_in = 1;
        din0=8'h10; din1=8'h11; din2=8'h12; din3=8'h13;  // beat0
        @(posedge clk);
        din0=8'h14; din1=8'h15; din2=8'h16; din3=8'h17;  // beat1
        @(posedge clk);
        din0=8'h20; din1=8'h21; din2=8'h22; din3=8'h23;  // beat2
        @(posedge clk);
        din0=8'h24; din1=8'h25; din2=8'h26; din3=8'h27;  // beat3

        @(posedge clk);
        valid_in = 0;
        {din0, din1, din2, din3} = '0;
    end

    // ---------- Clock counter ----------
    integer clk_cnt;
    initial clk_cnt = 0;
    always @(posedge clk) begin
        if (!rst_n) clk_cnt <= 0;
        else        clk_cnt <= clk_cnt + 1;
    end

    // ---------- Golden checker (chunk format, per-beat) ----------
    integer mismatch_cnt, check_cnt, exp_idx;
    initial begin mismatch_cnt = 0; check_cnt = 0; exp_idx = 0; end

    // 4L chunk spec: each valid_out beat = passthrough of one input phase
    // a_top = din of that phase, a_bot/b_top/b_bot = 0
    always @(posedge clk) begin
        if (rst_n && valid_out) begin
            $display("[DUT] clk=%0d a_top={%02h,%02h,%02h,%02h} a_bot={%02h,%02h,%02h,%02h} b_top={%02h,%02h,%02h,%02h} b_bot={%02h,%02h,%02h,%02h}",
                clk_cnt,
                a_top0, a_top1, a_top2, a_top3,
                a_bot0, a_bot1, a_bot2, a_bot3,
                b_top0, b_top1, b_top2, b_top3,
                b_bot0, b_bot1, b_bot2, b_bot3);

            if (exp_idx < NUM_BEATS) begin
                check_cnt = check_cnt + 1;
                // Check a_top = input din of this phase
                if (a_top0 !== stim_din0[exp_idx]) begin
                    $display("[MISMATCH] beat%0d a_top0=%02h exp=%02h", exp_idx, a_top0, stim_din0[exp_idx]);
                    mismatch_cnt = mismatch_cnt + 1;
                end
                if (a_top1 !== stim_din1[exp_idx]) begin
                    $display("[MISMATCH] beat%0d a_top1=%02h exp=%02h", exp_idx, a_top1, stim_din1[exp_idx]);
                    mismatch_cnt = mismatch_cnt + 1;
                end
                if (a_top2 !== stim_din2[exp_idx]) begin
                    $display("[MISMATCH] beat%0d a_top2=%02h exp=%02h", exp_idx, a_top2, stim_din2[exp_idx]);
                    mismatch_cnt = mismatch_cnt + 1;
                end
                if (a_top3 !== stim_din3[exp_idx]) begin
                    $display("[MISMATCH] beat%0d a_top3=%02h exp=%02h", exp_idx, a_top3, stim_din3[exp_idx]);
                    mismatch_cnt = mismatch_cnt + 1;
                end
                // Check a_bot = 0
                if (a_bot0 !== 8'h00) begin $display("[MISMATCH] beat%0d a_bot0=%02h exp=00", exp_idx, a_bot0); mismatch_cnt = mismatch_cnt + 1; end
                if (a_bot1 !== 8'h00) begin $display("[MISMATCH] beat%0d a_bot1=%02h exp=00", exp_idx, a_bot1); mismatch_cnt = mismatch_cnt + 1; end
                if (a_bot2 !== 8'h00) begin $display("[MISMATCH] beat%0d a_bot2=%02h exp=00", exp_idx, a_bot2); mismatch_cnt = mismatch_cnt + 1; end
                if (a_bot3 !== 8'h00) begin $display("[MISMATCH] beat%0d a_bot3=%02h exp=00", exp_idx, a_bot3); mismatch_cnt = mismatch_cnt + 1; end
                // Check b_top = 0
                if (b_top0 !== 8'h00) begin $display("[MISMATCH] beat%0d b_top0=%02h exp=00", exp_idx, b_top0); mismatch_cnt = mismatch_cnt + 1; end
                if (b_top1 !== 8'h00) begin $display("[MISMATCH] beat%0d b_top1=%02h exp=00", exp_idx, b_top1); mismatch_cnt = mismatch_cnt + 1; end
                if (b_top2 !== 8'h00) begin $display("[MISMATCH] beat%0d b_top2=%02h exp=00", exp_idx, b_top2); mismatch_cnt = mismatch_cnt + 1; end
                if (b_top3 !== 8'h00) begin $display("[MISMATCH] beat%0d b_top3=%02h exp=00", exp_idx, b_top3); mismatch_cnt = mismatch_cnt + 1; end
                // Check b_bot = 0
                if (b_bot0 !== 8'h00) begin $display("[MISMATCH] beat%0d b_bot0=%02h exp=00", exp_idx, b_bot0); mismatch_cnt = mismatch_cnt + 1; end
                if (b_bot1 !== 8'h00) begin $display("[MISMATCH] beat%0d b_bot1=%02h exp=00", exp_idx, b_bot1); mismatch_cnt = mismatch_cnt + 1; end
                if (b_bot2 !== 8'h00) begin $display("[MISMATCH] beat%0d b_bot2=%02h exp=00", exp_idx, b_bot2); mismatch_cnt = mismatch_cnt + 1; end
                if (b_bot3 !== 8'h00) begin $display("[MISMATCH] beat%0d b_bot3=%02h exp=00", exp_idx, b_bot3); mismatch_cnt = mismatch_cnt + 1; end
            end else begin
                $display("[WARN] Unexpected valid_out at exp_idx=%0d (beyond %0d beats)", exp_idx, NUM_BEATS);
            end
            exp_idx = exp_idx + 1;
        end
    end

    // ---------- Final verdict ----------
    initial begin
        #(SIM_END);
        $display("--------------------------------------------");
        $display("[INFO] Total check beats   : %0d", check_cnt);
        $display("[INFO] Total mismatches    : %0d", mismatch_cnt);
        if (mismatch_cnt == 0 && check_cnt >= NUM_BEATS)
            $display("[PASS] 4L descheduler chunk-format test passed");
        else if (check_cnt < NUM_BEATS)
            $display("[FAIL] Only %0d / %0d beats checked — missing valid_out", check_cnt, NUM_BEATS);
        else
            $display("[FAIL] 4L descheduler chunk-format test FAILED");
        $display("--------------------------------------------");
        $finish;
    end

endmodule
