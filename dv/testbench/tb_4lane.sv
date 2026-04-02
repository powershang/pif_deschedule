// =============================================================================
// Testbench: tb_4lane (Descheduler)
// DUT: inplace_transpose_buf_multi_lane_descheduler (DATA_W=8, lane_mode=4L)
//
// Clock:
//   clk_in = clk_out = 10ns period (same clock, 4L mode)
//
// 4L forward order: single phase, din = a_top (direct pass-through)
// Expected output: a_top restored
//
// VCD: wave_4lane_desched.vcd
// =============================================================================

`timescale 1ns/1ps

module tb_4lane;

    localparam DATA_W      = 8;
    localparam CLK_HALF    = 5;   // 10ns period
    localparam SIM_END     = 400;

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
        $dumpfile("D:/python work/rtl-ddd_reorder/dv/testbench/wave_4lane_desched.vcd");
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

    // Stimulus: 4L single-phase pass-through
    initial begin
        repeat(4) @(posedge clk);

        @(posedge clk); valid_in = 1;
        din0=8'h10; din1=8'h11; din2=8'h12; din3=8'h13;
        @(posedge clk);
        din0=8'h20; din1=8'h21; din2=8'h22; din3=8'h23;
        @(posedge clk);
        din0=8'h30; din1=8'h31; din2=8'h32; din3=8'h33;
        @(posedge clk);
        din0=8'h40; din1=8'h41; din2=8'h42; din3=8'h43;

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

    always @(posedge clk) begin
        if (rst_n && valid_out) begin
            $display("[DUT] clk=%0d a_top={%0h,%0h,%0h,%0h}", clk_cnt, a_top0,a_top1,a_top2,a_top3);
            case (exp_idx)
                0: check4(8'h10,8'h11,8'h12,8'h13);
                1: check4(8'h20,8'h21,8'h22,8'h23);
                2: check4(8'h30,8'h31,8'h32,8'h33);
                3: check4(8'h40,8'h41,8'h42,8'h43);
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
