// =============================================================================
// Testbench: tb_desched_8lane (Descheduler Stage1 — Chunk Format Output)
// DUT: inplace_transpose_buf_multi_lane_descheduler (DATA_W=8, lane_mode=8L)
//
// Clock:
//   clk_in  period = 10ns  (fast)
//   clk_out period = 20ns  (slow = clk_in / 2, ratio 2:1)
//
// 8L mode spec (Stage1 chunk output):
//   - Scheduler sends 2 phases per slow cycle (2 fast beats)
//   - phase0 (fast beat 0) → a_top[0:3]
//   - phase1 (fast beat 1) → a_bot[0:3]
//   - b_top = 0, b_bot = 0
//   - Each valid_out pulse carries two 4-sample chunks
//
// Input stimulus: 8 fast beats (4 slow cycles x 2 phases)
//   F0={10,11,12,13} F1={14,15,16,17}  (slow0)
//   F2={20,21,22,23} F3={24,25,26,27}  (slow1)
//   F4={30,31,32,33} F5={34,35,36,37}  (slow2)
//   F6={40,41,42,43} F7={44,45,46,47}  (slow3)
//
// Expected output (chunk format, 4 valid_out pulses on clk_out):
//   out0: a_top={10,11,12,13} a_bot={14,15,16,17} b_top=0 b_bot=0
//   out1: a_top={20,21,22,23} a_bot={24,25,26,27} b_top=0 b_bot=0
//   out2: a_top={30,31,32,33} a_bot={34,35,36,37} b_top=0 b_bot=0
//   out3: a_top={40,41,42,43} a_bot={44,45,46,47} b_top=0 b_bot=0
//
// VCD: wave_8lane_desched.vcd
// =============================================================================

`timescale 1ns/1ps

module tb_desched_8lane;

    localparam DATA_W       = 8;
    localparam CLK_IN_HALF  = 5;
    localparam CLK_OUT_HALF = 10;
    localparam SIM_END      = 800;
    localparam NUM_OUT      = 4;   // 4 slow-cycle outputs

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

    initial clk_in = 0;
    always #(CLK_IN_HALF) clk_in = ~clk_in;

    initial begin
        clk_out = 0;
        #(CLK_IN_HALF);
        forever #(CLK_OUT_HALF) clk_out = ~clk_out;
    end

    initial begin
        $dumpfile("wave_8lane_desched.vcd");
        $dumpvars(0, tb_desched_8lane);
    end

    // ---------- Reset + config ----------
    initial begin
        rst_n     = 0;
        lane_mode = 2'b01;  // 8L
        valid_in  = 0;
        {din0, din1, din2, din3} = '0;
        repeat(4) @(posedge clk_in);
        rst_n = 1;
    end

    // ---------- Golden arrays (from spec, not RTL) ----------
    // 8L: every 2 fast beats → 1 output. phase0 → a_top, phase1 → a_bot
    reg [DATA_W-1:0] exp_at0 [0:NUM_OUT-1];
    reg [DATA_W-1:0] exp_at1 [0:NUM_OUT-1];
    reg [DATA_W-1:0] exp_at2 [0:NUM_OUT-1];
    reg [DATA_W-1:0] exp_at3 [0:NUM_OUT-1];
    reg [DATA_W-1:0] exp_ab0 [0:NUM_OUT-1];
    reg [DATA_W-1:0] exp_ab1 [0:NUM_OUT-1];
    reg [DATA_W-1:0] exp_ab2 [0:NUM_OUT-1];
    reg [DATA_W-1:0] exp_ab3 [0:NUM_OUT-1];

    initial begin
        // out0: phase0={10,11,12,13} phase1={14,15,16,17}
        exp_at0[0]=8'h10; exp_at1[0]=8'h11; exp_at2[0]=8'h12; exp_at3[0]=8'h13;
        exp_ab0[0]=8'h14; exp_ab1[0]=8'h15; exp_ab2[0]=8'h16; exp_ab3[0]=8'h17;
        // out1: phase0={20,21,22,23} phase1={24,25,26,27}
        exp_at0[1]=8'h20; exp_at1[1]=8'h21; exp_at2[1]=8'h22; exp_at3[1]=8'h23;
        exp_ab0[1]=8'h24; exp_ab1[1]=8'h25; exp_ab2[1]=8'h26; exp_ab3[1]=8'h27;
        // out2: phase0={30,31,32,33} phase1={34,35,36,37}
        exp_at0[2]=8'h30; exp_at1[2]=8'h31; exp_at2[2]=8'h32; exp_at3[2]=8'h33;
        exp_ab0[2]=8'h34; exp_ab1[2]=8'h35; exp_ab2[2]=8'h36; exp_ab3[2]=8'h37;
        // out3: phase0={40,41,42,43} phase1={44,45,46,47}
        exp_at0[3]=8'h40; exp_at1[3]=8'h41; exp_at2[3]=8'h42; exp_at3[3]=8'h43;
        exp_ab0[3]=8'h44; exp_ab1[3]=8'h45; exp_ab2[3]=8'h46; exp_ab3[3]=8'h47;
    end

    // ---------- Stimulus: 8 fast beats ----------
    initial begin
        repeat(4) @(posedge clk_in);  // wait for reset

        // slow cycle 0: phase0 + phase1
        @(posedge clk_in); valid_in = 1;
        din0=8'h10; din1=8'h11; din2=8'h12; din3=8'h13;  // F0 (phase0)
        @(posedge clk_in);
        din0=8'h14; din1=8'h15; din2=8'h16; din3=8'h17;  // F1 (phase1)

        // slow cycle 1
        @(posedge clk_in);
        din0=8'h20; din1=8'h21; din2=8'h22; din3=8'h23;  // F2
        @(posedge clk_in);
        din0=8'h24; din1=8'h25; din2=8'h26; din3=8'h27;  // F3

        // slow cycle 2
        @(posedge clk_in);
        din0=8'h30; din1=8'h31; din2=8'h32; din3=8'h33;  // F4
        @(posedge clk_in);
        din0=8'h34; din1=8'h35; din2=8'h36; din3=8'h37;  // F5

        // slow cycle 3
        @(posedge clk_in);
        din0=8'h40; din1=8'h41; din2=8'h42; din3=8'h43;  // F6
        @(posedge clk_in);
        din0=8'h44; din1=8'h45; din2=8'h46; din3=8'h47;  // F7

        @(posedge clk_in);
        valid_in = 0;
        {din0, din1, din2, din3} = '0;
    end

    // ---------- Clock counter ----------
    integer wclk_cnt;
    initial wclk_cnt = 0;
    always @(posedge clk_out) begin
        if (!rst_n) wclk_cnt <= 0;
        else        wclk_cnt <= wclk_cnt + 1;
    end

    // ---------- Golden checker (chunk format, per-beat on clk_out) ----------
    integer mismatch_cnt, check_cnt, exp_idx;
    initial begin mismatch_cnt = 0; check_cnt = 0; exp_idx = 0; end

    always @(posedge clk_out) begin
        if (rst_n && valid_out) begin
            $display("[DUT] wclk=%0d a_top={%02h,%02h,%02h,%02h} a_bot={%02h,%02h,%02h,%02h} b_top={%02h,%02h,%02h,%02h} b_bot={%02h,%02h,%02h,%02h}",
                wclk_cnt,
                a_top0, a_top1, a_top2, a_top3,
                a_bot0, a_bot1, a_bot2, a_bot3,
                b_top0, b_top1, b_top2, b_top3,
                b_bot0, b_bot1, b_bot2, b_bot3);

            if (exp_idx < NUM_OUT) begin
                check_cnt = check_cnt + 1;
                // Check a_top = phase0 data
                if (a_top0 !== exp_at0[exp_idx]) begin $display("[MISMATCH] beat%0d a_top0=%02h exp=%02h", exp_idx, a_top0, exp_at0[exp_idx]); mismatch_cnt = mismatch_cnt + 1; end
                if (a_top1 !== exp_at1[exp_idx]) begin $display("[MISMATCH] beat%0d a_top1=%02h exp=%02h", exp_idx, a_top1, exp_at1[exp_idx]); mismatch_cnt = mismatch_cnt + 1; end
                if (a_top2 !== exp_at2[exp_idx]) begin $display("[MISMATCH] beat%0d a_top2=%02h exp=%02h", exp_idx, a_top2, exp_at2[exp_idx]); mismatch_cnt = mismatch_cnt + 1; end
                if (a_top3 !== exp_at3[exp_idx]) begin $display("[MISMATCH] beat%0d a_top3=%02h exp=%02h", exp_idx, a_top3, exp_at3[exp_idx]); mismatch_cnt = mismatch_cnt + 1; end
                // Check a_bot = phase1 data
                if (a_bot0 !== exp_ab0[exp_idx]) begin $display("[MISMATCH] beat%0d a_bot0=%02h exp=%02h", exp_idx, a_bot0, exp_ab0[exp_idx]); mismatch_cnt = mismatch_cnt + 1; end
                if (a_bot1 !== exp_ab1[exp_idx]) begin $display("[MISMATCH] beat%0d a_bot1=%02h exp=%02h", exp_idx, a_bot1, exp_ab1[exp_idx]); mismatch_cnt = mismatch_cnt + 1; end
                if (a_bot2 !== exp_ab2[exp_idx]) begin $display("[MISMATCH] beat%0d a_bot2=%02h exp=%02h", exp_idx, a_bot2, exp_ab2[exp_idx]); mismatch_cnt = mismatch_cnt + 1; end
                if (a_bot3 !== exp_ab3[exp_idx]) begin $display("[MISMATCH] beat%0d a_bot3=%02h exp=%02h", exp_idx, a_bot3, exp_ab3[exp_idx]); mismatch_cnt = mismatch_cnt + 1; end
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
                $display("[WARN] Unexpected valid_out at exp_idx=%0d (beyond %0d outputs)", exp_idx, NUM_OUT);
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
        if (mismatch_cnt == 0 && check_cnt >= NUM_OUT)
            $display("[PASS] 8L descheduler chunk-format test passed");
        else if (check_cnt < NUM_OUT)
            $display("[FAIL] Only %0d / %0d beats checked — missing valid_out", check_cnt, NUM_OUT);
        else
            $display("[FAIL] 8L descheduler chunk-format test FAILED");
        $display("--------------------------------------------");
        $finish;
    end

endmodule
