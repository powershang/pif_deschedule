// =============================================================================
// Testbench: tb_loopback_desched_top
// End-to-end A-to-A verification + Compactor verification:
//   din[0:15] -> scheduler_top -> descheduler(Stage1) -> reverse_transpose
//             -> lane_compactor -> CHECK (3 layers: rev A / rev B / compactor)
//
// Architecture: Burst-aware Line Dumper + Post-sim Golden Compare
//   - A "line" = one continuous burst of valid data (valid high -> low = one line)
//   - Golden dumper:        stores scheduler_top input (per cycle, 16 lanes)
//   - Rev A/B dumper:       stores reverse_transpose output, compared vs golden_a/b
//   - Compactor dumper:     on clk_slow_div2, stores compactor output
//   - Compactor golden:     cycles {0,1,4,5,8,9,12,13,16,17,20,21} of the input
//                           (24 input cycles -> 12 compactor cycles, 4:2 compaction)
//
// Hierarchy:
//   u_sched_top : scheduler_top       (din[0:15] -> dout[0:3])
//   u_desched   : descheduler Stage1  (4-lane fast -> chunk output)
//   u_rev_a     : reverse_transpose   (Group A: lanes 0-7)
//   u_rev_b     : reverse_transpose   (Group B: lanes 8-15)
//   u_compact   : lane_compactor      (clk_in_fast=clk_slow, clk_out_slow=clk_slow_div2)
//
// Test matrix: 8 cases (4L/8L/12L/16L) x (PHY/VLANE).
// Each mode: 24 input cycles of per-lane-per-cycle data (single continuous burst).
// =============================================================================

`timescale 1ns/1ps

module tb_loopback_desched_top;

    localparam DATA_W        = 8;
    localparam CLK_FAST_HALF = 5;
    localparam NUM_CYCLES    = 24;

    // Line storage dimensions
    localparam MAX_LINES    = 8;    // max bursts per test
    localparam MAX_LINE_LEN = 32;   // max cycles per burst

    // =========================================================================
    // Clocks & reset
    // =========================================================================
    logic clk_fast, clk_slow, clk_slow_div2;
    logic rst_n;
    integer slow_half;

    initial clk_fast = 0;
    always #(CLK_FAST_HALF) clk_fast = ~clk_fast;

    initial begin
        clk_slow = 0;
        slow_half = CLK_FAST_HALF;
        #(CLK_FAST_HALF);
        forever #(slow_half) clk_slow = ~clk_slow;
    end

    // clk_slow_div2: toggles on every posedge of clk_slow -> period = 2 * clk_slow period.
    // Generated from the same "PLL" as clk_slow (deterministic edge alignment).
    initial clk_slow_div2 = 0;
    always @(posedge clk_slow) clk_slow_div2 <= ~clk_slow_div2;

    // =========================================================================
    // VCD dump
    // =========================================================================
    initial begin
        $dumpfile("wave_loopback_desched_top.vcd");
        $dumpvars(0, tb_loopback_desched_top);
    end

    // =========================================================================
    // Signals
    // =========================================================================
    logic [1:0]        lane_mode;
    logic              virtual_lane_en;
    logic              valid_in;
    logic [DATA_W-1:0] din0,  din1,  din2,  din3;
    logic [DATA_W-1:0] din4,  din5,  din6,  din7;
    logic [DATA_W-1:0] din8,  din9,  din10, din11;
    logic [DATA_W-1:0] din12, din13, din14, din15;
    logic              align_error_flag;

    // scheduler_top -> descheduler
    logic              sched_valid_out;
    logic [DATA_W-1:0] sched_dout0, sched_dout1, sched_dout2, sched_dout3;
    logic [2:0]        sched_dbg_state;
    logic [3:0]        sched_dbg_fifo_cnt;

    // descheduler -> reverse transpose
    logic              ds_valid_out;
    logic [DATA_W-1:0] ds_a_top0, ds_a_top1, ds_a_top2, ds_a_top3;
    logic [DATA_W-1:0] ds_a_bot0, ds_a_bot1, ds_a_bot2, ds_a_bot3;
    logic [DATA_W-1:0] ds_b_top0, ds_b_top1, ds_b_top2, ds_b_top3;
    logic [DATA_W-1:0] ds_b_bot0, ds_b_bot1, ds_b_bot2, ds_b_bot3;
    logic [2:0]        ds_dbg_state;
    logic [3:0]        ds_dbg_fifo_cnt;

    // reverse transpose Group A outputs
    logic              rev_a_valid;
    logic [DATA_W-1:0] rev_a_d0, rev_a_d1, rev_a_d2, rev_a_d3;
    logic [DATA_W-1:0] rev_a_d4, rev_a_d5, rev_a_d6, rev_a_d7;

    // reverse transpose Group B outputs
    logic              rev_b_valid;
    logic [DATA_W-1:0] rev_b_d0, rev_b_d1, rev_b_d2, rev_b_d3;
    logic [DATA_W-1:0] rev_b_d4, rev_b_d5, rev_b_d6, rev_b_d7;

    // lane_cfg for reverse transpose
    wire rev_a_lane_cfg = (lane_mode == 2'b00) ? 1'b1 : 1'b0;  // LANE4 for 4L, LANE8 otherwise
    wire rev_b_lane_cfg = (lane_mode == 2'b11) ? 1'b0 : 1'b1;  // LANE8 for 16L, LANE4 otherwise
    wire rev_b_valid_in = ds_valid_out & lane_mode[1];           // only active for 12L/16L

    // =========================================================================
    // DUT: scheduler_top
    // =========================================================================
    inplace_transpose_buf_multi_lane_scheduler_top #(.DATA_W(DATA_W)) u_sched_top (
        .clk_in(clk_slow), .clk_out(clk_fast), .rst_n(rst_n),
        .valid_in(valid_in), .lane_mode(lane_mode), .virtual_lane_en(virtual_lane_en),
        .din0(din0),   .din1(din1),   .din2(din2),   .din3(din3),
        .din4(din4),   .din5(din5),   .din6(din6),   .din7(din7),
        .din8(din8),   .din9(din9),   .din10(din10), .din11(din11),
        .din12(din12), .din13(din13), .din14(din14), .din15(din15),
        .align_error_flag(align_error_flag),
        .valid_out(sched_valid_out),
        .dout0(sched_dout0), .dout1(sched_dout1),
        .dout2(sched_dout2), .dout3(sched_dout3),
        .dbg_state(sched_dbg_state), .dbg_fifo_cnt(sched_dbg_fifo_cnt)
    );

    // =========================================================================
    // DUT: descheduler Stage 1
    // =========================================================================
    inplace_transpose_buf_multi_lane_descheduler #(.DATA_W(DATA_W)) u_desched (
        .clk_in(clk_fast), .clk_out(clk_slow), .rst_n(rst_n),
        .lane_mode(lane_mode), .valid_in(sched_valid_out),
        .din0(sched_dout0), .din1(sched_dout1),
        .din2(sched_dout2), .din3(sched_dout3),
        .valid_out(ds_valid_out),
        .a_top0(ds_a_top0), .a_top1(ds_a_top1),
        .a_top2(ds_a_top2), .a_top3(ds_a_top3),
        .a_bot0(ds_a_bot0), .a_bot1(ds_a_bot1),
        .a_bot2(ds_a_bot2), .a_bot3(ds_a_bot3),
        .b_top0(ds_b_top0), .b_top1(ds_b_top1),
        .b_top2(ds_b_top2), .b_top3(ds_b_top3),
        .b_bot0(ds_b_bot0), .b_bot1(ds_b_bot1),
        .b_bot2(ds_b_bot2), .b_bot3(ds_b_bot3),
        .dbg_state(ds_dbg_state), .dbg_fifo_cnt(ds_dbg_fifo_cnt)
    );

    // =========================================================================
    // DUT: reverse_inplace_transpose Group A (lanes 0-7)
    // =========================================================================
    reverse_inplace_transpose #(.DATA_W(DATA_W)) u_rev_a (
        .clk(clk_slow), .rst_n(rst_n),
        .lane_cfg(rev_a_lane_cfg), .mode(virtual_lane_en), .valid_in(ds_valid_out),
        .din_top0(ds_a_top0), .din_top1(ds_a_top1),
        .din_top2(ds_a_top2), .din_top3(ds_a_top3),
        .din_bot0(ds_a_bot0), .din_bot1(ds_a_bot1),
        .din_bot2(ds_a_bot2), .din_bot3(ds_a_bot3),
        .valid_out(rev_a_valid),
        .dout0(rev_a_d0), .dout1(rev_a_d1), .dout2(rev_a_d2), .dout3(rev_a_d3),
        .dout4(rev_a_d4), .dout5(rev_a_d5), .dout6(rev_a_d6), .dout7(rev_a_d7)
    );

    // =========================================================================
    // DUT: reverse_inplace_transpose Group B (lanes 8-15)
    // =========================================================================
    reverse_inplace_transpose #(.DATA_W(DATA_W)) u_rev_b (
        .clk(clk_slow), .rst_n(rst_n),
        .lane_cfg(rev_b_lane_cfg), .mode(virtual_lane_en), .valid_in(rev_b_valid_in),
        .din_top0(ds_b_top0), .din_top1(ds_b_top1),
        .din_top2(ds_b_top2), .din_top3(ds_b_top3),
        .din_bot0(ds_b_bot0), .din_bot1(ds_b_bot1),
        .din_bot2(ds_b_bot2), .din_bot3(ds_b_bot3),
        .valid_out(rev_b_valid),
        .dout0(rev_b_d0), .dout1(rev_b_d1), .dout2(rev_b_d2), .dout3(rev_b_d3),
        .dout4(rev_b_d4), .dout5(rev_b_d5), .dout6(rev_b_d6), .dout7(rev_b_d7)
    );

    // =========================================================================
    // DUT: lane_compactor
    //   clk_in_fast  = clk_slow        (= rev_transpose domain, descheduler clk_out)
    //   clk_out_slow = clk_slow_div2   (clk_slow / 2)
    // Drives both Group A and Group B (B inputs are 0 for 4L/8L modes).
    // =========================================================================
    logic [15:0]       cmp_valid_out;
    logic [DATA_W-1:0] cmp_a_top0, cmp_a_top1, cmp_a_top2, cmp_a_top3;
    logic [DATA_W-1:0] cmp_a_bot0, cmp_a_bot1, cmp_a_bot2, cmp_a_bot3;
    logic [DATA_W-1:0] cmp_b_top0, cmp_b_top1, cmp_b_top2, cmp_b_top3;
    logic [DATA_W-1:0] cmp_b_bot0, cmp_b_bot1, cmp_b_bot2, cmp_b_bot3;

    // Per-lane length-limiter configuration, driven per test case.
    logic [12:0] lane_len_cfg [0:15];

    lane_compactor #(.DATA_W(DATA_W), .LEN_W(13)) u_compact (
        .clk_in_fast (clk_slow),
        .clk_out_slow(clk_slow_div2),
        .rst_n       (rst_n),
        .valid_in    (rev_a_valid),
        .a_top0_in(rev_a_d0), .a_top1_in(rev_a_d1), .a_top2_in(rev_a_d2), .a_top3_in(rev_a_d3),
        .a_bot0_in(rev_a_d4), .a_bot1_in(rev_a_d5), .a_bot2_in(rev_a_d6), .a_bot3_in(rev_a_d7),
        .b_top0_in(rev_b_d0), .b_top1_in(rev_b_d1), .b_top2_in(rev_b_d2), .b_top3_in(rev_b_d3),
        .b_bot0_in(rev_b_d4), .b_bot1_in(rev_b_d5), .b_bot2_in(rev_b_d6), .b_bot3_in(rev_b_d7),
        .lane_len_0 (lane_len_cfg[0]),  .lane_len_1 (lane_len_cfg[1]),
        .lane_len_2 (lane_len_cfg[2]),  .lane_len_3 (lane_len_cfg[3]),
        .lane_len_4 (lane_len_cfg[4]),  .lane_len_5 (lane_len_cfg[5]),
        .lane_len_6 (lane_len_cfg[6]),  .lane_len_7 (lane_len_cfg[7]),
        .lane_len_8 (lane_len_cfg[8]),  .lane_len_9 (lane_len_cfg[9]),
        .lane_len_10(lane_len_cfg[10]), .lane_len_11(lane_len_cfg[11]),
        .lane_len_12(lane_len_cfg[12]), .lane_len_13(lane_len_cfg[13]),
        .lane_len_14(lane_len_cfg[14]), .lane_len_15(lane_len_cfg[15]),
        .valid_out(cmp_valid_out),
        .a_top0(cmp_a_top0), .a_top1(cmp_a_top1), .a_top2(cmp_a_top2), .a_top3(cmp_a_top3),
        .a_bot0(cmp_a_bot0), .a_bot1(cmp_a_bot1), .a_bot2(cmp_a_bot2), .a_bot3(cmp_a_bot3),
        .b_top0(cmp_b_top0), .b_top1(cmp_b_top1), .b_top2(cmp_b_top2), .b_top3(cmp_b_top3),
        .b_bot0(cmp_b_bot0), .b_bot1(cmp_b_bot1), .b_bot2(cmp_b_bot2), .b_bot3(cmp_b_bot3)
    );

    // =========================================================================
    // Line-based golden arrays (input side)
    // Flat 2D for iverilog: [line * MAX_LINE_LEN + cyc][lane]
    // =========================================================================
    reg [DATA_W-1:0] golden_a [0:MAX_LINES*MAX_LINE_LEN-1][0:7];
    reg [DATA_W-1:0] golden_b [0:MAX_LINES*MAX_LINE_LEN-1][0:7];
    integer golden_line_cnt;
    integer golden_line_len [0:MAX_LINES-1];

    // =========================================================================
    // Line-based capture arrays (output side)
    // =========================================================================
    reg [DATA_W-1:0] cap_a [0:MAX_LINES*MAX_LINE_LEN-1][0:7];
    integer cap_a_line_cnt;
    integer cap_a_line_len [0:MAX_LINES-1];

    reg [DATA_W-1:0] cap_b [0:MAX_LINES*MAX_LINE_LEN-1][0:7];
    integer cap_b_line_cnt;
    integer cap_b_line_len [0:MAX_LINES-1];

    // Compactor capture arrays (16 lanes wide). cap_c_a = Group A (lanes 0-7),
    // cap_c_b = Group B (lanes 8-15). Compactor output runs on clk_slow_div2
    // and emits cycles { 0,1, 4,5, 8,9, 12,13, 16,17, 20,21 } of the source.
    //
    // cap_c_a/cap_c_b are indexed by [line*MAX_LINE_LEN + slow_cycle][lane]
    // and store the data bus on slow cycles where ANY lane was valid (the bus
    // is shared across lanes; per-lane valid gating is decoded separately).
    // cap_c_line_len[line] = total number of slow cycles captured in that line
    // (i.e. from first slow-cycle any lane is valid until last one).
    reg [DATA_W-1:0] cap_c_a [0:MAX_LINES*MAX_LINE_LEN-1][0:7];
    reg [DATA_W-1:0] cap_c_b [0:MAX_LINES*MAX_LINE_LEN-1][0:7];
    integer cap_c_line_cnt;
    integer cap_c_line_len [0:MAX_LINES-1];

    // Per-lane valid bit captured each slow cycle of the burst.
    // cap_c_lv[line*MAX_LINE_LEN + slow_cycle][lane] = 1/0.
    reg cap_c_lv [0:MAX_LINES*MAX_LINE_LEN-1][0:15];

    // Per-lane beat count (how many slow cycles valid_out[lane] was 1) for each line.
    integer cap_c_lane_cnt [0:MAX_LINES-1][0:15];

    // Compactor golden arrays — built post-facto from golden_a/golden_b by
    // picking cycles {0,1,4,5,8,9,12,13,16,17,20,21}.
    reg [DATA_W-1:0] gold_c_a [0:MAX_LINES*MAX_LINE_LEN-1][0:7];
    reg [DATA_W-1:0] gold_c_b [0:MAX_LINES*MAX_LINE_LEN-1][0:7];
    integer gold_c_line_len [0:MAX_LINES-1];

    // =========================================================================
    // Dumper control
    // =========================================================================
    integer dumper_en;

    // =========================================================================
    // Golden dumper (input side) - track valid_in rising/falling edges
    // =========================================================================
    reg prev_valid_in;
    integer g_line, g_cyc;

    always @(posedge clk_slow) begin
        if (rst_n && dumper_en) begin
            if (valid_in && !prev_valid_in) begin
                // Rising edge of valid_in: start new line
                g_line = golden_line_cnt;
                g_cyc = 0;
                golden_line_cnt = golden_line_cnt + 1;
            end
            if (valid_in) begin
                // Store this cycle's 16-lane data split into golden_a (lanes 0-7) and golden_b (lanes 8-15)
                golden_a[g_line * MAX_LINE_LEN + g_cyc][0] = din0;
                golden_a[g_line * MAX_LINE_LEN + g_cyc][1] = din1;
                golden_a[g_line * MAX_LINE_LEN + g_cyc][2] = din2;
                golden_a[g_line * MAX_LINE_LEN + g_cyc][3] = din3;
                golden_a[g_line * MAX_LINE_LEN + g_cyc][4] = din4;
                golden_a[g_line * MAX_LINE_LEN + g_cyc][5] = din5;
                golden_a[g_line * MAX_LINE_LEN + g_cyc][6] = din6;
                golden_a[g_line * MAX_LINE_LEN + g_cyc][7] = din7;

                golden_b[g_line * MAX_LINE_LEN + g_cyc][0] = din8;
                golden_b[g_line * MAX_LINE_LEN + g_cyc][1] = din9;
                golden_b[g_line * MAX_LINE_LEN + g_cyc][2] = din10;
                golden_b[g_line * MAX_LINE_LEN + g_cyc][3] = din11;
                golden_b[g_line * MAX_LINE_LEN + g_cyc][4] = din12;
                golden_b[g_line * MAX_LINE_LEN + g_cyc][5] = din13;
                golden_b[g_line * MAX_LINE_LEN + g_cyc][6] = din14;
                golden_b[g_line * MAX_LINE_LEN + g_cyc][7] = din15;

                golden_line_len[g_line] = g_cyc + 1;
                g_cyc = g_cyc + 1;
            end
            prev_valid_in = valid_in;
        end
    end

    // =========================================================================
    // DUT dumper Group A (output side) - track rev_a_valid rising/falling edges
    // =========================================================================
    reg prev_rev_a_valid;
    integer ca_line, ca_cyc;

    always @(posedge clk_slow) begin
        if (rst_n && dumper_en) begin
            if (rev_a_valid && !prev_rev_a_valid) begin
                // Rising edge: new output line
                ca_line = cap_a_line_cnt;
                ca_cyc = 0;
                cap_a_line_cnt = cap_a_line_cnt + 1;
            end
            if (rev_a_valid) begin
                cap_a[ca_line * MAX_LINE_LEN + ca_cyc][0] = rev_a_d0;
                cap_a[ca_line * MAX_LINE_LEN + ca_cyc][1] = rev_a_d1;
                cap_a[ca_line * MAX_LINE_LEN + ca_cyc][2] = rev_a_d2;
                cap_a[ca_line * MAX_LINE_LEN + ca_cyc][3] = rev_a_d3;
                cap_a[ca_line * MAX_LINE_LEN + ca_cyc][4] = rev_a_d4;
                cap_a[ca_line * MAX_LINE_LEN + ca_cyc][5] = rev_a_d5;
                cap_a[ca_line * MAX_LINE_LEN + ca_cyc][6] = rev_a_d6;
                cap_a[ca_line * MAX_LINE_LEN + ca_cyc][7] = rev_a_d7;

                cap_a_line_len[ca_line] = ca_cyc + 1;
                ca_cyc = ca_cyc + 1;
            end
            prev_rev_a_valid = rev_a_valid;
        end
    end

    // =========================================================================
    // DUT dumper Group B (output side) - track rev_b_valid rising/falling edges
    // =========================================================================
    reg prev_rev_b_valid;
    integer cb_line, cb_cyc;

    always @(posedge clk_slow) begin
        if (rst_n && dumper_en && lane_mode[1]) begin
            if (rev_b_valid && !prev_rev_b_valid) begin
                // Rising edge: new output line
                cb_line = cap_b_line_cnt;
                cb_cyc = 0;
                cap_b_line_cnt = cap_b_line_cnt + 1;
            end
            if (rev_b_valid) begin
                cap_b[cb_line * MAX_LINE_LEN + cb_cyc][0] = rev_b_d0;
                cap_b[cb_line * MAX_LINE_LEN + cb_cyc][1] = rev_b_d1;
                cap_b[cb_line * MAX_LINE_LEN + cb_cyc][2] = rev_b_d2;
                cap_b[cb_line * MAX_LINE_LEN + cb_cyc][3] = rev_b_d3;
                cap_b[cb_line * MAX_LINE_LEN + cb_cyc][4] = rev_b_d4;
                cap_b[cb_line * MAX_LINE_LEN + cb_cyc][5] = rev_b_d5;
                cap_b[cb_line * MAX_LINE_LEN + cb_cyc][6] = rev_b_d6;
                cap_b[cb_line * MAX_LINE_LEN + cb_cyc][7] = rev_b_d7;

                cap_b_line_len[cb_line] = cb_cyc + 1;
                cb_cyc = cb_cyc + 1;
            end
            prev_rev_b_valid = rev_b_valid;
        end
    end

    // =========================================================================
    // Compactor dumper (clk_slow_div2 domain)
    // RTL contract (post beat-counter fix): valid_out only asserts after
    // reg_a has been committed, so the very first beat of each burst is
    // real data. No skip/offset workaround — every beat from the rising
    // edge of cmp_valid_out is captured verbatim.
    // =========================================================================
    reg prev_cmp_any_valid;
    integer cc_line, cc_cyc;
    wire cmp_any_valid = |cmp_valid_out;
    integer cc_lane_i;

    always @(posedge clk_slow_div2) begin
        if (rst_n && dumper_en) begin
            if (cmp_any_valid && !prev_cmp_any_valid) begin
                cc_line = cap_c_line_cnt;
                cc_cyc  = 0;
                cap_c_line_cnt = cap_c_line_cnt + 1;
                // zero per-lane counts for this new line
                for (cc_lane_i = 0; cc_lane_i < 16; cc_lane_i = cc_lane_i + 1)
                    cap_c_lane_cnt[cc_line][cc_lane_i] = 0;
            end
            if (cmp_any_valid) begin
                // Group A (lanes 0..7)
                cap_c_a[cc_line * MAX_LINE_LEN + cc_cyc][0] = cmp_a_top0;
                cap_c_a[cc_line * MAX_LINE_LEN + cc_cyc][1] = cmp_a_top1;
                cap_c_a[cc_line * MAX_LINE_LEN + cc_cyc][2] = cmp_a_top2;
                cap_c_a[cc_line * MAX_LINE_LEN + cc_cyc][3] = cmp_a_top3;
                cap_c_a[cc_line * MAX_LINE_LEN + cc_cyc][4] = cmp_a_bot0;
                cap_c_a[cc_line * MAX_LINE_LEN + cc_cyc][5] = cmp_a_bot1;
                cap_c_a[cc_line * MAX_LINE_LEN + cc_cyc][6] = cmp_a_bot2;
                cap_c_a[cc_line * MAX_LINE_LEN + cc_cyc][7] = cmp_a_bot3;
                // Group B (lanes 8..15)
                cap_c_b[cc_line * MAX_LINE_LEN + cc_cyc][0] = cmp_b_top0;
                cap_c_b[cc_line * MAX_LINE_LEN + cc_cyc][1] = cmp_b_top1;
                cap_c_b[cc_line * MAX_LINE_LEN + cc_cyc][2] = cmp_b_top2;
                cap_c_b[cc_line * MAX_LINE_LEN + cc_cyc][3] = cmp_b_top3;
                cap_c_b[cc_line * MAX_LINE_LEN + cc_cyc][4] = cmp_b_bot0;
                cap_c_b[cc_line * MAX_LINE_LEN + cc_cyc][5] = cmp_b_bot1;
                cap_c_b[cc_line * MAX_LINE_LEN + cc_cyc][6] = cmp_b_bot2;
                cap_c_b[cc_line * MAX_LINE_LEN + cc_cyc][7] = cmp_b_bot3;
                // Per-lane valid bits + counts
                for (cc_lane_i = 0; cc_lane_i < 16; cc_lane_i = cc_lane_i + 1) begin
                    cap_c_lv[cc_line * MAX_LINE_LEN + cc_cyc][cc_lane_i] = cmp_valid_out[cc_lane_i];
                    if (cmp_valid_out[cc_lane_i])
                        cap_c_lane_cnt[cc_line][cc_lane_i] =
                            cap_c_lane_cnt[cc_line][cc_lane_i] + 1;
                end

                cap_c_line_len[cc_line] = cc_cyc + 1;
                cc_cyc = cc_cyc + 1;
            end
            prev_cmp_any_valid = cmp_any_valid;
        end
    end

    // =========================================================================
    // Tasks
    // =========================================================================
    integer fail_total;
    integer mismatch_cnt;

    initial fail_total = 0;

    task set_lane_len_all;
        input integer val;
        integer li;
        begin
            for (li = 0; li < 16; li = li + 1)
                lane_len_cfg[li] = val[12:0];
        end
    endtask

    task clear_inputs;
        begin
            valid_in = 0;
            din0  = 0; din1  = 0; din2  = 0; din3  = 0;
            din4  = 0; din5  = 0; din6  = 0; din7  = 0;
            din8  = 0; din9  = 0; din10 = 0; din11 = 0;
            din12 = 0; din13 = 0; din14 = 0; din15 = 0;
        end
    endtask

    task clear_arrays;
        integer idx, lane, ln;
        begin
            for (idx = 0; idx < MAX_LINES * MAX_LINE_LEN; idx = idx + 1) begin
                for (lane = 0; lane < 8; lane = lane + 1) begin
                    golden_a[idx][lane] = 0;
                    golden_b[idx][lane] = 0;
                    cap_a[idx][lane]    = 0;
                    cap_b[idx][lane]    = 0;
                    cap_c_a[idx][lane]  = 0;
                    cap_c_b[idx][lane]  = 0;
                    gold_c_a[idx][lane] = 0;
                    gold_c_b[idx][lane] = 0;
                end
                for (lane = 0; lane < 16; lane = lane + 1)
                    cap_c_lv[idx][lane] = 0;
            end
            for (ln = 0; ln < MAX_LINES; ln = ln + 1) begin
                golden_line_len[ln] = 0;
                cap_a_line_len[ln]  = 0;
                cap_b_line_len[ln]  = 0;
                cap_c_line_len[ln]  = 0;
                gold_c_line_len[ln] = 0;
                for (lane = 0; lane < 16; lane = lane + 1)
                    cap_c_lane_cnt[ln][lane] = 0;
            end
            golden_line_cnt = 0;
            cap_a_line_cnt  = 0;
            cap_b_line_cnt  = 0;
            cap_c_line_cnt  = 0;
            g_line = 0;
            g_cyc  = 0;
            ca_line = 0;
            ca_cyc  = 0;
            cb_line = 0;
            cb_cyc  = 0;
            cc_line = 0;
            cc_cyc  = 0;
            prev_valid_in      = 0;
            prev_rev_a_valid   = 0;
            prev_rev_b_valid   = 0;
            prev_cmp_any_valid = 0;
        end
    endtask

    // =========================================================================
    // Line-by-line golden compare with offset detection
    // =========================================================================
    task compare_results;
        input [1:0] mode;
        integer line, cyc, lane, offset;
        integer mm;
        integer g_base, c_base;
        begin
            mm = 0;

            // --- Dump golden and capture data ---
            $display("");
            $display("  === GOLDEN (input to scheduler_top) ===");
            for (line = 0; line < golden_line_cnt; line = line + 1) begin
                g_base = line * MAX_LINE_LEN;
                $display("  Golden Line %0d (%0d cycles):", line, golden_line_len[line]);
                for (cyc = 0; cyc < golden_line_len[line]; cyc = cyc + 1)
                    $display("    [%02d] L0=%02h L1=%02h L2=%02h L3=%02h L4=%02h L5=%02h L6=%02h L7=%02h",
                        cyc,
                        golden_a[g_base+cyc][0], golden_a[g_base+cyc][1],
                        golden_a[g_base+cyc][2], golden_a[g_base+cyc][3],
                        golden_a[g_base+cyc][4], golden_a[g_base+cyc][5],
                        golden_a[g_base+cyc][6], golden_a[g_base+cyc][7]);
            end

            $display("");
            $display("  === CAPTURE (output of reverse_transpose A) ===");
            for (line = 0; line < cap_a_line_cnt; line = line + 1) begin
                c_base = line * MAX_LINE_LEN;
                $display("  Capture Line %0d (%0d cycles):", line, cap_a_line_len[line]);
                for (cyc = 0; cyc < cap_a_line_len[line]; cyc = cyc + 1)
                    $display("    [%02d] L0=%02h L1=%02h L2=%02h L3=%02h L4=%02h L5=%02h L6=%02h L7=%02h",
                        cyc,
                        cap_a[c_base+cyc][0], cap_a[c_base+cyc][1],
                        cap_a[c_base+cyc][2], cap_a[c_base+cyc][3],
                        cap_a[c_base+cyc][4], cap_a[c_base+cyc][5],
                        cap_a[c_base+cyc][6], cap_a[c_base+cyc][7]);
            end

            $display("");

            // --- Dump Group B if active ---
            if (mode[1]) begin
                $display("");
                $display("  === GOLDEN Group B (lanes 8-15) ===");
                for (line = 0; line < golden_line_cnt; line = line + 1) begin
                    g_base = line * MAX_LINE_LEN;
                    $display("  Golden B Line %0d (%0d cycles):", line, golden_line_len[line]);
                    for (cyc = 0; cyc < golden_line_len[line]; cyc = cyc + 1)
                        $display("    [%02d] L8=%02h L9=%02h L10=%02h L11=%02h L12=%02h L13=%02h L14=%02h L15=%02h",
                            cyc,
                            golden_b[g_base+cyc][0], golden_b[g_base+cyc][1],
                            golden_b[g_base+cyc][2], golden_b[g_base+cyc][3],
                            golden_b[g_base+cyc][4], golden_b[g_base+cyc][5],
                            golden_b[g_base+cyc][6], golden_b[g_base+cyc][7]);
                end

                $display("");
                $display("  === CAPTURE Group B (output of reverse_transpose B) ===");
                for (line = 0; line < cap_b_line_cnt; line = line + 1) begin
                    c_base = line * MAX_LINE_LEN;
                    $display("  Capture B Line %0d (%0d cycles):", line, cap_b_line_len[line]);
                    for (cyc = 0; cyc < cap_b_line_len[line]; cyc = cyc + 1)
                        $display("    [%02d] L8=%02h L9=%02h L10=%02h L11=%02h L12=%02h L13=%02h L14=%02h L15=%02h",
                            cyc,
                            cap_b[c_base+cyc][0], cap_b[c_base+cyc][1],
                            cap_b[c_base+cyc][2], cap_b[c_base+cyc][3],
                            cap_b[c_base+cyc][4], cap_b[c_base+cyc][5],
                            cap_b[c_base+cyc][6], cap_b[c_base+cyc][7]);
                end
                $display("");
            end

            // --- Group A compare ---
            $display("  Group A: golden %0d lines, capture %0d lines", golden_line_cnt, cap_a_line_cnt);

            for (line = 0; line < cap_a_line_cnt; line = line + 1) begin
                if (line >= golden_line_cnt) begin
                    $display("  FAIL: capture A has extra line %0d", line);
                    mm = mm + 1;
                end else begin
                    g_base = line * MAX_LINE_LEN;
                    c_base = line * MAX_LINE_LEN;

                    // Find offset: search for cap_a[c_base][0] in golden_a[g_base + *][0]
                    offset = -1;
                    for (cyc = 0; cyc < golden_line_len[line]; cyc = cyc + 1) begin
                        if (offset == -1 && golden_a[g_base + cyc][0] === cap_a[c_base][0])
                            offset = cyc;
                    end

                    if (offset < 0) begin
                        $display("  Line %0d: FAIL could not find offset (cap[0][0]=%02h)", line, cap_a[c_base][0]);
                        mm = mm + 1;
                    end else begin
                        // Compare entry by entry
                        for (cyc = 0; cyc < cap_a_line_len[line]; cyc = cyc + 1) begin
                            if (offset + cyc < golden_line_len[line]) begin
                                for (lane = 0; lane < 8; lane = lane + 1) begin
                                    if (cap_a[c_base + cyc][lane] !== golden_a[g_base + offset + cyc][lane]) begin
                                        if (mm < 20)
                                            $display("  [MISMATCH] A line%0d cyc%0d lane%0d got=%02h exp=%02h",
                                                line, cyc, lane,
                                                cap_a[c_base + cyc][lane],
                                                golden_a[g_base + offset + cyc][lane]);
                                        mm = mm + 1;
                                    end
                                end
                            end
                        end
                        $display("  Line %0d: len golden=%0d capture=%0d offset=%0d",
                            line, golden_line_len[line], cap_a_line_len[line], offset);
                    end
                end
            end

            if (cap_a_line_cnt < golden_line_cnt)
                $display("  WARNING: capture A has fewer lines (%0d) than golden (%0d)",
                    cap_a_line_cnt, golden_line_cnt);

            // --- Group B (only for 12L/16L) ---
            if (mode[1]) begin
                $display("  Group B: golden %0d lines, capture %0d lines", golden_line_cnt, cap_b_line_cnt);

                for (line = 0; line < cap_b_line_cnt; line = line + 1) begin
                    if (line >= golden_line_cnt) begin
                        $display("  FAIL: capture B has extra line %0d", line);
                        mm = mm + 1;
                    end else begin
                        g_base = line * MAX_LINE_LEN;
                        c_base = line * MAX_LINE_LEN;

                        // Find offset: search for cap_b[c_base][0] in golden_b[g_base + *][0]
                        offset = -1;
                        for (cyc = 0; cyc < golden_line_len[line]; cyc = cyc + 1) begin
                            if (offset == -1 && golden_b[g_base + cyc][0] === cap_b[c_base][0])
                                offset = cyc;
                        end

                        if (offset < 0) begin
                            $display("  Line %0d: FAIL could not find offset (cap[0][0]=%02h)", line, cap_b[c_base][0]);
                            mm = mm + 1;
                        end else begin
                            for (cyc = 0; cyc < cap_b_line_len[line]; cyc = cyc + 1) begin
                                if (offset + cyc < golden_line_len[line]) begin
                                    for (lane = 0; lane < 8; lane = lane + 1) begin
                                        if (cap_b[c_base + cyc][lane] !== golden_b[g_base + offset + cyc][lane]) begin
                                            if (mm < 20)
                                                $display("  [MISMATCH] B line%0d cyc%0d lane%0d got=%02h exp=%02h",
                                                    line, cyc, lane,
                                                    cap_b[c_base + cyc][lane],
                                                    golden_b[g_base + offset + cyc][lane]);
                                            mm = mm + 1;
                                        end
                                    end
                                end
                            end
                            $display("  Line %0d: len golden=%0d capture=%0d offset=%0d",
                                line, golden_line_len[line], cap_b_line_len[line], offset);
                        end
                    end
                end

                if (cap_b_line_cnt < golden_line_cnt)
                    $display("  WARNING: capture B has fewer lines (%0d) than golden (%0d)",
                        cap_b_line_cnt, golden_line_cnt);
            end

            // =================================================================
            // Compactor compare (per-lane valid, with length limiter):
            //   - Build gold_c_a/b from input golden by picking cycles
            //     {0,1, 4,5, 8,9, 12,13, 16,17, 20,21} (4:2 compaction).
            //   - For each lane i in the active set (determined by mode):
            //       expected_valid_count[i] = min(gold_c_line_len, lane_len_cfg[i])
            //       cap_c_lane_cnt[line][i] must equal expected_valid_count[i].
            //     For each slow cycle in the captured line:
            //       expected cap_c_lv == 1 iff (cyc < expected_valid_count[i]).
            //       when cap_c_lv==1 the data on that lane must equal
            //       gold_c_{a|b}[cyc_within_keep][lane_in_group].
            //   - Inactive lanes (per mode) are not checked.
            // =================================================================
            begin : COMPACTOR_CMP
                integer cline, csrc, cdst;
                integer cmp_mm;
                integer cmp_g_base, cmp_c_base;
                integer glen, keep;
                integer lane16, grp_lane, exp_cnt, got_cnt, exp_lv, got_lv;
                integer lane_active_max;
                reg [DATA_W-1:0] exp_val, got_val;

                cmp_mm = 0;

                // --- Build compactor golden from input golden arrays ---
                // Spec: compactor keeps cycles 0 and 1 out of every group of 4
                // input cycles (cycles 2 and 3 are dropped redundant beats).
                // Expected golden order for a 24-cycle burst:
                //   {0, 1, 4, 5, 8, 9, 12, 13, 16, 17, 20, 21}  -> 12 beats.
                for (cline = 0; cline < golden_line_cnt; cline = cline + 1) begin
                    cmp_g_base = cline * MAX_LINE_LEN;
                    glen       = golden_line_len[cline];
                    cdst       = 0;
                    for (csrc = 0; csrc < glen; csrc = csrc + 4) begin
                        // Emit source cycle csrc, then csrc+1.
                        if (csrc < glen) begin
                            for (lane = 0; lane < 8; lane = lane + 1) begin
                                gold_c_a[cmp_g_base + cdst][lane] = golden_a[cmp_g_base + csrc][lane];
                                gold_c_b[cmp_g_base + cdst][lane] = golden_b[cmp_g_base + csrc][lane];
                            end
                            cdst = cdst + 1;
                        end
                        if (csrc + 1 < glen) begin
                            for (lane = 0; lane < 8; lane = lane + 1) begin
                                gold_c_a[cmp_g_base + cdst][lane] = golden_a[cmp_g_base + csrc + 1][lane];
                                gold_c_b[cmp_g_base + cdst][lane] = golden_b[cmp_g_base + csrc + 1][lane];
                            end
                            cdst = cdst + 1;
                        end
                    end
                    gold_c_line_len[cline] = cdst;
                end

                // --- Dump compactor golden ---
                $display("");
                $display("  === COMPACTOR GOLDEN (picked cycles 0,1,4,5,8,9,...) ===");
                for (cline = 0; cline < golden_line_cnt; cline = cline + 1) begin
                    cmp_g_base = cline * MAX_LINE_LEN;
                    $display("  CG Line %0d (%0d cycles):", cline, gold_c_line_len[cline]);
                    for (csrc = 0; csrc < gold_c_line_len[cline]; csrc = csrc + 1) begin
                        if (mode[1])
                            $display("    [%02d] A:L0=%02h L1=%02h L2=%02h L3=%02h L4=%02h L5=%02h L6=%02h L7=%02h | B:L8=%02h L9=%02h L10=%02h L11=%02h L12=%02h L13=%02h L14=%02h L15=%02h",
                                csrc,
                                gold_c_a[cmp_g_base+csrc][0], gold_c_a[cmp_g_base+csrc][1],
                                gold_c_a[cmp_g_base+csrc][2], gold_c_a[cmp_g_base+csrc][3],
                                gold_c_a[cmp_g_base+csrc][4], gold_c_a[cmp_g_base+csrc][5],
                                gold_c_a[cmp_g_base+csrc][6], gold_c_a[cmp_g_base+csrc][7],
                                gold_c_b[cmp_g_base+csrc][0], gold_c_b[cmp_g_base+csrc][1],
                                gold_c_b[cmp_g_base+csrc][2], gold_c_b[cmp_g_base+csrc][3],
                                gold_c_b[cmp_g_base+csrc][4], gold_c_b[cmp_g_base+csrc][5],
                                gold_c_b[cmp_g_base+csrc][6], gold_c_b[cmp_g_base+csrc][7]);
                        else
                            $display("    [%02d] A:L0=%02h L1=%02h L2=%02h L3=%02h L4=%02h L5=%02h L6=%02h L7=%02h",
                                csrc,
                                gold_c_a[cmp_g_base+csrc][0], gold_c_a[cmp_g_base+csrc][1],
                                gold_c_a[cmp_g_base+csrc][2], gold_c_a[cmp_g_base+csrc][3],
                                gold_c_a[cmp_g_base+csrc][4], gold_c_a[cmp_g_base+csrc][5],
                                gold_c_a[cmp_g_base+csrc][6], gold_c_a[cmp_g_base+csrc][7]);
                    end
                end

                // --- Dump compactor capture ---
                $display("");
                $display("  === COMPACTOR CAPTURE (output of lane_compactor) ===");
                for (cline = 0; cline < cap_c_line_cnt; cline = cline + 1) begin
                    cmp_c_base = cline * MAX_LINE_LEN;
                    $display("  CC Line %0d (%0d cycles):", cline, cap_c_line_len[cline]);
                    for (csrc = 0; csrc < cap_c_line_len[cline]; csrc = csrc + 1) begin
                        if (mode[1])
                            $display("    [%02d] A:L0=%02h L1=%02h L2=%02h L3=%02h L4=%02h L5=%02h L6=%02h L7=%02h | B:L8=%02h L9=%02h L10=%02h L11=%02h L12=%02h L13=%02h L14=%02h L15=%02h",
                                csrc,
                                cap_c_a[cmp_c_base+csrc][0], cap_c_a[cmp_c_base+csrc][1],
                                cap_c_a[cmp_c_base+csrc][2], cap_c_a[cmp_c_base+csrc][3],
                                cap_c_a[cmp_c_base+csrc][4], cap_c_a[cmp_c_base+csrc][5],
                                cap_c_a[cmp_c_base+csrc][6], cap_c_a[cmp_c_base+csrc][7],
                                cap_c_b[cmp_c_base+csrc][0], cap_c_b[cmp_c_base+csrc][1],
                                cap_c_b[cmp_c_base+csrc][2], cap_c_b[cmp_c_base+csrc][3],
                                cap_c_b[cmp_c_base+csrc][4], cap_c_b[cmp_c_base+csrc][5],
                                cap_c_b[cmp_c_base+csrc][6], cap_c_b[cmp_c_base+csrc][7]);
                        else
                            $display("    [%02d] A:L0=%02h L1=%02h L2=%02h L3=%02h L4=%02h L5=%02h L6=%02h L7=%02h",
                                csrc,
                                cap_c_a[cmp_c_base+csrc][0], cap_c_a[cmp_c_base+csrc][1],
                                cap_c_a[cmp_c_base+csrc][2], cap_c_a[cmp_c_base+csrc][3],
                                cap_c_a[cmp_c_base+csrc][4], cap_c_a[cmp_c_base+csrc][5],
                                cap_c_a[cmp_c_base+csrc][6], cap_c_a[cmp_c_base+csrc][7]);
                    end
                end
                $display("");

                // --- Determine active lane range from mode ---
                // 4L -> 4, 8L -> 8, 12L -> 12, 16L -> 16.
                case (mode)
                    2'b00: lane_active_max = 4;
                    2'b01: lane_active_max = 8;
                    2'b10: lane_active_max = 12;
                    2'b11: lane_active_max = 16;
                    default: lane_active_max = 16;
                endcase

                $display("  Compactor: golden %0d lines, capture %0d lines (active lanes 0..%0d)",
                    golden_line_cnt, cap_c_line_cnt, lane_active_max - 1);

                if (cap_c_line_cnt !== golden_line_cnt) begin
                    $display("  FAIL: compactor line count mismatch (got=%0d exp=%0d)",
                        cap_c_line_cnt, golden_line_cnt);
                    cmp_mm = cmp_mm + 1;
                end

                // --- Per-lane valid bitmap dump (first line only, up to 6 cycles) ---
                if (cap_c_line_cnt > 0) begin
                    $display("  === PER-LANE valid_out bitmap (line 0, first up to 6 slow cycles) ===");
                    for (csrc = 0; csrc < cap_c_line_len[0] && csrc < 6; csrc = csrc + 1) begin
                        $display("    [cyc %0d] valid_out[15:0] = %b%b%b%b_%b%b%b%b_%b%b%b%b_%b%b%b%b",
                            csrc,
                            cap_c_lv[csrc][15], cap_c_lv[csrc][14],
                            cap_c_lv[csrc][13], cap_c_lv[csrc][12],
                            cap_c_lv[csrc][11], cap_c_lv[csrc][10],
                            cap_c_lv[csrc][9],  cap_c_lv[csrc][8],
                            cap_c_lv[csrc][7],  cap_c_lv[csrc][6],
                            cap_c_lv[csrc][5],  cap_c_lv[csrc][4],
                            cap_c_lv[csrc][3],  cap_c_lv[csrc][2],
                            cap_c_lv[csrc][1],  cap_c_lv[csrc][0]);
                    end
                end

                for (cline = 0; cline < golden_line_cnt; cline = cline + 1) begin
                    cmp_g_base = cline * MAX_LINE_LEN;
                    cmp_c_base = cline * MAX_LINE_LEN;

                    if (cline >= cap_c_line_cnt) begin
                        $display("  FAIL: compactor missing line %0d entirely", cline);
                        cmp_mm = cmp_mm + 1;
                    end else begin
                        for (lane16 = 0; lane16 < lane_active_max; lane16 = lane16 + 1) begin
                            // Group / within-group lane index
                            if (lane16 < 8) begin
                                grp_lane = lane16;
                            end else begin
                                grp_lane = lane16 - 8;
                            end

                            // Expected beat count for this lane
                            if (lane_len_cfg[lane16] >= gold_c_line_len[cline])
                                exp_cnt = gold_c_line_len[cline];
                            else
                                exp_cnt = lane_len_cfg[lane16];

                            got_cnt = cap_c_lane_cnt[cline][lane16];
                            if (got_cnt !== exp_cnt) begin
                                $display("  FAIL: line %0d lane %0d valid-count mismatch got=%0d exp=%0d (lane_len=%0d, golden_len=%0d)",
                                    cline, lane16, got_cnt, exp_cnt,
                                    lane_len_cfg[lane16], gold_c_line_len[cline]);
                                cmp_mm = cmp_mm + 1;
                            end

                            // Walk every captured slow cycle; check valid bit
                            // matches expected pattern (1 for first exp_cnt cycles,
                            // 0 afterwards), and on valid=1 check the data bus.
                            for (csrc = 0; csrc < cap_c_line_len[cline]; csrc = csrc + 1) begin
                                exp_lv = (csrc < exp_cnt) ? 1 : 0;
                                got_lv = cap_c_lv[cmp_c_base + csrc][lane16];

                                if (got_lv !== exp_lv) begin
                                    if (cmp_mm < 20)
                                        $display("  [CMP LV] line%0d cyc%0d lane%0d got_valid=%0d exp_valid=%0d",
                                            cline, csrc, lane16, got_lv, exp_lv);
                                    cmp_mm = cmp_mm + 1;
                                end

                                if (got_lv && exp_lv && csrc < gold_c_line_len[cline]) begin
                                    // Data compare
                                    if (lane16 < 8) begin
                                        got_val = cap_c_a[cmp_c_base + csrc][grp_lane];
                                        exp_val = gold_c_a[cmp_g_base + csrc][grp_lane];
                                    end else begin
                                        got_val = cap_c_b[cmp_c_base + csrc][grp_lane];
                                        exp_val = gold_c_b[cmp_g_base + csrc][grp_lane];
                                    end
                                    if (got_val !== exp_val) begin
                                        if (cmp_mm < 20)
                                            $display("  [CMP DATA] line%0d cyc%0d lane%0d got=%02h exp=%02h",
                                                cline, csrc, lane16, got_val, exp_val);
                                        cmp_mm = cmp_mm + 1;
                                    end
                                end
                            end
                        end

                        $display("  Compactor line %0d: cap_len=%0d golden_keep_len=%0d",
                            cline, cap_c_line_len[cline], gold_c_line_len[cline]);
                    end
                end

                mm = mm + cmp_mm;
            end

            mismatch_cnt = mismatch_cnt + mm;
        end
    endtask

    // =========================================================================
    // Run one mode
    // =========================================================================
    task run_mode;
        input [255:0] name;
        input [1:0]   mode;
        input integer ratio;
        input         vlane_en;
        integer c;
        integer mode_pass;
        begin
            $display("\n========================================");
            $display("--- %0s (mode=%0b, ratio=%0d, vlane=%0d) ---", name, mode, ratio, vlane_en);
            $display("========================================");

            // Setup
            lane_mode       = mode;
            virtual_lane_en = vlane_en;
            slow_half       = ratio * CLK_FAST_HALF;
            mismatch_cnt = 0;
            dumper_en    = 0;
            // NOTE: lane_len_cfg is set by the caller before invoking run_mode
            // (normal cases call set_lane_len_all(8191); length-limiter cases
            // set individual per-lane limits).

            clear_inputs;
            clear_arrays;

            // Reset
            rst_n = 0;
            repeat(8) @(posedge clk_fast);
            rst_n = 1;
            repeat(4) @(posedge clk_slow);

            // Enable dumper
            dumper_en = 1;

            // Drive NUM_CYCLES of per-lane-per-cycle data (one continuous burst)
            // din[n] = n + cycle * 16 (for all active lanes)
            for (c = 0; c < NUM_CYCLES; c = c + 1) begin
                @(negedge clk_slow);
                valid_in = 1;

                // Group A lower: lanes 0-3 (always active)
                din0 = 8'(0 + c * 16);
                din1 = 8'(1 + c * 16);
                din2 = 8'(2 + c * 16);
                din3 = 8'(3 + c * 16);

                // Group A upper: lanes 4-7 (active for 8L/12L/16L)
                if (mode >= 2'b01) begin
                    din4 = 8'(4 + c * 16);
                    din5 = 8'(5 + c * 16);
                    din6 = 8'(6 + c * 16);
                    din7 = 8'(7 + c * 16);
                end else begin
                    din4 = 0; din5 = 0; din6 = 0; din7 = 0;
                end

                // Group B lower: lanes 8-11 (active for 12L/16L)
                if (mode >= 2'b10) begin
                    din8  = 8'(8  + c * 16);
                    din9  = 8'(9  + c * 16);
                    din10 = 8'(10 + c * 16);
                    din11 = 8'(11 + c * 16);
                end else begin
                    din8 = 0; din9 = 0; din10 = 0; din11 = 0;
                end

                // Group B upper: lanes 12-15 (active for 16L only)
                if (mode == 2'b11) begin
                    din12 = 8'(12 + c * 16);
                    din13 = 8'(13 + c * 16);
                    din14 = 8'(14 + c * 16);
                    din15 = 8'(15 + c * 16);
                end else begin
                    din12 = 0; din13 = 0; din14 = 0; din15 = 0;
                end
            end

            // Deassert valid_in -> line ends
            @(negedge clk_slow);
            clear_inputs;

            // Wait for pipeline to drain (generous: 200 slow cycles, covers
            // compactor clk_slow_div2 domain which runs at half rate).
            repeat(200) @(posedge clk_slow);

            // Disable dumper
            dumper_en = 0;

            // Post-sim golden compare
            compare_results(mode);

            // Report
            mode_pass = 1;

            $display("  ---");
            $display("  Golden lines:     %0d", golden_line_cnt);
            $display("  Capture A lines:  %0d", cap_a_line_cnt);
            if (mode[1])
                $display("  Capture B lines:  %0d", cap_b_line_cnt);
            $display("  Capture CMP lines:%0d", cap_c_line_cnt);
            $display("  Mismatches:       %0d", mismatch_cnt);

            if (cap_a_line_cnt == 0) begin
                $display("  FAIL: Group A captured 0 lines");
                mode_pass = 0;
            end
            if (mode[1] && cap_b_line_cnt == 0) begin
                $display("  FAIL: Group B captured 0 lines");
                mode_pass = 0;
            end
            if (cap_c_line_cnt == 0) begin
                $display("  FAIL: Compactor captured 0 lines");
                mode_pass = 0;
            end
            if (mismatch_cnt > 0) begin
                mode_pass = 0;
            end

            if (mode_pass)
                $display("  PASS %0s", name);
            else begin
                $display("  FAIL %0s", name);
                fail_total = fail_total + 1;
            end
        end
    endtask

    // =========================================================================
    // Main test sequence
    // =========================================================================
    initial begin
        fail_total = 0;
        rst_n = 0;
        lane_mode = 2'b00;
        virtual_lane_en = 1'b0;
        slow_half = CLK_FAST_HALF;
        dumper_en = 0;
        clear_inputs;
        set_lane_len_all(8191);

        //                  name             mode    ratio  vlane
        set_lane_len_all(8191);
        run_mode("4L  PHY",   2'b00,  1, 0);
        set_lane_len_all(8191);
        run_mode("8L  PHY",   2'b01,  2, 0);
        set_lane_len_all(8191);
        run_mode("12L PHY",   2'b10,  3, 0);
        set_lane_len_all(8191);
        run_mode("16L PHY",   2'b11,  4, 0);

        set_lane_len_all(8191);
        run_mode("4L  VLANE", 2'b00,  1, 1);
        set_lane_len_all(8191);
        run_mode("8L  VLANE", 2'b01,  2, 1);
        set_lane_len_all(8191);
        run_mode("12L VLANE", 2'b10,  3, 1);
        set_lane_len_all(8191);
        run_mode("16L VLANE", 2'b11,  4, 1);

        // =====================================================================
        // C9: 8L PHY uniform len=4
        //   L0..L7  = 4      (expect 4 beats valid_out[i]=1 then zero)
        //   L8..L15 = 8191   (inactive in 8L mode anyway, not checked)
        // =====================================================================
        set_lane_len_all(8191);
        begin integer li;
          for (li = 0; li < 8; li = li + 1) lane_len_cfg[li] = 13'd4;
        end
        run_mode("C9  8L PHY uniform len=4", 2'b01, 2, 0);

        // =====================================================================
        // C10: 16L PHY mixed length
        //   L0=2, L1=4, L2=6, L3=8, L4=10, L5=12, L6=8191, L7=8191
        //   L8=2, L9=4, L10=6, L11=8, L12=10, L13=12, L14=8191, L15=8191
        // =====================================================================
        set_lane_len_all(8191);
        lane_len_cfg[0]  = 13'd2;  lane_len_cfg[1]  = 13'd4;
        lane_len_cfg[2]  = 13'd6;  lane_len_cfg[3]  = 13'd8;
        lane_len_cfg[4]  = 13'd10; lane_len_cfg[5]  = 13'd12;
        lane_len_cfg[6]  = 13'd8191; lane_len_cfg[7]  = 13'd8191;
        lane_len_cfg[8]  = 13'd2;  lane_len_cfg[9]  = 13'd4;
        lane_len_cfg[10] = 13'd6;  lane_len_cfg[11] = 13'd8;
        lane_len_cfg[12] = 13'd10; lane_len_cfg[13] = 13'd12;
        lane_len_cfg[14] = 13'd8191; lane_len_cfg[15] = 13'd8191;
        run_mode("C10 16L PHY mixed length", 2'b11, 4, 0);

        // =====================================================================
        // C11: 4L PHY L0=0
        //   L0=0 (never emits), L1..L3=8191 (full 12 beats each)
        // =====================================================================
        set_lane_len_all(8191);
        lane_len_cfg[0] = 13'd0;
        run_mode("C11 4L PHY L0=0", 2'b00, 1, 0);

        $display("\n============================================");
        if (fail_total == 0)
            $display("[PASS] ALL LOOPBACK DESCHED_TOP TESTS PASSED (8 regression + 3 length-limiter cases, %0d input cycles each)", NUM_CYCLES);
        else
            $display("[FAIL] %0d mode(s) failed", fail_total);
        $display("============================================");
        $finish;
    end

    // =========================================================================
    // Timeout
    // =========================================================================
    initial begin
        #2000000;
        $display("[TIMEOUT] Simulation exceeded 2000000ns");
        $finish;
    end

endmodule
