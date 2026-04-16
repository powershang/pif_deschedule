`timescale 1ns/1ps

// =============================================================================
// Testbench: tb_8n_align
// DUT: lanedata_8n_align_process
//
// Scope:
//   8N-mode (align_mode=1): 8 rem cases (rem 0..7)
//   4N-mode (align_mode=0): 6 cases (rem4 0/2 normal + rem4 1/3 error)
//   1 back-to-back cross-mode case
//   Total: 15 cases
//
// Golden derived independently from spec (not from RTL).
//
// Checks per case:
//   - Length correctness (8N or 4N padding + phase2)
//   - Data bit-exact (passthrough + padding pattern Cn,Cn+1 from chunk start)
//   - 4N-mode phase2: all-zero check per lane per beat
//   - error_flag per-beat timeline (sticky semantics)
//   - No valid_out gap within a burst
//
// Stimulus rule:
//   din[lane] at beat i = (base_val + i*16 + lane) & 0xFF
// =============================================================================

module tb_8n_align;

    parameter DATA_W = 8;
    parameter CLK_HALF = 5;

    logic              clk, rst_n;
    logic              valid_in, virtual_lane_en;
    logic              align_mode;  // 0 = 4N-align, 1 = 8N-align
    logic [DATA_W-1:0] din  [0:15];
    logic [DATA_W-1:0] dout [0:15];
    logic              valid_out;
    logic              error_flag;

    lanedata_8n_align_process #(.DATA_W(DATA_W)) dut (
        .clk(clk), .rst_n(rst_n),
        .valid_in(valid_in), .virtual_lane_en(virtual_lane_en),
        .align_mode(align_mode),
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

    // iverilog VCD dump
    initial begin
        $dumpfile("wave_8n_align.vcd");
        $dumpvars(0, tb_8n_align);
    end

    // ncverilog FSDB dump (ignored by iverilog)
    `ifdef FSDB_ON
    initial begin
        $fsdbDumpfile("wave_8n_align.fsdb");
        $fsdbDumpvars(0, tb_8n_align, "+all");
    end
    `endif

    // =========================================================================
    // Output capture (all 16 lanes)
    // =========================================================================
    integer            cap_count;
    reg [DATA_W-1:0]   cap[0:15][0:255];
    reg                cap_err[0:255];
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
            align_mode = 1;  // default 8N-mode
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
    // Golden: compute expected output value for any beat index
    // =========================================================================
    // Returns expected data for output beat_idx, lane l, given burst parameters.
    // For "don't care" regions (odd rem padding), returns -1 to signal skip.
    function automatic integer golden_beat;
        input integer beat_idx;
        input integer l;
        input integer burst_len;
        input integer base_val;
        input integer amode;  // 0=4N, 1=8N
        integer rem8, rem4, chunk_start, pad_idx, src_beat;
        integer pad_phase1, phase1_end;
        begin
            if (beat_idx < burst_len) begin
                // Passthrough region
                golden_beat = exp_din(beat_idx, l, base_val);
            end else if (amode == 1) begin
                // 8N-mode padding
                rem8 = burst_len % 8;
                if (rem8 == 0) begin
                    golden_beat = -1; // should not reach here
                end else if (rem8[0]) begin
                    // Odd rem: don't care
                    golden_beat = -1;
                end else begin
                    // Even rem: replay Cn, Cn+1 from chunk start
                    chunk_start = burst_len - rem8;
                    pad_idx = beat_idx - burst_len;
                    src_beat = chunk_start + (pad_idx % 2);
                    golden_beat = exp_din(src_beat, l, base_val);
                end
            end else begin
                // 4N-mode
                rem4 = burst_len % 4;
                pad_phase1 = (rem4 == 0) ? 0 : (4 - rem4);
                phase1_end = burst_len + pad_phase1;

                if (rem4[0]) begin
                    // Odd rem4: phase1 is don't-care, phase2 is zero
                    if (beat_idx < phase1_end) begin
                        golden_beat = -1;  // don't care
                    end else begin
                        golden_beat = 0;   // phase2 all zero
                    end
                end else if (beat_idx < phase1_end) begin
                    // Phase 1: replay Cn, Cn+1 from 4-beat chunk start
                    chunk_start = burst_len - rem4;
                    pad_idx = beat_idx - burst_len;
                    src_beat = chunk_start + (pad_idx % 2);
                    golden_beat = exp_din(src_beat, l, base_val);
                end else begin
                    // Phase 2: all zero
                    golden_beat = 0;
                end
            end
        end
    endfunction

    // =========================================================================
    // Compute expected output length
    // =========================================================================
    function automatic integer expected_out_len;
        input integer burst_len;
        input integer amode;
        integer rem8, rem4, pad8, pad_phase1;
        begin
            if (amode == 1) begin
                rem8 = burst_len % 8;
                pad8 = (rem8 == 0) ? 0 : (8 - rem8);
                expected_out_len = burst_len + pad8;
            end else begin
                rem4 = burst_len % 4;
                pad_phase1 = (rem4 == 0) ? 0 : (4 - rem4);
                expected_out_len = burst_len + pad_phase1 + 4;  // phase1 + phase2(4 zero)
            end
        end
    endfunction

    // =========================================================================
    // Single burst test (supports both 8N and 4N modes)
    // =========================================================================
    task run_rem_case;
        input [255:0]  test_name;
        input integer  burst_len;
        input integer  base_val;
        input integer  amode;        // 0=4N, 1=8N
        input integer  vlane_en;     // 0=PHY, 1=VLANE
        integer i, l;
        integer exp_out_len;
        integer is_odd_rem;
        integer rem_val;
        integer rem4_val;
        integer pad_phase1;
        integer phase1_end;
        integer golden_val;
        logic [DATA_W-1:0] exp_val;
        integer pass_this_case;
        integer local_fail;
        begin
            local_fail = 0;
            $display("\n--- CASE: %0s (align_mode=%0d vlane=%0d) ---", test_name, amode, vlane_en);
            do_reset;
            align_mode = amode[0];
            virtual_lane_en = vlane_en[0];
            cap_started = 1;

            drive_burst(burst_len, base_val);

            repeat(20) @(posedge clk);
            cap_started = 0;

            exp_out_len = expected_out_len(burst_len, amode);

            // Determine if this is an odd-rem (error) case
            if (amode == 1) begin
                rem_val = burst_len % 8;
                is_odd_rem = rem_val[0];
            end else begin
                rem4_val = burst_len % 4;
                is_odd_rem = rem4_val[0];
            end

            // Check 1: length
            if (cap_count !== exp_out_len) begin
                $display("  FAIL out_count=%0d expected=%0d", cap_count, exp_out_len);
                local_fail++;
            end else begin
                $display("  PASS out_count=%0d (burst=%0d total_pad=%0d)",
                         cap_count, burst_len, exp_out_len - burst_len);
            end

            // Check 2: no gap
            if (cap_gap) begin
                $display("  FAIL valid_out had gap");
                local_fail++;
            end

            // Check 3: data check (passthrough + padding) using golden function
            for (i = 0; i < cap_count; i++) begin
                for (l = 0; l < 16; l++) begin
                    golden_val = golden_beat(i, l, burst_len, base_val, amode);
                    if (golden_val == -1) begin
                        // Don't care region, skip
                    end else begin
                        exp_val = golden_val[DATA_W-1:0];
                        if (cap[l][i] !== exp_val) begin
                            // Determine region label for debug
                            if (i < burst_len)
                                $display("  FAIL passthrough beat=%0d lane=%0d got=%02h exp=%02h",
                                         i, l, cap[l][i], exp_val);
                            else if (amode == 0 && golden_val == 0) begin
                                // Could be phase1-zero or phase2-zero; check which
                                rem4_val = burst_len % 4;
                                pad_phase1 = (rem4_val == 0) ? 0 : (4 - rem4_val);
                                phase1_end = burst_len + pad_phase1;
                                if (i >= phase1_end)
                                    $display("  FAIL phase2-zero beat=%0d lane=%0d got=%02h exp=00",
                                             i, l, cap[l][i]);
                                else
                                    $display("  FAIL phase1-pad beat=%0d lane=%0d got=%02h exp=%02h",
                                             i, l, cap[l][i], exp_val);
                            end else
                                $display("  FAIL pad beat=%0d lane=%0d got=%02h exp=%02h",
                                         i, l, cap[l][i], exp_val);
                            local_fail++;
                        end
                    end
                end
            end

            // Check 4: 4N-mode phase2 explicit all-zero check (even if golden already covers it)
            if (amode == 0) begin
                rem4_val = burst_len % 4;
                pad_phase1 = (rem4_val == 0) ? 0 : (4 - rem4_val);
                phase1_end = burst_len + pad_phase1;
                $display("  4N-mode: phase1_end=%0d phase2=[%0d..%0d]",
                         phase1_end, phase1_end, exp_out_len - 1);
                for (i = phase1_end; i < cap_count; i++) begin
                    for (l = 0; l < 16; l++) begin
                        if (cap[l][i] !== {DATA_W{1'b0}}) begin
                            $display("  FAIL phase2-zero beat=%0d lane=%0d got=%02h (must be 0x00)",
                                     i, l, cap[l][i]);
                            local_fail++;
                        end
                    end
                end
                // Verify phase2 is exactly 4 beats
                if (cap_count > phase1_end) begin
                    if ((cap_count - phase1_end) !== 4) begin
                        $display("  FAIL phase2 length=%0d expected=4",
                                 cap_count - phase1_end);
                        local_fail++;
                    end
                end
            end

            // Check 5: error_flag per-beat timeline
            begin : err_flag_check
                integer saw_err_high;
                integer err_dropped_after_high;
                string  tag;
                saw_err_high = 0;
                err_dropped_after_high = 0;

                $display("  ERR_TIMELINE %0s (odd_rem=%0d expected=%0s):",
                         test_name, is_odd_rem, is_odd_rem ? "ODD->1" : "EVEN->0");
                for (int b = 0; b < cap_count; b++) begin
                    if (b < burst_len)
                        tag = "burst";
                    else if (amode == 0) begin
                        rem4_val = burst_len % 4;
                        pad_phase1 = (rem4_val == 0) ? 0 : (4 - rem4_val);
                        phase1_end = burst_len + pad_phase1;
                        if (b < phase1_end)
                            tag = "ph1  ";
                        else
                            tag = "ph2  ";
                    end else
                        tag = "pad  ";
                    $display("    beat[%0d] %0s  err=%0b", b, tag, cap_err[b]);
                    if (cap_err[b] === 1'b1) saw_err_high = 1;
                    else if (saw_err_high && cap_err[b] === 1'b0)
                        err_dropped_after_high = 1;
                end
                $display("    (live after drain) err=%0b", error_flag);

                if (!is_odd_rem) begin
                    // Even rem: error_flag must be 0 on every beat
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
                    // Odd rem: error_flag must be 1 on every padding beat (both phases for 4N)
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
                    // Sticky rule
                    if (err_dropped_after_high) begin
                        $display("  FAIL odd-rem error_flag dropped 1->0 during burst (not sticky)");
                        local_fail++;
                    end
                    // Live after drain must remain 1
                    if (error_flag !== 1'b1) begin
                        $display("  FAIL error_flag (live after drain) = %0b, expected 1",
                                 error_flag);
                        local_fail++;
                    end
                end
            end

            // Summary
            if (local_fail == 0) begin
                integer pad_total;
                pad_total = exp_out_len - burst_len;
                $display("  >>> CASE PASS");
                pass_count++;
                summary_line.push_back($sformatf("PASS  %0s (len=%0d pad=%0d err=%0b)",
                    test_name, burst_len, pad_total, is_odd_rem[0]));
            end else begin
                $display("  >>> CASE FAIL (%0d error(s))", local_fail);
                fail_count = fail_count + local_fail;
                summary_line.push_back($sformatf("FAIL  %0s (len=%0d) %0d err(s)",
                    test_name, burst_len, local_fail));
            end
        end
    endtask

    // =========================================================================
    // Back-to-back cross-mode test: 8N rem=0 len=8 -> gap -> 4N rem4=2 len=6
    // =========================================================================
    task run_back_to_back;
        integer i, l;
        integer burst1_len, burst2_len;
        integer burst1_base, burst2_base;
        integer burst1_mode, burst2_mode;
        integer b1_exp_len, b2_exp_len;
        integer exp_total;
        integer local_fail;
        integer golden_val;
        logic [DATA_W-1:0] exp_val;
        integer rem4_val, pad_phase1, phase1_end;
        begin
            local_fail = 0;
            $display("\n--- CASE: back-to-back 8N-rem0 + 4N-rem2 ---");
            do_reset;
            cap_started = 1;

            // Burst 1: 8N-mode, rem=0, len=8, base 0x20
            burst1_len = 8; burst1_base = 8'h20; burst1_mode = 1;
            b1_exp_len = expected_out_len(burst1_len, burst1_mode);  // 8

            // Burst 2: 4N-mode, rem4=2, len=6, base 0xA0
            burst2_len = 6; burst2_base = 8'hA0; burst2_mode = 0;
            b2_exp_len = expected_out_len(burst2_len, burst2_mode);  // 6+2+4=12

            exp_total = b1_exp_len + b2_exp_len;  // 8+12=20

            // Drive burst 1 in 8N-mode
            align_mode = 1;
            drive_burst(burst1_len, burst1_base);

            // Gap between bursts
            repeat(3) @(posedge clk);

            // Drive burst 2 in 4N-mode
            align_mode = 0;
            drive_burst(burst2_len, burst2_base);

            repeat(20) @(posedge clk);
            cap_started = 0;

            // Length check
            if (cap_count !== exp_total) begin
                $display("  FAIL total out_count=%0d expected=%0d", cap_count, exp_total);
                local_fail++;
            end else begin
                $display("  PASS total out_count=%0d (burst1=%0d burst2=%0d)",
                         cap_count, b1_exp_len, b2_exp_len);
            end

            // Burst 1 data check (8N, rem=0, passthrough only)
            for (i = 0; i < burst1_len && i < cap_count; i++) begin
                for (l = 0; l < 16; l++) begin
                    golden_val = golden_beat(i, l, burst1_len, burst1_base, burst1_mode);
                    if (golden_val != -1) begin
                        exp_val = golden_val[DATA_W-1:0];
                        if (cap[l][i] !== exp_val) begin
                            $display("  FAIL burst1 beat=%0d lane=%0d got=%02h exp=%02h",
                                     i, l, cap[l][i], exp_val);
                            local_fail++;
                        end
                    end
                end
                // Burst 1 rem=0 => error_flag should be 0
                if (cap_err[i] !== 1'b0) begin
                    $display("  FAIL burst1 beat=%0d error_flag=%0b expected 0",
                             i, cap_err[i]);
                    local_fail++;
                end
            end

            // Burst 2 data check (4N, rem4=2)
            // Burst 2 output lives at positions [b1_exp_len .. b1_exp_len + b2_exp_len - 1]
            for (i = 0; i < b2_exp_len && (b1_exp_len + i) < cap_count; i++) begin
                for (l = 0; l < 16; l++) begin
                    golden_val = golden_beat(i, l, burst2_len, burst2_base, burst2_mode);
                    if (golden_val != -1) begin
                        exp_val = golden_val[DATA_W-1:0];
                        if (cap[l][b1_exp_len + i] !== exp_val) begin
                            $display("  FAIL burst2 beat=%0d lane=%0d got=%02h exp=%02h",
                                     i, l, cap[l][b1_exp_len + i], exp_val);
                            local_fail++;
                        end
                    end
                end
            end

            // Burst 2 phase2 all-zero explicit check
            rem4_val = burst2_len % 4;  // 6%4=2
            pad_phase1 = (rem4_val == 0) ? 0 : (4 - rem4_val);  // 2
            phase1_end = burst2_len + pad_phase1;  // 8
            for (i = phase1_end; i < b2_exp_len; i++) begin
                for (l = 0; l < 16; l++) begin
                    if (cap[l][b1_exp_len + i] !== {DATA_W{1'b0}}) begin
                        $display("  FAIL burst2 phase2-zero beat=%0d lane=%0d got=%02h",
                                 i, l, cap[l][b1_exp_len + i]);
                        local_fail++;
                    end
                end
            end

            // Burst 2 error_flag: rem4=2 (even) => err must be 0 on all burst2 beats
            for (i = 0; i < b2_exp_len && (b1_exp_len + i) < cap_count; i++) begin
                if (cap_err[b1_exp_len + i] !== 1'b0) begin
                    $display("  FAIL burst2 beat=%0d error_flag=%0b expected 0",
                             i, cap_err[b1_exp_len + i]);
                    local_fail++;
                end
            end

            // ERR timeline dump
            $display("  ERR_TIMELINE back-to-back (burst1 8N-rem0, burst2 4N-rem2):");
            for (int b = 0; b < cap_count; b++) begin
                string tag;
                if (b < b1_exp_len)
                    tag = "b1-burst";
                else if (b < b1_exp_len + burst2_len)
                    tag = "b2-burst";
                else if (b < b1_exp_len + phase1_end)
                    tag = "b2-ph1  ";
                else
                    tag = "b2-ph2  ";
                $display("    beat[%0d] %0s  err=%0b", b, tag, cap_err[b]);
            end

            // Fresh burst reset: error_flag should have been cleared by burst2 rising edge
            $display("  NOTE burst2 fresh burst reset verified (error_flag=0 throughout burst2)");

            if (local_fail == 0) begin
                $display("  >>> CASE PASS");
                pass_count++;
                summary_line.push_back("PASS  back-to-back 8N-rem0 + 4N-rem2");
            end else begin
                $display("  >>> CASE FAIL (%0d error(s))", local_fail);
                fail_count = fail_count + local_fail;
                summary_line.push_back($sformatf("FAIL  back-to-back 8N-rem0+4N-rem2 (%0d)", local_fail));
            end
        end
    endtask

    // =========================================================================
    // Dump helper for padding sequences
    // =========================================================================
    task dump_padding_sequence;
        input [255:0] label;
        input integer burst_len;
        input integer base_val;
        input integer amode;
        integer i;
        begin
            $display("\n--- PADDING DUMP: %0s ---", label);
            $display("  burst_len=%0d align_mode=%0d cap_count=%0d",
                     burst_len, amode, cap_count);
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

    task dump_8n_rem2;
        begin
            do_reset;
            align_mode = 1;
            virtual_lane_en = 0;
            cap_started = 1;
            drive_burst(10, 8'h30);   // len=10 => rem=2, pad=6
            repeat(20) @(posedge clk);
            cap_started = 0;
            dump_padding_sequence("8N rem=2 (len=10 base=0x30)", 10, 8'h30, 1);
        end
    endtask

    task dump_4n_rem2;
        begin
            do_reset;
            align_mode = 0;
            virtual_lane_en = 0;
            cap_started = 1;
            drive_burst(6, 8'hB0);    // len=6 => rem4=2, phase1=2pad, phase2=4zero
            repeat(20) @(posedge clk);
            cap_started = 0;
            dump_padding_sequence("4N rem4=2 (len=6 base=0xB0)", 6, 8'hB0, 0);
        end
    endtask

    // =========================================================================
    // Main
    // =========================================================================
    initial begin
        fail_count = 0;
        pass_count = 0;

        // =====================================================================
        // 8N-mode cases (align_mode=1)
        // =====================================================================

        // =====================================================================
        // 8N-mode PHY cases (align_mode=1, vlane=0)
        // =====================================================================

        // TC1: 8N rem=0 len=8 — no pad
        run_rem_case("8N PHY rem=0 len=8",   8,  8'h10, 1, 0);

        // TC2: 8N rem=2 len=10 — pad 6 beat from Cn,Cn+1
        run_rem_case("8N PHY rem=2 len=10",  10, 8'h20, 1, 0);

        // TC3: 8N rem=4 len=12 — pad 4 beat
        run_rem_case("8N PHY rem=4 len=12",  12, 8'h30, 1, 0);

        // TC4: 8N rem=6 len=14 — pad 2 beat
        run_rem_case("8N PHY rem=6 len=14",  14, 8'h40, 1, 0);

        // TC5: 8N rem=1 len=9 — error, pad 7 don't care
        run_rem_case("8N PHY rem=1 len=9",   9,  8'h50, 1, 0);

        // TC6: 8N rem=3 len=11 — error, pad 5 don't care
        run_rem_case("8N PHY rem=3 len=11",  11, 8'h60, 1, 0);

        // TC7: 8N rem=5 len=13 — error, pad 3 don't care
        run_rem_case("8N PHY rem=5 len=13",  13, 8'h70, 1, 0);

        // TC8: 8N rem=7 len=15 — error, pad 1 don't care
        run_rem_case("8N PHY rem=7 len=15",  15, 8'h80, 1, 0);

        // =====================================================================
        // 8N-mode VLANE cases (align_mode=1, vlane=1)
        // Spec: VLANE behavior is IDENTICAL to PHY (virtual_lane_en is unused
        // wire). These cases verify the path is exercised with no side effects.
        // =====================================================================

        // TC9: 8N VLANE rem=0 len=8 — no pad
        run_rem_case("8N VLANE rem=0 len=8",  8,  8'h18, 1, 1);

        // TC10: 8N VLANE rem=2 len=10 — pad 6
        run_rem_case("8N VLANE rem=2 len=10", 10, 8'h28, 1, 1);

        // TC11: 8N VLANE rem=4 len=12 — pad 4
        run_rem_case("8N VLANE rem=4 len=12", 12, 8'h38, 1, 1);

        // TC12: 8N VLANE rem=6 len=14 — pad 2
        run_rem_case("8N VLANE rem=6 len=14", 14, 8'h48, 1, 1);

        // =====================================================================
        // 4N-mode PHY cases (align_mode=0, vlane=0)
        // =====================================================================

        // TC13: 4N PHY rem4=0 len=8 — phase1 0 pad + phase2 4 zero
        run_rem_case("4N PHY rem4=0 len=8",  8,  8'h90, 0, 0);

        // TC14: 4N PHY rem4=0 len=4 — phase1 0 pad + phase2 4 zero
        run_rem_case("4N PHY rem4=0 len=4",  4,  8'hA0, 0, 0);

        // TC15: 4N PHY rem4=2 len=6 — phase1 2 pad (Cn,Cn+1) + phase2 4 zero
        run_rem_case("4N PHY rem4=2 len=6",  6,  8'hB0, 0, 0);

        // TC16: 4N PHY rem4=2 len=10 — phase1 2 pad (Cn,Cn+1) + phase2 4 zero
        //       verifies second chunk's Cn is different from TC15
        run_rem_case("4N PHY rem4=2 len=10", 10, 8'hC0, 0, 0);

        // TC17: 4N PHY rem4=1 len=5 — error + phase1 3 don't care + phase2 4 zero
        run_rem_case("4N PHY rem4=1 len=5",  5,  8'hD0, 0, 0);

        // TC18: 4N PHY rem4=3 len=7 — error + phase1 1 don't care + phase2 4 zero
        run_rem_case("4N PHY rem4=3 len=7",  7,  8'hE0, 0, 0);

        // =====================================================================
        // 4N-mode VLANE cases (align_mode=0, vlane=1)
        // =====================================================================

        // TC19: 4N VLANE rem4=0 len=8 — phase1 0 + phase2 4 zero
        run_rem_case("4N VLANE rem4=0 len=8",  8,  8'h98, 0, 1);

        // TC20: 4N VLANE rem4=2 len=6 — phase1 2 pad + phase2 4 zero
        run_rem_case("4N VLANE rem4=2 len=6",  6,  8'hB8, 0, 1);

        // TC21: 4N VLANE rem4=1 len=5 — error + phase1 3 dc + phase2 4 zero
        run_rem_case("4N VLANE rem4=1 len=5",  5,  8'hD8, 0, 1);

        // TC22: 4N VLANE rem4=2 len=10 — phase1 2 pad + phase2 4 zero (2nd chunk)
        run_rem_case("4N VLANE rem4=2 len=10", 10, 8'hC8, 0, 1);

        // =====================================================================
        // Back-to-back cross-mode: 8N rem=0 len=8 -> gap -> 4N rem4=2 len=6
        // =====================================================================
        // TC15
        run_back_to_back();

        // =====================================================================
        // Artifact dumps (not scored)
        // =====================================================================
        dump_8n_rem2();
        dump_4n_rem2();

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
