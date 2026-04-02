// =============================================================================
// Testbench: tb_8lane (Descheduler)
// DUT: inplace_transpose_buf_multi_lane_descheduler (DATA_W=8, lane_mode=8L)
//
// Clock:
//   clk_in  period = 10ns  (fast)
//   clk_out period = 20ns  (slow = clk_in / 2)
//
// 8L forward order: phase0=a_top, phase1=a_bot
// Expected output: a_top and a_bot restored
//
// VCD: wave_8lane_desched.vcd
// =============================================================================

`timescale 1ns/1ps

module tb_8lane;

    localparam DATA_W       = 8;
    localparam CLK_IN_HALF  = 5;
    localparam CLK_OUT_HALF = 10;
    localparam SIM_END      = 500;

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
        $dumpfile("D:/python work/rtl-ddd_reorder/dv/testbench/wave_8lane_desched.vcd");
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

    // Stimulus: 8L serialized (2 phases per cycle)
    // Original: cycle0 a_top={10..13} a_bot={14..17}
    //           cycle1 a_top={20..23} a_bot={24..27}
    //           cycle2 a_top={30..33} a_bot={34..37}
    //           cycle3 a_top={40..43} a_bot={44..47}
    initial begin
        repeat(4) @(posedge clk_in);

        @(posedge clk_in); valid_in = 1;
        din0=8'h10; din1=8'h11; din2=8'h12; din3=8'h13;  // a_top
        @(posedge clk_in);
        din0=8'h14; din1=8'h15; din2=8'h16; din3=8'h17;  // a_bot

        @(posedge clk_in);
        din0=8'h20; din1=8'h21; din2=8'h22; din3=8'h23;
        @(posedge clk_in);
        din0=8'h24; din1=8'h25; din2=8'h26; din3=8'h27;

        @(posedge clk_in);
        din0=8'h30; din1=8'h31; din2=8'h32; din3=8'h33;
        @(posedge clk_in);
        din0=8'h34; din1=8'h35; din2=8'h36; din3=8'h37;

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

    always @(posedge clk_out) begin
        if (rst_n && valid_out) begin
            $display("[DUT] wclk=%0d a_top={%0h,%0h,%0h,%0h} a_bot={%0h,%0h,%0h,%0h}",
                wclk_cnt, a_top0,a_top1,a_top2,a_top3, a_bot0,a_bot1,a_bot2,a_bot3);
            case (exp_idx)
                0: check8(8'h10,8'h11,8'h12,8'h13, 8'h14,8'h15,8'h16,8'h17);
                1: check8(8'h20,8'h21,8'h22,8'h23, 8'h24,8'h25,8'h26,8'h27);
                2: check8(8'h30,8'h31,8'h32,8'h33, 8'h34,8'h35,8'h36,8'h37);
                3: check8(8'h40,8'h41,8'h42,8'h43, 8'h44,8'h45,8'h46,8'h47);
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
