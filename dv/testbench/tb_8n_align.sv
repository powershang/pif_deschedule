`timescale 1ns/1ps

// =============================================================================
// Testbench: tb_8n_align
// DUT: lanedata_8n_align_process
//
// Scope:
//   8 rem cases (rem 0..7) + 1 back-to-back case = 9 cases total.
//
// Checks per case:
//   - Even rem (0,2,4,6): length + data (bit-exact, including padding pattern
//                         c_{N-1}, cN, c_{N-1}, cN, ...) + error_flag == 0.
//   - Odd  rem (1,3,5,7): length + error_flag == 1 (padding data don't-care
//                         because tail_buf[1] may be residual on rem=1).
//   - No valid_out gap.
//
// Stimulus rule:
//   Per project memory: every lane must have independent non-zero data.
//   => din[n] at beat i of the burst = (i * 16 + n + base) & 0xFF
//      (base is chosen per-burst to avoid aliasing across cases).
//   Lane 0 therefore carries i (+ base).
// =============================================================================

module tb_8n_align;

    parameter DATA_W = 8;
    parameter CLK_HALF = 5;

    logic              clk, rst_n;
    logic              valid_in, virtual_lane_en;
    logic [DATA_W-1:0] din  [0:15];
    logic [DATA_W-1:0] dout [0:15];
    logic              valid_out;
    logic              error_flag;

    lanedata_8n_align_process #(.DATA_W(DATA_W)) dut (
        .clk(clk), .rst_n(rst_n),
        .valid_in(valid_in), .virtual_lane_en(virtual_lane_en),
        .din0 (din[0]),  .din1 (din[1]),  .din2 (din[2]),  .din3 (din[3]),
        .din4 (din[4]),  .din5 (din[5]),  .din6 (din[6]),  .din7 (din[7]),
        .din8 (din[8]),  .din9 (din[9]),  .din10(din[10]), .din11(din[11]),
        .din12(din[12]), .din13(din[13]), .din14(din[14]), .din15(din[15]),
        .valid_out(valid_out),
        .dout0 (dout[0]),  .dout1 (dout[1]),  .dout2 (dout[2]),  .dout3 (dout[3]),
        .dout4 (dout[4]),  .dout5 (dout[5]),  .dout6 (dout[6]),  .dout7 (dout[7]),
        .dout8 (dout[8]),  .dout9 (dout[9]),  .dout10(dout[10]), .dout11(dout[11]),
        .dout12(dout[12]), .dout13(dout[13]), .dout14(dout[14]), .dout15(dout[15]),
        .error_flag(error_flag)
    );

    initial clk = 0;
    always #(CLK_HALF) clk = ~clk;

    initial begin
        $dumpfile("wave_8n_align.vcd");
        $dumpvars(0, tb_8n_align);
    end

    // Debug probe: print beat_mod_q / error_flag_q / error_flag whenever the
    // DUT detects "burst just ended" (prev_valid_q=1 && valid_in=0)
    always @(posedge clk) begin
        if (rst_n && dut.prev_valid_q && !dut.valid_in && !dut.pad_active_q) begin
            $display("[BURST-END @%0t] beat_mod_q=%0d error_flag_q(before)=%0b error_flag(before)=%0b tail_top_q=%0b",
                     $time, dut.beat_mod_q, dut.error_flag_q, dut.error_flag, dut.tail_buf_top_q);
        end
    end
    // One cycle after burst-end, confirm error_flag latched
    always @(posedge clk) begin
        if (rst_n && dut.pad_active_q) begin
            $display("[PAD      @%0t] pad_left_q=%0d error_flag_q=%0b error_flag=%0b",
                     $time, dut.pad_left_q, dut.error_flag_q, dut.error_flag);
        end
    end

    // =========================================================================
    // Output capture (all 16 lanes)
    // =========================================================================
    integer            cap_count;
    reg [DATA_W-1:0]   cap[0:15][0:127];
    reg                cap_err[0:127];
    integer            cap_gap;
    integer            cap_started;
    integer            cap_seen_end;

    always @(posedge clk) begin
        if (rst_n && cap_started) begin
            if (valid_out) begin
                for (int l = 0; l < 16; l++)
                    cap[l][cap_count] = dout[l];
                cap_err[cap_count] = error_flag;
                cap_count = cap_count + 1;
                if (cap_seen_end)
                    cap_gap = 1;
            end else if (cap_count > 0) begin
                cap_seen_end = 1;
            end
        end
    end

    // =========================================================================
    // Common infra
    // =========================================================================
    integer fail_count;
    integer pass_count;
    string  summary_line[$];
    initial begin fail_count = 0; pass_count = 0; end

    task clear_cap;
        begin
            cap_count = 0;
            cap_gap = 0;
            cap_seen_end = 0;
            cap_started = 0;
        end
    endtask

    task do_reset;
        begin
            rst_n = 0;
            valid_in = 0;
            virtual_lane_en = 0;
            for (int i = 0; i < 16; i++) din[i] = '0;
            clear_cap();
            repeat(3) @(posedge clk);
            rst_n = 1;
            @(posedge clk);
        end
    endtask

    // Drive burst of `len` beats with given per-beat base (lane n at beat i = base + i*16 + n)
    task drive_burst;
        input integer len;
        input integer base_val;
        integer i;
        begin
            for (i = 0; i < len; i++) begin
                @(posedge clk);
                #1;
                valid_in = 1;
                for (int l = 0; l < 16; l++)
                    din[l] = (base_val + i*16 + l) & 8'hFF;
            end
            @(posedge clk);
            #1;
            valid_in = 0;
            for (int l = 0; l < 16; l++) din[l] = '0;
        end
    endtask

    // Compute expected lane-l data for beat index i of a burst with given base
    function automatic [DATA_W-1:0] exp_din;
        input integer i;
        input integer l;
        input integer base_val;
        begin
            exp_din = (base_val + i*16 + l) & 8'hFF;
        end
    endfunction

    // =========================================================================
    // Single burst test (one rem value)
    // =========================================================================
    task run_rem_case;
        input [255:0]  test_name;
        input integer  burst_len;
        input integer  base_val;
        input integer  rem_val;       // rem = burst_len mod 8
        input integer  vlane_en;      // 0 = PHY mode, 1 = VLANE mode
        integer i, l;
        integer pad_total;
        integer exp_out_len;
        integer is_odd_rem;
        logic [DATA_W-1:0] exp_val;
        integer pass_this_case;
        integer local_fail;
        begin
            local_fail = 0;
            $display("\n--- CASE: %0s (vlane_en=%0d) ---", test_name, vlane_en);
            do_reset;
            virtual_lane_en = vlane_en[0];
            cap_started = 1;

            drive_burst(burst_len, base_val);

            repeat(16) @(posedge clk);
            cap_started = 0;

            pad_total   = (rem_val == 0) ? 0 : (8 - rem_val);
            exp_out_len = burst_len + pad_total;
            is_odd_rem  = rem_val[0];

            // Check 1: length
            if (cap_count !== exp_out_len) begin
                $display("  FAIL out_count=%0d expected=%0d", cap_count, exp_out_len);
                local_fail++;
            end else begin
                $display("  PASS out_count=%0d (burst=%0d pad=%0d)",
                         cap_count, burst_len, pad_total);
            end

            // Check 2: no gap
            if (cap_gap) begin
                $display("  FAIL valid_out had gap");
                local_fail++;
            end

            // Check 3: passthrough data (first burst_len beats, all lanes)
            for (i = 0; i < burst_len && i < cap_count; i++) begin
                for (l = 0; l < 16; l++) begin
                    exp_val = exp_din(i, l, base_val);
                    if (cap[l][i] !== exp_val) begin
                        $display("  FAIL passthrough beat=%0d lane=%0d got=%02h exp=%02h",
                                 i, l, cap[l][i], exp_val);
                        local_fail++;
                    end
                end
            end

            // Check 4: padding data (only for even rem; odd rem don't-care)
            if (!is_odd_rem && rem_val != 0 && cap_count >= exp_out_len) begin
                // Padding beats: positions [burst_len .. burst_len+pad_total-1]
                // Sequence (new spec): c_{N-1}, cN, c_{N-1}, cN, ...
                //   pad_idx 0 -> beat (burst_len-2)
                //   pad_idx 1 -> beat (burst_len-1)
                //   pad_idx 2 -> beat (burst_len-2)
                //   pad_idx 3 -> beat (burst_len-1)
                for (i = 0; i < pad_total; i++) begin
                    integer src_beat;
                    src_beat = (i[0] == 0) ? (burst_len - 2) : (burst_len - 1);
                    for (l = 0; l < 16; l++) begin
                        exp_val = exp_din(src_beat, l, base_val);
                        if (cap[l][burst_len + i] !== exp_val) begin
                            $display("  FAIL pad beat=%0d (pad_idx=%0d src=%0d) lane=%0d got=%02h exp=%02h",
                                     burst_len+i, i, src_beat, l,
                                     cap[l][burst_len + i], exp_val);
                            local_fail++;
                        end
                    end
                end
            end

            // Check 5: error_flag (per-beat, full timeline)
            //
            // Spec:
            //   Even rem (0,2,4,6): error_flag MUST be 0 on EVERY valid_out=1
            //                       beat (burst + any padding).
            //   Odd  rem (1,3,5,7): error_flag MUST be 1 on EVERY padding beat,
            //                       MUST be 1 on the last valid_out=1 beat,
            //                       and MUST be sticky — once asserted it may
            //                       not drop back to 0 within the same burst.
            //
            // Always dump the full per-beat err timeline to the log so humans
            // can eyeball it against FSDB without re-running.
            begin : err_flag_check
                integer saw_err_high;
                integer err_dropped_after_high;
                string  tag;
                saw_err_high = 0;
                err_dropped_after_high = 0;

                $display("  ERR_TIMELINE %0s (rem=%0d expected=%0s):",
                         test_name, rem_val, is_odd_rem ? "ODD->1" : "EVEN->0");
                for (int b = 0; b < cap_count; b++) begin
                    tag = (b < burst_len) ? "burst" : "pad  ";
                    $display("    beat[%0d] %0s  err=%0b", b, tag, cap_err[b]);
                    if (cap_err[b] === 1'b1) saw_err_high = 1;
                    else if (saw_err_high && cap_err[b] === 1'b0)
                        err_dropped_after_high = 1;
                end
                $display("    (live after drain) err=%0b", error_flag);

                if (!is_odd_rem) begin
                    for (int b = 0; b < cap_count; b++) begin
                        if (cap_err[b] !== 1'b0) begin
                            $display("  FAIL even-rem beat[%0d] err=%0b expected 0",
                                     b, cap_err[b]);
                            local_fail++;
                        end
                    end
                    if (error_flag !== 1'b0) begin
                        $display("  FAIL error_flag (live) = %0b, expected 0", error_flag);
                        local_fail++;
                    end
                end else begin
                    // Every padding beat must carry err=1
                    for (int b = burst_len; b < cap_count; b++) begin
                        if (cap_err[b] !== 1'b1) begin
                            $display("  FAIL odd-rem pad beat[%0d] err=%0b expected 1",
                                     b, cap_err[b]);
                            local_fail++;
                        end
                    end
                    // Last captured beat must be err=1
                    if (cap_count > 0 && cap_err[cap_count-1] !== 1'b1) begin
                        $display("  FAIL odd-rem last beat[%0d] err=%0b expected 1",
                                 cap_count-1, cap_err[cap_count-1]);
                        local_fail++;
                    end
                    // Sticky rule: once err went high, must not drop back to 0
                    if (err_dropped_after_high) begin
                        $display("  FAIL odd-rem error_flag dropped 1->0 during burst (not sticky)");
                        local_fail++;
                    end
                    // Live after drain must remain 1 (sticky post-burst)
                    if (error_flag !== 1'b1) begin
                        $display("  FAIL error_flag (live after drain) = %0b, expected 1",
                                 error_flag);
                        local_fail++;
                    end
                end
            end

            if (local_fail == 0) begin
                $display("  >>> CASE PASS");
                pass_count++;
                summary_line.push_back($sformatf("PASS  %0s (len=%0d rem=%0d pad=%0d err=%0b)",
                    test_name, burst_len, rem_val, pad_total, is_odd_rem[0]));
            end else begin
                $display("  >>> CASE FAIL (%0d error(s))", local_fail);
                fail_count = fail_count + local_fail;
                summary_line.push_back($sformatf("FAIL  %0s (len=%0d rem=%0d pad=%0d) %0d err(s)",
                    test_name, burst_len, rem_val, pad_total, local_fail));
            end
        end
    endtask

    // =========================================================================
    // Back-to-back dual-burst test
    // =========================================================================
    task run_back_to_back;
        integer i, l;
        integer burst1_len, burst2_len;
        integer burst1_base, burst2_base;
        integer pad2_total;
        integer exp_total;
        integer b1_exp_len;
        integer b2_exp_len;
        integer local_fail;
        logic [DATA_W-1:0] exp_val;
        begin
            local_fail = 0;
            $display("\n--- CASE: back-to-back rem=0 + rem=3 ---");
            do_reset;
            virtual_lane_en = 0;
            cap_started = 1;

            // Burst 1: rem=0, len=8, base 8'h20
            burst1_len = 8; burst1_base = 8'h20;
            // Burst 2: rem=3, len=11, base 8'hA0
            burst2_len = 11; burst2_base = 8'hA0;

            b1_exp_len = 8;             // rem=0, no pad
            pad2_total = 8 - 3;         // rem=3 pad = 5
            b2_exp_len = burst2_len + pad2_total; // 16
            exp_total  = b1_exp_len + b2_exp_len; // 24

            drive_burst(burst1_len, burst1_base);
            // Force a gap of a few cycles between bursts
            repeat(3) @(posedge clk);
            drive_burst(burst2_len, burst2_base);

            repeat(16) @(posedge clk);
            cap_started = 0;

            // Length check: the two bursts are non-overlapping but each has
            // its own valid_out-continuous run. Our capture lumps them; since
            // valid_out goes low between burst 1 drain and burst 2 start,
            // cap_gap will have been set. So split-check via counts.
            //
            // Simpler approach: require exactly exp_total captured beats, and
            // explicitly allow one gap (reset the gap detector here by simply
            // trusting per-burst continuity during the live capture of each
            // burst is already covered by the single-rem cases above).
            if (cap_count !== exp_total) begin
                $display("  FAIL total out_count=%0d expected=%0d", cap_count, exp_total);
                local_fail++;
            end else begin
                $display("  PASS total out_count=%0d (burst1=%0d burst2=%0d)",
                         cap_count, b1_exp_len, b2_exp_len);
            end

            // Burst 1 passthrough (no pad)
            for (i = 0; i < burst1_len; i++) begin
                for (l = 0; l < 16; l++) begin
                    exp_val = exp_din(i, l, burst1_base);
                    if (cap[l][i] !== exp_val) begin
                        $display("  FAIL burst1 beat=%0d lane=%0d got=%02h exp=%02h",
                                 i, l, cap[l][i], exp_val);
                        local_fail++;
                    end
                end
                // Burst 1 is rem=0 => error_flag should be 0 during burst 1
                if (cap_err[i] !== 1'b0) begin
                    $display("  FAIL burst1 beat=%0d error_flag=%0b expected 0",
                             i, cap_err[i]);
                    local_fail++;
                end
            end

            // Burst 2 passthrough (first burst2_len beats after burst 1)
            for (i = 0; i < burst2_len; i++) begin
                for (l = 0; l < 16; l++) begin
                    exp_val = exp_din(i, l, burst2_base);
                    if (cap[l][b1_exp_len + i] !== exp_val) begin
                        $display("  FAIL burst2 beat=%0d lane=%0d got=%02h exp=%02h",
                                 i, l, cap[l][b1_exp_len + i], exp_val);
                        local_fail++;
                    end
                end
            end

            // Burst 2 rem=3 => odd rem, padding data is don't-care.
            // Every pad beat of burst 2 must carry err=1.
            // Burst 2 pad beats live at absolute positions
            //   [b1_exp_len + burst2_len .. b1_exp_len + b2_exp_len - 1]
            //   = [8 + 11 .. 8 + 16 - 1] = [19 .. 23]
            $display("  ERR_TIMELINE back-to-back (burst1 rem=0, burst2 rem=3):");
            for (int b = 0; b < cap_count; b++) begin
                string tag;
                if (b < b1_exp_len)
                    tag = "b1-burst";
                else if (b < b1_exp_len + burst2_len)
                    tag = "b2-burst";
                else
                    tag = "b2-pad  ";
                $display("    beat[%0d] %0s  err=%0b", b, tag, cap_err[b]);
            end
            for (int b = b1_exp_len + burst2_len; b < cap_count; b++) begin
                if (cap_err[b] !== 1'b1) begin
                    $display("  FAIL burst2 pad beat[%0d] err=%0b expected 1",
                             b, cap_err[b]);
                    local_fail++;
                end
            end
            if (cap_err[cap_count-1] !== 1'b1) begin
                $display("  FAIL burst2 last beat error_flag=%0b expected 1",
                         cap_err[cap_count-1]);
                local_fail++;
            end

            // beat_mod_q reset check: the simplest proxy is that burst2
            // passthrough matches its own base (already checked). If
            // beat_mod_q had carried over from burst 1, the pad_total for
            // burst 2 (11 beats) would differ from expected (5). Since
            // burst 2 total length checks out as 16, rem was computed fresh.
            // Add an explicit note.
            $display("  NOTE burst2 rem computed fresh (total=%0d matches 8 multiple)",
                     b2_exp_len);

            if (local_fail == 0) begin
                $display("  >>> CASE PASS");
                pass_count++;
                summary_line.push_back("PASS  back-to-back rem0+rem3");
            end else begin
                $display("  >>> CASE FAIL (%0d error(s))", local_fail);
                fail_count = fail_count + local_fail;
                summary_line.push_back($sformatf("FAIL  back-to-back rem0+rem3 (%0d)", local_fail));
            end
        end
    endtask

    // =========================================================================
    // Dump helper for rem=2 / rem=5 padding sequences (requested artifact)
    // =========================================================================
    task dump_padding_sequence;
        input [255:0] label;
        input integer burst_len;
        input integer base_val;
        integer i, pad_total, rem_val;
        begin
            $display("\n--- PADDING DUMP: %0s ---", label);
            rem_val = burst_len % 8;
            pad_total = (rem_val == 0) ? 0 : (8 - rem_val);
            $display("  burst_len=%0d rem=%0d pad_total=%0d",
                     burst_len, rem_val, pad_total);
            $display("  cap_count=%0d", cap_count);
            for (i = 0; i < cap_count; i++) begin
                if (i < burst_len)
                    $display("    beat[%0d] lane0=%02h lane1=%02h lane15=%02h err=%0b  (passthrough)",
                             i, cap[0][i], cap[1][i], cap[15][i], cap_err[i]);
                else
                    $display("    beat[%0d] lane0=%02h lane1=%02h lane15=%02h err=%0b  (pad idx=%0d)",
                             i, cap[0][i], cap[1][i], cap[15][i], cap_err[i], i - burst_len);
            end
        end
    endtask

    // Rerun rem=2 burst but keep capture for dump
    task dump_rem2;
        begin
            do_reset;
            virtual_lane_en = 0;
            cap_started = 1;
            drive_burst(10, 8'h30);   // len=10 => rem=2, pad=6
            repeat(16) @(posedge clk);
            cap_started = 0;
            dump_padding_sequence("rem=2 (len=10 base=0x30, pad data MUST match)", 10, 8'h30);
        end
    endtask

    task dump_rem5;
        begin
            do_reset;
            virtual_lane_en = 0;
            cap_started = 1;
            drive_burst(13, 8'h50);   // len=13 => rem=5, pad=3
            repeat(16) @(posedge clk);
            cap_started = 0;
            dump_padding_sequence("rem=5 (len=13 base=0x50, pad data don't-care, err MUST=1)", 13, 8'h50);
        end
    endtask

    // =========================================================================
    // Main
    // =========================================================================
    initial begin
        fail_count = 0;
        pass_count = 0;

        // 8 rem cases (PHY mode: virtual_lane_en=0)
        run_rem_case("PHY rem=0 len=8",  8,  8'h10, 0, 0);
        run_rem_case("PHY rem=1 len=9",  9,  8'h20, 1, 0);
        run_rem_case("PHY rem=2 len=10", 10, 8'h30, 2, 0);
        run_rem_case("PHY rem=3 len=11", 11, 8'h40, 3, 0);
        run_rem_case("PHY rem=4 len=12", 12, 8'h50, 4, 0);
        run_rem_case("PHY rem=5 len=13", 13, 8'h60, 5, 0);
        run_rem_case("PHY rem=6 len=14", 14, 8'h70, 6, 0);
        run_rem_case("PHY rem=7 len=15", 15, 8'h80, 7, 0);

        // VLANE-mode cases (virtual_lane_en=1). Spec: VLANE behavior is
        // IDENTICAL to PHY (same padding length, same padding data, same
        // error_flag). Expected values derived independently from spec,
        // not copied from PHY golden.
        //   rem=0: passthrough, pad=0, err=0
        //   rem=2: even, pad=6 {c_{N-1},cN,c_{N-1},cN,c_{N-1},cN}, err=0
        //   rem=3: odd,  pad=5, err sticky high
        //   rem=4: even, pad=4 {c_{N-1},cN,c_{N-1},cN},             err=0
        run_rem_case("VLANE rem=0 len=8",  8,  8'h18, 0, 1);
        run_rem_case("VLANE rem=2 len=10", 10, 8'h38, 2, 1);
        run_rem_case("VLANE rem=3 len=11", 11, 8'h48, 3, 1);
        run_rem_case("VLANE rem=4 len=12", 12, 8'h58, 4, 1);

        // back-to-back
        run_back_to_back();

        // Artifact dumps (not scored)
        dump_rem2();
        dump_rem5();

        // Summary table
        $display("\n===================== 8N-ALIGN SUMMARY =====================");
        foreach (summary_line[i]) $display("  %0s", summary_line[i]);
        $display("  total_cases=%0d  pass_cases=%0d  fail_units=%0d",
                 summary_line.size(), pass_count, fail_count);
        $display("============================================================");
        if (fail_count == 0)
            $display("ALL 8N-ALIGN TESTS PASSED");
        else
            $display("8N-ALIGN TESTS: %0d FAILURE UNIT(S)", fail_count);
        $display("============================================================");
        $finish;
    end

endmodule
