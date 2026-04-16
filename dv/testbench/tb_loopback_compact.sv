// =============================================================================
// Testbench: tb_loopback_compact
// Full chain: Scheduler_Top → Descheduler → Lane Compactor
//
// Tests 16L PHY mode with full 16-lane input.
// Uses the same input pattern as tb_inplace_transpose_buf_multi_lane_top:
//   din[n] = n*16 + cycle_num,  n = 0..15
//
// scheduler_top receives per-lane-per-cycle input (din0..din15),
// internally does chunk accumulation + serialization.
// Descheduler does inverse transpose back to per-lane-per-cycle.
// Compactor merges 2 consecutive descheduler outputs into 1.
//
// 16L PHY config:
//   lane_mode = 2'b11, virtual_lane_en = 0
//   clk ratio = 4:1 (slow_half = 4 * CLK_FAST_HALF)
//
// Original input (8 cycles, all 16 lanes active):
//   cycle0: din0=0,   din1=16,  din2=32,  ..., din15=240
//   cycle1: din0=1,   din1=17,  din2=33,  ..., din15=241
//   ...
//   cycle7: din0=7,   din1=23,  din2=39,  ..., din15=247
//
// Expected descheduler output (= original input, per-lane-per-cycle):
//   cycle0: a_top={0,16,32,48}  a_bot={64,80,96,112}
//           b_top={128,144,160,176}  b_bot={192,208,224,240}
//   cycle1: a_top={1,17,33,49}  a_bot={65,81,97,113}
//           b_top={129,145,161,177}  b_bot={193,209,225,241}
//   ...
//
// Expected compactor output (2:1 merge of consecutive descheduler outputs):
//   cmp0 = merge(cycle0, cycle1):
//     a_top={0,16,1,17} a_bot={64,80,65,81} b_top={128,144,129,145} b_bot={192,208,193,209}
//   cmp1 = merge(cycle2, cycle3):
//     a_top={2,18,3,19} a_bot={66,82,67,83} b_top={130,146,131,147} b_bot={194,210,195,211}
//   cmp2 = merge(cycle4, cycle5):
//     a_top={4,20,5,21} a_bot={68,84,69,85} b_top={132,148,133,149} b_bot={196,212,197,213}
//   cmp3 = merge(cycle6, cycle7):
//     a_top={6,22,7,23} a_bot={70,86,71,87} b_top={134,150,135,151} b_bot={198,214,199,215}
//
// VCD: wave_loopback_compact.vcd
// =============================================================================

`timescale 1ns/1ps

module tb_loopback_compact;

    localparam DATA_W = 8;
    localparam CLK_FAST_HALF = 5;  // 10ns

    // Clocks
    logic clk_fast, clk_slow, clk_slow_div2;

    // Scheduler_top ports
    logic                  rst_n;
    logic [1:0]            lane_mode;
    logic                  virtual_lane_en;
    logic                  fwd_valid_in;
    logic [DATA_W-1:0]     fwd_din [0:15];
    logic                  fwd_valid_out;
    logic [DATA_W-1:0]     fwd_dout0, fwd_dout1, fwd_dout2, fwd_dout3;
    logic                  align_error_flag;
    logic [2:0]            fwd_dbg_state;
    logic [3:0]            fwd_dbg_fifo_cnt;

    // Descheduler ports
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
    // DUT chain: Scheduler_Top → Descheduler → Compactor
    // =========================================================================
    inplace_transpose_buf_multi_lane_scheduler_top #(.DATA_W(DATA_W)) u_fwd (
        .clk_in(clk_slow), .clk_out(clk_fast), .rst_n(rst_n),
        .valid_in(fwd_valid_in),
        .lane_mode(lane_mode),
        .virtual_lane_en(virtual_lane_en),
        .align_mode(1'b1),
        .din0(fwd_din[0]),   .din1(fwd_din[1]),   .din2(fwd_din[2]),   .din3(fwd_din[3]),
        .din4(fwd_din[4]),   .din5(fwd_din[5]),   .din6(fwd_din[6]),   .din7(fwd_din[7]),
        .din8(fwd_din[8]),   .din9(fwd_din[9]),   .din10(fwd_din[10]), .din11(fwd_din[11]),
        .din12(fwd_din[12]), .din13(fwd_din[13]), .din14(fwd_din[14]), .din15(fwd_din[15]),
        .align_error_flag(align_error_flag),
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
        .clk_in_fast(clk_slow), .clk_out_slow(clk_slow_div2), .rst_n(rst_n),
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
    initial slow_half = 4 * CLK_FAST_HALF;  // 20

    initial begin
        clk_slow = 0;
        #(CLK_FAST_HALF);
        forever #(slow_half) clk_slow = ~clk_slow;
    end

    // clk_slow_div2 = clk_slow / 2 (compactor output clock, same-PLL)
    initial begin
        clk_slow_div2 = 0;
        #(CLK_FAST_HALF);
        forever #(2*slow_half) clk_slow_div2 = ~clk_slow_div2;
    end

    // VCD
    initial begin
        $dumpfile("wave_loopback_compact.vcd");
        $dumpvars(0, tb_loopback_compact);
    end

    // =========================================================================
    // Stimulus: 8 slow cycles, 16L PHY pattern (same as scheduler_top TB)
    //   din[n] = n*16 + cycle_num
    // =========================================================================
    integer i, n;

    task clear_din;
        integer j;
        begin
            fwd_valid_in = 0;
            for (j = 0; j < 16; j = j + 1) fwd_din[j] = 0;
        end
    endtask

    initial begin
        rst_n           = 0;
        lane_mode       = 2'b11;  // 16L
        virtual_lane_en = 0;      // PHY mode
        clear_din;

        repeat(6) @(posedge clk_fast);
        rst_n = 1;
        repeat(2) @(posedge clk_slow);

        // 8 cycles: din[n] = n*16 + i
        for (i = 0; i < 8; i = i + 1) begin
            @(posedge clk_slow);
            fwd_valid_in = 1;
            for (n = 0; n < 16; n = n + 1)
                fwd_din[n] = n * 16 + i;
        end

        @(posedge clk_slow);
        clear_din;

        repeat(60) @(posedge clk_slow);

        $display("============================================");
        $display("[INFO] Loopback+Compact test completed");
        $display("[INFO] Descheduler: outputs=%0d mismatches=%0d", desched_idx, desched_mismatch);
        $display("[INFO] Compactor:   checks=%0d mismatches=%0d", check_cnt, mismatch_cnt);
        if (desched_mismatch == 0 && desched_idx >= 8 && mismatch_cnt == 0 && check_cnt >= 4)
            $display("[PASS] Loopback+Compact 16L test passed");
        else
            $display("[FAIL] Loopback+Compact 16L test FAILED");
        $display("============================================");
        $finish;
    end

    // =========================================================================
    // Auto-checker
    // =========================================================================
    integer mismatch_cnt, check_cnt, exp_idx;
    initial begin mismatch_cnt=0; check_cnt=0; exp_idx=0; end

    // Expected compactor outputs (2:1 merge of consecutive descheduler outputs)
    // Descheduler output = original din (per-lane-per-cycle):
    //   cycle t: a_top = {t, 16+t, 32+t, 48+t}
    //            a_bot = {64+t, 80+t, 96+t, 112+t}
    //            b_top = {128+t, 144+t, 160+t, 176+t}
    //            b_bot = {192+t, 208+t, 224+t, 240+t}
    //
    // Compactor merge(even=t, odd=t+1):
    //   a_top = {t, 16+t, t+1, 16+t+1}
    //   a_bot = {64+t, 80+t, 64+t+1, 80+t+1}
    //   b_top = {128+t, 144+t, 128+t+1, 144+t+1}
    //   b_bot = {192+t, 208+t, 192+t+1, 208+t+1}
    //
    // cmp0 (t=0,1): a_top={0,16,1,17}  a_bot={64,80,65,81}  b_top={128,144,129,145}  b_bot={192,208,193,209}
    // cmp1 (t=2,3): a_top={2,18,3,19}  a_bot={66,82,67,83}  b_top={130,146,131,147}  b_bot={194,210,195,211}
    // cmp2 (t=4,5): a_top={4,20,5,21}  a_bot={68,84,69,85}  b_top={132,148,133,149}  b_bot={196,212,197,213}
    // cmp3 (t=6,7): a_top={6,22,7,23}  a_bot={70,86,71,87}  b_top={134,150,135,151}  b_bot={198,214,199,215}

    logic [DATA_W-1:0] e_at0[0:3], e_at1[0:3], e_at2[0:3], e_at3[0:3];
    logic [DATA_W-1:0] e_ab0[0:3], e_ab1[0:3], e_ab2[0:3], e_ab3[0:3];
    logic [DATA_W-1:0] e_bt0[0:3], e_bt1[0:3], e_bt2[0:3], e_bt3[0:3];
    logic [DATA_W-1:0] e_bb0[0:3], e_bb1[0:3], e_bb2[0:3], e_bb3[0:3];

    initial begin
        // cmp0: merge(cycle0, cycle1)
        e_at0[0]=8'd0;   e_at1[0]=8'd16;  e_at2[0]=8'd1;   e_at3[0]=8'd17;
        e_ab0[0]=8'd64;  e_ab1[0]=8'd80;  e_ab2[0]=8'd65;  e_ab3[0]=8'd81;
        e_bt0[0]=8'd128; e_bt1[0]=8'd144; e_bt2[0]=8'd129; e_bt3[0]=8'd145;
        e_bb0[0]=8'd192; e_bb1[0]=8'd208; e_bb2[0]=8'd193; e_bb3[0]=8'd209;
        // cmp1: merge(cycle2, cycle3)
        e_at0[1]=8'd2;   e_at1[1]=8'd18;  e_at2[1]=8'd3;   e_at3[1]=8'd19;
        e_ab0[1]=8'd66;  e_ab1[1]=8'd82;  e_ab2[1]=8'd67;  e_ab3[1]=8'd83;
        e_bt0[1]=8'd130; e_bt1[1]=8'd146; e_bt2[1]=8'd131; e_bt3[1]=8'd147;
        e_bb0[1]=8'd194; e_bb1[1]=8'd210; e_bb2[1]=8'd195; e_bb3[1]=8'd211;
        // cmp2: merge(cycle4, cycle5)
        e_at0[2]=8'd4;   e_at1[2]=8'd20;  e_at2[2]=8'd5;   e_at3[2]=8'd21;
        e_ab0[2]=8'd68;  e_ab1[2]=8'd84;  e_ab2[2]=8'd69;  e_ab3[2]=8'd85;
        e_bt0[2]=8'd132; e_bt1[2]=8'd148; e_bt2[2]=8'd133; e_bt3[2]=8'd149;
        e_bb0[2]=8'd196; e_bb1[2]=8'd212; e_bb2[2]=8'd197; e_bb3[2]=8'd213;
        // cmp3: merge(cycle6, cycle7)
        e_at0[3]=8'd6;   e_at1[3]=8'd22;  e_at2[3]=8'd7;   e_at3[3]=8'd23;
        e_ab0[3]=8'd70;  e_ab1[3]=8'd86;  e_ab2[3]=8'd71;  e_ab3[3]=8'd87;
        e_bt0[3]=8'd134; e_bt1[3]=8'd150; e_bt2[3]=8'd135; e_bt3[3]=8'd151;
        e_bb0[3]=8'd198; e_bb1[3]=8'd214; e_bb2[3]=8'd199; e_bb3[3]=8'd215;
    end

    always @(posedge clk_slow) begin
        if (rst_n && cmp_valid_out && exp_idx < 4) begin
            check_cnt = check_cnt + 1;
            $display("[CMP] #%0d a_top={%0d,%0d,%0d,%0d} a_bot={%0d,%0d,%0d,%0d} b_top={%0d,%0d,%0d,%0d} b_bot={%0d,%0d,%0d,%0d}",
                exp_idx,
                cmp_a_top0,cmp_a_top1,cmp_a_top2,cmp_a_top3,
                cmp_a_bot0,cmp_a_bot1,cmp_a_bot2,cmp_a_bot3,
                cmp_b_top0,cmp_b_top1,cmp_b_top2,cmp_b_top3,
                cmp_b_bot0,cmp_b_bot1,cmp_b_bot2,cmp_b_bot3);

            if (cmp_a_top0!==e_at0[exp_idx]) begin $display("[MISMATCH] a_top0=%0d exp=%0d",cmp_a_top0,e_at0[exp_idx]); mismatch_cnt=mismatch_cnt+1; end
            if (cmp_a_top1!==e_at1[exp_idx]) begin $display("[MISMATCH] a_top1=%0d exp=%0d",cmp_a_top1,e_at1[exp_idx]); mismatch_cnt=mismatch_cnt+1; end
            if (cmp_a_top2!==e_at2[exp_idx]) begin $display("[MISMATCH] a_top2=%0d exp=%0d",cmp_a_top2,e_at2[exp_idx]); mismatch_cnt=mismatch_cnt+1; end
            if (cmp_a_top3!==e_at3[exp_idx]) begin $display("[MISMATCH] a_top3=%0d exp=%0d",cmp_a_top3,e_at3[exp_idx]); mismatch_cnt=mismatch_cnt+1; end
            if (cmp_a_bot0!==e_ab0[exp_idx]) begin $display("[MISMATCH] a_bot0=%0d exp=%0d",cmp_a_bot0,e_ab0[exp_idx]); mismatch_cnt=mismatch_cnt+1; end
            if (cmp_a_bot1!==e_ab1[exp_idx]) begin $display("[MISMATCH] a_bot1=%0d exp=%0d",cmp_a_bot1,e_ab1[exp_idx]); mismatch_cnt=mismatch_cnt+1; end
            if (cmp_a_bot2!==e_ab2[exp_idx]) begin $display("[MISMATCH] a_bot2=%0d exp=%0d",cmp_a_bot2,e_ab2[exp_idx]); mismatch_cnt=mismatch_cnt+1; end
            if (cmp_a_bot3!==e_ab3[exp_idx]) begin $display("[MISMATCH] a_bot3=%0d exp=%0d",cmp_a_bot3,e_ab3[exp_idx]); mismatch_cnt=mismatch_cnt+1; end
            if (cmp_b_top0!==e_bt0[exp_idx]) begin $display("[MISMATCH] b_top0=%0d exp=%0d",cmp_b_top0,e_bt0[exp_idx]); mismatch_cnt=mismatch_cnt+1; end
            if (cmp_b_top1!==e_bt1[exp_idx]) begin $display("[MISMATCH] b_top1=%0d exp=%0d",cmp_b_top1,e_bt1[exp_idx]); mismatch_cnt=mismatch_cnt+1; end
            if (cmp_b_top2!==e_bt2[exp_idx]) begin $display("[MISMATCH] b_top2=%0d exp=%0d",cmp_b_top2,e_bt2[exp_idx]); mismatch_cnt=mismatch_cnt+1; end
            if (cmp_b_top3!==e_bt3[exp_idx]) begin $display("[MISMATCH] b_top3=%0d exp=%0d",cmp_b_top3,e_bt3[exp_idx]); mismatch_cnt=mismatch_cnt+1; end
            if (cmp_b_bot0!==e_bb0[exp_idx]) begin $display("[MISMATCH] b_bot0=%0d exp=%0d",cmp_b_bot0,e_bb0[exp_idx]); mismatch_cnt=mismatch_cnt+1; end
            if (cmp_b_bot1!==e_bb1[exp_idx]) begin $display("[MISMATCH] b_bot1=%0d exp=%0d",cmp_b_bot1,e_bb1[exp_idx]); mismatch_cnt=mismatch_cnt+1; end
            if (cmp_b_bot2!==e_bb2[exp_idx]) begin $display("[MISMATCH] b_bot2=%0d exp=%0d",cmp_b_bot2,e_bb2[exp_idx]); mismatch_cnt=mismatch_cnt+1; end
            if (cmp_b_bot3!==e_bb3[exp_idx]) begin $display("[MISMATCH] b_bot3=%0d exp=%0d",cmp_b_bot3,e_bb3[exp_idx]); mismatch_cnt=mismatch_cnt+1; end

            exp_idx = exp_idx + 1;
        end
    end

    // Monitor scheduler_top serialized output
    integer sched_beat;
    initial sched_beat = 0;
    always @(posedge clk_fast) begin
        if (rst_n && fwd_valid_out) begin
            $display("[SCHED] beat%0d dout={%0d,%0d,%0d,%0d}",
                sched_beat, fwd_dout0,fwd_dout1,fwd_dout2,fwd_dout3);
            sched_beat = sched_beat + 1;
        end
    end

    // Monitor and check descheduler output (should = original din)
    // Expected: cycle t → a_top={t, 16+t, 32+t, 48+t}
    //                      a_bot={64+t, 80+t, 96+t, 112+t}
    //                      b_top={128+t, 144+t, 160+t, 176+t}
    //                      b_bot={192+t, 208+t, 224+t, 240+t}
    integer desched_idx, desched_mismatch;
    initial begin desched_idx=0; desched_mismatch=0; end

    always @(posedge clk_slow) begin
        if (rst_n && rev_valid_out) begin
            $display("[DESCHED] #%0d a_top={%0d,%0d,%0d,%0d} a_bot={%0d,%0d,%0d,%0d} b_top={%0d,%0d,%0d,%0d} b_bot={%0d,%0d,%0d,%0d}",
                desched_idx,
                rev_a_top0,rev_a_top1,rev_a_top2,rev_a_top3,
                rev_a_bot0,rev_a_bot1,rev_a_bot2,rev_a_bot3,
                rev_b_top0,rev_b_top1,rev_b_top2,rev_b_top3,
                rev_b_bot0,rev_b_bot1,rev_b_bot2,rev_b_bot3);

            if (desched_idx < 8) begin
                if (rev_a_top0 !== desched_idx)       begin $display("[D-MISMATCH] a_top0=%0d exp=%0d", rev_a_top0, desched_idx);       desched_mismatch=desched_mismatch+1; end
                if (rev_a_top1 !== 16+desched_idx)    begin $display("[D-MISMATCH] a_top1=%0d exp=%0d", rev_a_top1, 16+desched_idx);    desched_mismatch=desched_mismatch+1; end
                if (rev_a_top2 !== 32+desched_idx)    begin $display("[D-MISMATCH] a_top2=%0d exp=%0d", rev_a_top2, 32+desched_idx);    desched_mismatch=desched_mismatch+1; end
                if (rev_a_top3 !== 48+desched_idx)    begin $display("[D-MISMATCH] a_top3=%0d exp=%0d", rev_a_top3, 48+desched_idx);    desched_mismatch=desched_mismatch+1; end
                if (rev_a_bot0 !== 64+desched_idx)    begin $display("[D-MISMATCH] a_bot0=%0d exp=%0d", rev_a_bot0, 64+desched_idx);    desched_mismatch=desched_mismatch+1; end
                if (rev_a_bot1 !== 80+desched_idx)    begin $display("[D-MISMATCH] a_bot1=%0d exp=%0d", rev_a_bot1, 80+desched_idx);    desched_mismatch=desched_mismatch+1; end
                if (rev_a_bot2 !== 96+desched_idx)    begin $display("[D-MISMATCH] a_bot2=%0d exp=%0d", rev_a_bot2, 96+desched_idx);    desched_mismatch=desched_mismatch+1; end
                if (rev_a_bot3 !== 112+desched_idx)   begin $display("[D-MISMATCH] a_bot3=%0d exp=%0d", rev_a_bot3, 112+desched_idx);   desched_mismatch=desched_mismatch+1; end
                if (rev_b_top0 !== 128+desched_idx)   begin $display("[D-MISMATCH] b_top0=%0d exp=%0d", rev_b_top0, 128+desched_idx);   desched_mismatch=desched_mismatch+1; end
                if (rev_b_top1 !== 144+desched_idx)   begin $display("[D-MISMATCH] b_top1=%0d exp=%0d", rev_b_top1, 144+desched_idx);   desched_mismatch=desched_mismatch+1; end
                if (rev_b_top2 !== 160+desched_idx)   begin $display("[D-MISMATCH] b_top2=%0d exp=%0d", rev_b_top2, 160+desched_idx);   desched_mismatch=desched_mismatch+1; end
                if (rev_b_top3 !== 176+desched_idx)   begin $display("[D-MISMATCH] b_top3=%0d exp=%0d", rev_b_top3, 176+desched_idx);   desched_mismatch=desched_mismatch+1; end
                if (rev_b_bot0 !== 192+desched_idx)   begin $display("[D-MISMATCH] b_bot0=%0d exp=%0d", rev_b_bot0, 192+desched_idx);   desched_mismatch=desched_mismatch+1; end
                if (rev_b_bot1 !== 208+desched_idx)   begin $display("[D-MISMATCH] b_bot1=%0d exp=%0d", rev_b_bot1, 208+desched_idx);   desched_mismatch=desched_mismatch+1; end
                if (rev_b_bot2 !== 224+desched_idx)   begin $display("[D-MISMATCH] b_bot2=%0d exp=%0d", rev_b_bot2, 224+desched_idx);   desched_mismatch=desched_mismatch+1; end
                if (rev_b_bot3 !== 240+desched_idx)   begin $display("[D-MISMATCH] b_bot3=%0d exp=%0d", rev_b_bot3, 240+desched_idx);   desched_mismatch=desched_mismatch+1; end
            end
            desched_idx = desched_idx + 1;
        end
    end

endmodule
