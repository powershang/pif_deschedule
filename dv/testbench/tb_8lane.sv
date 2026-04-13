// =============================================================================
// Testbench: tb_8lane (Descheduler)
// DUT: inplace_transpose_buf_multi_lane_descheduler (DATA_W=8, lane_mode=8L)
//
// Clock:
//   clk_in  period = 10ns  (fast)
//   clk_out period = 20ns  (slow = clk_in / 2)
//
// 8L mode: descheduler receives chunk-format serialized data and outputs
// per-lane-per-cycle format (inverse transpose).
//
// Input stimulus (simulating scheduler output after 8lane_2beat LANE8 PHY):
//   8 lanes, each with 4 samples (half chunk, top only for simplicity).
//   Each slow cycle = 1 lane's top chunk:
//     slow0: a_top={10,11,12,13} a_bot={14,15,16,17}  Lane0
//     slow1: a_top={20,21,22,23} a_bot={24,25,26,27}  Lane1
//     slow2: a_top={30,31,32,33} a_bot={34,35,36,37}  Lane2
//     slow3: a_top={40,41,42,43} a_bot={44,45,46,47}  Lane3
//     (a_top = Lane_i top 4 samples, a_bot = Lane_(i+4) top 4 samples)
//
// The serialized fast beats:
//     F0={10,11,12,13} F1={14,15,16,17}  (slow0 phase0=a_top, phase1=a_bot)
//     F2={20,21,22,23} F3={24,25,26,27}  (slow1)
//     F4={30,31,32,33} F5={34,35,36,37}  (slow2)
//     F6={40,41,42,43} F7={44,45,46,47}  (slow3)
//
// Expected output (per-lane-per-cycle, inverse transpose):
//   Each output cycle has 8 lanes: a_top0..3 = Lane0..3, a_bot0..3 = Lane4..7
//   cycle0: a_top={10,20,30,40} a_bot={14,24,34,44}
//   cycle1: a_top={11,21,31,41} a_bot={15,25,35,45}
//   cycle2: a_top={12,22,32,42} a_bot={16,26,36,46}
//   cycle3: a_top={13,23,33,43} a_bot={17,27,37,47}
//
// VCD: wave_8lane_desched.vcd
// =============================================================================

`timescale 1ns/1ps

module tb_8lane;

    localparam DATA_W       = 8;
    localparam CLK_IN_HALF  = 5;
    localparam CLK_OUT_HALF = 10;
    localparam SIM_END      = 800;

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
        $dumpvars(0, tb_8lane);
    end

    initial begin
        rst_n     = 0;
        lane_mode = 2'b01;  // 8L
        valid_in  = 0;
        {din0, din1, din2, din3} = '0;
        repeat(4) @(posedge clk_in);
        rst_n = 1;
    end

    // Stimulus: 8 fast beats (4 slow cycles × 2 phases)
    // Representing 4 lanes in a_top + 4 lanes in a_bot, each with 4 samples
    initial begin
        repeat(4) @(posedge clk_in);

        // slow cycle 0: Lane0 (a_top) + Lane4 (a_bot)
        @(posedge clk_in); valid_in = 1;
        din0=8'h10; din1=8'h11; din2=8'h12; din3=8'h13;  // a_top: Lane0[0..3]
        @(posedge clk_in);
        din0=8'h14; din1=8'h15; din2=8'h16; din3=8'h17;  // a_bot: Lane4[0..3]

        // slow cycle 1: Lane1 (a_top) + Lane5 (a_bot)
        @(posedge clk_in);
        din0=8'h20; din1=8'h21; din2=8'h22; din3=8'h23;
        @(posedge clk_in);
        din0=8'h24; din1=8'h25; din2=8'h26; din3=8'h27;

        // slow cycle 2: Lane2 (a_top) + Lane6 (a_bot)
        @(posedge clk_in);
        din0=8'h30; din1=8'h31; din2=8'h32; din3=8'h33;
        @(posedge clk_in);
        din0=8'h34; din1=8'h35; din2=8'h36; din3=8'h37;

        // slow cycle 3: Lane3 (a_top) + Lane7 (a_bot)
        @(posedge clk_in);
        din0=8'h40; din1=8'h41; din2=8'h42; din3=8'h43;
        @(posedge clk_in);
        din0=8'h44; din1=8'h45; din2=8'h46; din3=8'h47;

        @(posedge clk_in);
        valid_in = 0;
        {din0, din1, din2, din3} = '0;
    end

    integer mismatch_cnt, check_cnt, exp_idx;
    initial begin mismatch_cnt=0; check_cnt=0; exp_idx=0; end

    integer wclk_cnt;
    initial wclk_cnt = 0;
    always @(posedge clk_out) begin
        if (!rst_n) wclk_cnt <= 0;
        else        wclk_cnt <= wclk_cnt + 1;
    end

    task check8(
        input [DATA_W-1:0] e_at0,e_at1,e_at2,e_at3,
        input [DATA_W-1:0] e_ab0,e_ab1,e_ab2,e_ab3
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
    endtask

    // Expected output: per-lane-per-cycle (inverse transpose)
    // a_top = {Lane0[t], Lane1[t], Lane2[t], Lane3[t]}
    // a_bot = {Lane4[t], Lane5[t], Lane6[t], Lane7[t]}
    always @(posedge clk_out) begin
        if (rst_n && valid_out) begin
            $display("[DUT] wclk=%0d a_top={%0h,%0h,%0h,%0h} a_bot={%0h,%0h,%0h,%0h}",
                wclk_cnt, a_top0,a_top1,a_top2,a_top3, a_bot0,a_bot1,a_bot2,a_bot3);
            case (exp_idx)
                0: check8(8'h10,8'h20,8'h30,8'h40, 8'h14,8'h24,8'h34,8'h44);
                1: check8(8'h11,8'h21,8'h31,8'h41, 8'h15,8'h25,8'h35,8'h45);
                2: check8(8'h12,8'h22,8'h32,8'h42, 8'h16,8'h26,8'h36,8'h46);
                3: check8(8'h13,8'h23,8'h33,8'h43, 8'h17,8'h27,8'h37,8'h47);
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
            $display("[PASS] 8L descheduler test passed");
        else if (check_cnt < 4)
            $display("[WARN] Only %0d / 4 checked", check_cnt);
        else
            $display("[FAIL] 8L descheduler test FAILED");
        $display("--------------------------------------------");
        $finish;
    end

endmodule
