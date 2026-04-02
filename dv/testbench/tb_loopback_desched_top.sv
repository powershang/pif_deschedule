// =============================================================================
// Testbench: tb_loopback_desched_top
// DUT chain: Scheduler → Descheduler_Top (desched + compactor)
//
// Test matrix: 4 lane modes × 2 data patterns (PHY-like / VLANE-like) = 8 cases
// Each case: 20 input pairs (40 slow cycles) → 20 compact outputs
//
// PHY pattern:  lane values are independent sequential per group
// VLANE pattern: lane values are even/odd interleaved per group
// =============================================================================

`timescale 1ns/1ps

module tb_loopback_desched_top;

    localparam DATA_W = 8;
    localparam CLK_FAST_HALF = 5;
    localparam NUM_PAIRS = 20;

    // =========================================================================
    // Signals
    // =========================================================================
    logic clk_fast, clk_slow;
    logic                  rst_n;
    logic [1:0]            lane_mode;
    integer                slow_half;

    logic                  fwd_a_valid_in, fwd_b_valid_in;
    logic [DATA_W-1:0]     fwd_a_top0, fwd_a_top1, fwd_a_top2, fwd_a_top3;
    logic [DATA_W-1:0]     fwd_a_bot0, fwd_a_bot1, fwd_a_bot2, fwd_a_bot3;
    logic [DATA_W-1:0]     fwd_b_top0, fwd_b_top1, fwd_b_top2, fwd_b_top3;
    logic [DATA_W-1:0]     fwd_b_bot0, fwd_b_bot1, fwd_b_bot2, fwd_b_bot3;
    logic                  fwd_valid_out;
    logic [DATA_W-1:0]     fwd_dout0, fwd_dout1, fwd_dout2, fwd_dout3;
    logic [2:0]            fwd_dbg_state;
    logic [3:0]            fwd_dbg_fifo_cnt;

    logic                  cmp_valid_out;
    logic [DATA_W-1:0]     cmp_a_top0, cmp_a_top1, cmp_a_top2, cmp_a_top3;
    logic [DATA_W-1:0]     cmp_a_bot0, cmp_a_bot1, cmp_a_bot2, cmp_a_bot3;
    logic [DATA_W-1:0]     cmp_b_top0, cmp_b_top1, cmp_b_top2, cmp_b_top3;
    logic [DATA_W-1:0]     cmp_b_bot0, cmp_b_bot1, cmp_b_bot2, cmp_b_bot3;
    logic [2:0]            rev_dbg_state;
    logic [3:0]            rev_dbg_fifo_cnt;

    // =========================================================================
    // DUT chain
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

    inplace_transpose_buf_multi_lane_descheduler_top #(.DATA_W(DATA_W)) u_dut (
        .clk_in(clk_fast), .clk_out(clk_slow), .rst_n(rst_n),
        .lane_mode(lane_mode),
        .valid_in(fwd_valid_out),
        .din0(fwd_dout0), .din1(fwd_dout1), .din2(fwd_dout2), .din3(fwd_dout3),
        .valid_out(cmp_valid_out),
        .a_top0(cmp_a_top0), .a_top1(cmp_a_top1), .a_top2(cmp_a_top2), .a_top3(cmp_a_top3),
        .a_bot0(cmp_a_bot0), .a_bot1(cmp_a_bot1), .a_bot2(cmp_a_bot2), .a_bot3(cmp_a_bot3),
        .b_top0(cmp_b_top0), .b_top1(cmp_b_top1), .b_top2(cmp_b_top2), .b_top3(cmp_b_top3),
        .b_bot0(cmp_b_bot0), .b_bot1(cmp_b_bot1), .b_bot2(cmp_b_bot2), .b_bot3(cmp_b_bot3),
        .dbg_state(rev_dbg_state), .dbg_fifo_cnt(rev_dbg_fifo_cnt)
    );

    // =========================================================================
    // Clocks
    // =========================================================================
    initial clk_fast = 0;
    always #(CLK_FAST_HALF) clk_fast = ~clk_fast;

    initial begin
        clk_slow = 0;
        slow_half = CLK_FAST_HALF;
        #(CLK_FAST_HALF);
        forever #(slow_half) clk_slow = ~clk_slow;
    end

    initial begin
        $dumpfile("/mnt/c/python_work/realtek_pc/PIF_schedule_reorder/wave_loopback_desched_top.vcd");
        $dumpvars(0, tb_loopback_desched_top);
    end

    // =========================================================================
    // Expected storage + checker
    // =========================================================================
    localparam MAX_EXP = 64;
    reg [DATA_W-1:0] e_at0[0:MAX_EXP-1], e_at1[0:MAX_EXP-1], e_at2[0:MAX_EXP-1], e_at3[0:MAX_EXP-1];
    reg [DATA_W-1:0] e_ab0[0:MAX_EXP-1], e_ab1[0:MAX_EXP-1], e_ab2[0:MAX_EXP-1], e_ab3[0:MAX_EXP-1];
    reg [DATA_W-1:0] e_bt0[0:MAX_EXP-1], e_bt1[0:MAX_EXP-1], e_bt2[0:MAX_EXP-1], e_bt3[0:MAX_EXP-1];
    reg [DATA_W-1:0] e_bb0[0:MAX_EXP-1], e_bb1[0:MAX_EXP-1], e_bb2[0:MAX_EXP-1], e_bb3[0:MAX_EXP-1];

    integer mismatch_cnt, check_cnt, exp_idx, exp_total;
    integer checking_en, is_drain_mode;

    always @(posedge clk_slow) begin
        if (rst_n && checking_en && cmp_valid_out) begin
            if (!is_drain_mode && exp_idx < exp_total) begin
                if (cmp_a_top0!==e_at0[exp_idx]) begin $display("  [MISMATCH] #%0d a_top0 got=%0h exp=%0h",exp_idx,cmp_a_top0,e_at0[exp_idx]); mismatch_cnt=mismatch_cnt+1; end
                if (cmp_a_top1!==e_at1[exp_idx]) begin $display("  [MISMATCH] #%0d a_top1 got=%0h exp=%0h",exp_idx,cmp_a_top1,e_at1[exp_idx]); mismatch_cnt=mismatch_cnt+1; end
                if (cmp_a_top2!==e_at2[exp_idx]) begin $display("  [MISMATCH] #%0d a_top2 got=%0h exp=%0h",exp_idx,cmp_a_top2,e_at2[exp_idx]); mismatch_cnt=mismatch_cnt+1; end
                if (cmp_a_top3!==e_at3[exp_idx]) begin $display("  [MISMATCH] #%0d a_top3 got=%0h exp=%0h",exp_idx,cmp_a_top3,e_at3[exp_idx]); mismatch_cnt=mismatch_cnt+1; end
                if (cmp_a_bot0!==e_ab0[exp_idx]) begin $display("  [MISMATCH] #%0d a_bot0 got=%0h exp=%0h",exp_idx,cmp_a_bot0,e_ab0[exp_idx]); mismatch_cnt=mismatch_cnt+1; end
                if (cmp_a_bot1!==e_ab1[exp_idx]) begin $display("  [MISMATCH] #%0d a_bot1 got=%0h exp=%0h",exp_idx,cmp_a_bot1,e_ab1[exp_idx]); mismatch_cnt=mismatch_cnt+1; end
                if (cmp_a_bot2!==e_ab2[exp_idx]) begin $display("  [MISMATCH] #%0d a_bot2 got=%0h exp=%0h",exp_idx,cmp_a_bot2,e_ab2[exp_idx]); mismatch_cnt=mismatch_cnt+1; end
                if (cmp_a_bot3!==e_ab3[exp_idx]) begin $display("  [MISMATCH] #%0d a_bot3 got=%0h exp=%0h",exp_idx,cmp_a_bot3,e_ab3[exp_idx]); mismatch_cnt=mismatch_cnt+1; end
                if (cmp_b_top0!==e_bt0[exp_idx]) begin $display("  [MISMATCH] #%0d b_top0 got=%0h exp=%0h",exp_idx,cmp_b_top0,e_bt0[exp_idx]); mismatch_cnt=mismatch_cnt+1; end
                if (cmp_b_top1!==e_bt1[exp_idx]) begin $display("  [MISMATCH] #%0d b_top1 got=%0h exp=%0h",exp_idx,cmp_b_top1,e_bt1[exp_idx]); mismatch_cnt=mismatch_cnt+1; end
                if (cmp_b_top2!==e_bt2[exp_idx]) begin $display("  [MISMATCH] #%0d b_top2 got=%0h exp=%0h",exp_idx,cmp_b_top2,e_bt2[exp_idx]); mismatch_cnt=mismatch_cnt+1; end
                if (cmp_b_top3!==e_bt3[exp_idx]) begin $display("  [MISMATCH] #%0d b_top3 got=%0h exp=%0h",exp_idx,cmp_b_top3,e_bt3[exp_idx]); mismatch_cnt=mismatch_cnt+1; end
                if (cmp_b_bot0!==e_bb0[exp_idx]) begin $display("  [MISMATCH] #%0d b_bot0 got=%0h exp=%0h",exp_idx,cmp_b_bot0,e_bb0[exp_idx]); mismatch_cnt=mismatch_cnt+1; end
                if (cmp_b_bot1!==e_bb1[exp_idx]) begin $display("  [MISMATCH] #%0d b_bot1 got=%0h exp=%0h",exp_idx,cmp_b_bot1,e_bb1[exp_idx]); mismatch_cnt=mismatch_cnt+1; end
                if (cmp_b_bot2!==e_bb2[exp_idx]) begin $display("  [MISMATCH] #%0d b_bot2 got=%0h exp=%0h",exp_idx,cmp_b_bot2,e_bb2[exp_idx]); mismatch_cnt=mismatch_cnt+1; end
                if (cmp_b_bot3!==e_bb3[exp_idx]) begin $display("  [MISMATCH] #%0d b_bot3 got=%0h exp=%0h",exp_idx,cmp_b_bot3,e_bb3[exp_idx]); mismatch_cnt=mismatch_cnt+1; end
            end
            check_cnt = check_cnt + 1;
            exp_idx = exp_idx + 1;
        end
    end

    // =========================================================================
    // Tasks
    // =========================================================================
    integer fail_total;
    initial fail_total = 0;

    task clear_inputs;
        begin
            fwd_a_valid_in = 0; fwd_b_valid_in = 0;
            {fwd_a_top0,fwd_a_top1,fwd_a_top2,fwd_a_top3} = '0;
            {fwd_a_bot0,fwd_a_bot1,fwd_a_bot2,fwd_a_bot3} = '0;
            {fwd_b_top0,fwd_b_top1,fwd_b_top2,fwd_b_top3} = '0;
            {fwd_b_bot0,fwd_b_bot1,fwd_b_bot2,fwd_b_bot3} = '0;
        end
    endtask

    // PHY-like pattern: independent sequential values per group
    //   even: a_top={v+0,v+1,0,0} a_bot={v+4,v+5,0,0} b_top={v+8,v+9,0,0} b_bot={v+c,v+d,0,0}
    //   odd:  a_top={v+2,v+3,0,0} a_bot={v+6,v+7,0,0} b_top={v+a,v+b,0,0} b_bot={v+e,v+f,0,0}
    //   compact expected: a_top={v+0,v+1,v+2,v+3} a_bot={v+4..7} b_top={v+8..b} b_bot={v+c..f}
    task drive_pair_phy;
        input integer pair_idx;
        input [1:0]  mode;
        reg [DATA_W-1:0] v;
        begin
            v = 8'h10 + pair_idx * 16;
            @(posedge clk_slow);
            fwd_a_valid_in = 1;
            fwd_b_valid_in = mode[1];
            fwd_a_top0=v+0; fwd_a_top1=v+1; fwd_a_top2=0; fwd_a_top3=0;
            fwd_a_bot0=v+4; fwd_a_bot1=v+5; fwd_a_bot2=0; fwd_a_bot3=0;
            fwd_b_top0=v+8; fwd_b_top1=v+9; fwd_b_top2=0; fwd_b_top3=0;
            fwd_b_bot0=v+12; fwd_b_bot1=v+13; fwd_b_bot2=0; fwd_b_bot3=0;
            @(posedge clk_slow);
            fwd_a_top0=v+2; fwd_a_top1=v+3; fwd_a_top2=0; fwd_a_top3=0;
            fwd_a_bot0=v+6; fwd_a_bot1=v+7; fwd_a_bot2=0; fwd_a_bot3=0;
            fwd_b_top0=v+10; fwd_b_top1=v+11; fwd_b_top2=0; fwd_b_top3=0;
            fwd_b_bot0=v+14; fwd_b_bot1=v+15; fwd_b_bot2=0; fwd_b_bot3=0;
        end
    endtask

    task store_exp_phy;
        input integer idx;
        input integer pair_idx;
        input [1:0]  mode;
        reg [DATA_W-1:0] v;
        begin
            v = 8'h10 + pair_idx * 16;
            // a_top always active
            e_at0[idx]=v+0;  e_at1[idx]=v+1;  e_at2[idx]=v+2;  e_at3[idx]=v+3;
            // a_bot active for 8L/12L/16L
            if (mode >= 2'b01) begin
                e_ab0[idx]=v+4; e_ab1[idx]=v+5; e_ab2[idx]=v+6; e_ab3[idx]=v+7;
            end else begin
                e_ab0[idx]=0; e_ab1[idx]=0; e_ab2[idx]=0; e_ab3[idx]=0;
            end
            // b_top active for 12L/16L
            if (mode >= 2'b10) begin
                e_bt0[idx]=v+8; e_bt1[idx]=v+9; e_bt2[idx]=v+10; e_bt3[idx]=v+11;
            end else begin
                e_bt0[idx]=0; e_bt1[idx]=0; e_bt2[idx]=0; e_bt3[idx]=0;
            end
            // b_bot active for 16L only
            if (mode == 2'b11) begin
                e_bb0[idx]=v+12; e_bb1[idx]=v+13; e_bb2[idx]=v+14; e_bb3[idx]=v+15;
            end else begin
                e_bb0[idx]=0; e_bb1[idx]=0; e_bb2[idx]=0; e_bb3[idx]=0;
            end
        end
    endtask

    // VLANE-like pattern: even/odd interleaved per group
    //   even: a_top={v+0,v+1,0,0} a_bot={v+2,v+3,0,0} b_top={v+4,v+5,0,0} b_bot={v+6,v+7,0,0}
    //   odd:  a_top={v+8,v+9,0,0} a_bot={v+a,v+b,0,0} b_top={v+c,v+d,0,0} b_bot={v+e,v+f,0,0}
    //   compact expected: a_top={v+0,v+1,v+8,v+9} a_bot={v+2..3,v+a..b} ...
    task drive_pair_vlane;
        input integer pair_idx;
        input [1:0]  mode;
        reg [DATA_W-1:0] v;
        begin
            v = 8'h20 + pair_idx * 16;
            @(posedge clk_slow);
            fwd_a_valid_in = 1;
            fwd_b_valid_in = mode[1];
            fwd_a_top0=v+0; fwd_a_top1=v+1; fwd_a_top2=0; fwd_a_top3=0;
            fwd_a_bot0=v+2; fwd_a_bot1=v+3; fwd_a_bot2=0; fwd_a_bot3=0;
            fwd_b_top0=v+4; fwd_b_top1=v+5; fwd_b_top2=0; fwd_b_top3=0;
            fwd_b_bot0=v+6; fwd_b_bot1=v+7; fwd_b_bot2=0; fwd_b_bot3=0;
            @(posedge clk_slow);
            fwd_a_top0=v+8;  fwd_a_top1=v+9;  fwd_a_top2=0; fwd_a_top3=0;
            fwd_a_bot0=v+10; fwd_a_bot1=v+11; fwd_a_bot2=0; fwd_a_bot3=0;
            fwd_b_top0=v+12; fwd_b_top1=v+13; fwd_b_top2=0; fwd_b_top3=0;
            fwd_b_bot0=v+14; fwd_b_bot1=v+15; fwd_b_bot2=0; fwd_b_bot3=0;
        end
    endtask

    task store_exp_vlane;
        input integer idx;
        input integer pair_idx;
        input [1:0]  mode;
        reg [DATA_W-1:0] v;
        begin
            v = 8'h20 + pair_idx * 16;
            e_at0[idx]=v+0; e_at1[idx]=v+1; e_at2[idx]=v+8;  e_at3[idx]=v+9;
            if (mode >= 2'b01) begin
                e_ab0[idx]=v+2; e_ab1[idx]=v+3; e_ab2[idx]=v+10; e_ab3[idx]=v+11;
            end else begin
                e_ab0[idx]=0; e_ab1[idx]=0; e_ab2[idx]=0; e_ab3[idx]=0;
            end
            if (mode >= 2'b10) begin
                e_bt0[idx]=v+4; e_bt1[idx]=v+5; e_bt2[idx]=v+12; e_bt3[idx]=v+13;
            end else begin
                e_bt0[idx]=0; e_bt1[idx]=0; e_bt2[idx]=0; e_bt3[idx]=0;
            end
            if (mode == 2'b11) begin
                e_bb0[idx]=v+6; e_bb1[idx]=v+7; e_bb2[idx]=v+14; e_bb3[idx]=v+15;
            end else begin
                e_bb0[idx]=0; e_bb1[idx]=0; e_bb2[idx]=0; e_bb3[idx]=0;
            end
        end
    endtask

    task run_mode;
        input [255:0] name;
        input [1:0]   mode;
        input integer ratio;
        input integer drain;
        input integer is_vlane;
        integer p;
        begin
            $display("\n--- %0s ---", name);
            lane_mode = mode;
            slow_half = ratio * CLK_FAST_HALF;
            mismatch_cnt = 0;
            check_cnt = 0;
            exp_idx = 0;
            exp_total = NUM_PAIRS;
            is_drain_mode = drain;
            checking_en = 0;

            if (!drain) begin
                for (p = 0; p < NUM_PAIRS; p = p + 1) begin
                    if (is_vlane) store_exp_vlane(p, p, mode);
                    else          store_exp_phy(p, p, mode);
                end
            end

            clear_inputs;
            rst_n = 0;
            repeat(8) @(posedge clk_fast);
            rst_n = 1;
            repeat(2) @(posedge clk_slow);
            checking_en = 1;

            for (p = 0; p < NUM_PAIRS; p = p + 1) begin
                if (is_vlane) drive_pair_vlane(p, mode);
                else          drive_pair_phy(p, mode);
            end

            @(posedge clk_slow);
            clear_inputs;
            repeat(NUM_PAIRS * ratio + 40) @(posedge clk_slow);
            checking_en = 0;

            if (drain) begin
                if (check_cnt >= NUM_PAIRS)
                    $display("  PASS %0s drain-checked %0d outputs", name, check_cnt);
                else begin
                    $display("  FAIL %0s expected >= %0d, got %0d", name, NUM_PAIRS, check_cnt);
                    fail_total = fail_total + 1;
                end
            end else begin
                if (mismatch_cnt == 0 && check_cnt >= NUM_PAIRS)
                    $display("  PASS %0s checked %0d outputs, 0 mismatches", name, check_cnt);
                else begin
                    $display("  FAIL %0s checks=%0d mismatches=%0d", name, check_cnt, mismatch_cnt);
                    fail_total = fail_total + 1;
                end
            end
        end
    endtask

    // =========================================================================
    // Main: 8 cases = 4 lane modes × 2 patterns
    // =========================================================================
    initial begin
        fail_total = 0;
        rst_n = 0;
        lane_mode = 2'b00;
        slow_half = CLK_FAST_HALF;
        clear_inputs;
        checking_en = 0;

        //                       name                mode  ratio drain vlane
        run_mode("4L  PHY  20-pair",  2'b00,  1,    0,    0);
        run_mode("4L  VLANE 20-pair", 2'b00,  1,    0,    1);
        run_mode("8L  PHY  20-pair",  2'b01,  2,    0,    0);
        run_mode("8L  VLANE 20-pair", 2'b01,  2,    0,    1);
        run_mode("12L PHY  20-pair",  2'b10,  3,    1,    0);
        run_mode("12L VLANE 20-pair", 2'b10,  3,    1,    1);
        run_mode("16L PHY  20-pair",  2'b11,  4,    0,    0);
        run_mode("16L VLANE 20-pair", 2'b11,  4,    0,    1);

        $display("\n============================================");
        if (fail_total == 0)
            $display("[PASS] ALL DESCHED_TOP LOOPBACK TESTS PASSED (8 cases, %0d pairs each)", NUM_PAIRS);
        else
            $display("[FAIL] %0d case(s) failed", fail_total);
        $display("============================================");
        $finish;
    end

endmodule
