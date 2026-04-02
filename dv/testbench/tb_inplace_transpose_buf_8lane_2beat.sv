`timescale 1ns/1ps

module tb_inplace_transpose_buf_8lane_2beat;

    parameter DATA_W = 8;
    parameter CLK_PERIOD = 10;
    parameter MAX_EXP = 256;

    localparam LANE8 = 1'b0;
    localparam LANE4 = 1'b1;
    localparam MODE_PHY = 2'b00;
    localparam MODE_VLANE = 2'b01;

    reg               clk;
    reg               rst_n;
    reg               valid_in;
    reg               lane_cfg;
    reg  [1:0]        mode;
    reg  [DATA_W-1:0] din0;
    reg  [DATA_W-1:0] din1;
    reg  [DATA_W-1:0] din2;
    reg  [DATA_W-1:0] din3;
    reg  [DATA_W-1:0] din4;
    reg  [DATA_W-1:0] din5;
    reg  [DATA_W-1:0] din6;
    reg  [DATA_W-1:0] din7;

    wire              valid_out;
    wire [DATA_W-1:0] dout_top0;
    wire [DATA_W-1:0] dout_top1;
    wire [DATA_W-1:0] dout_top2;
    wire [DATA_W-1:0] dout_top3;
    wire [DATA_W-1:0] dout_bot0;
    wire [DATA_W-1:0] dout_bot1;
    wire [DATA_W-1:0] dout_bot2;
    wire [DATA_W-1:0] dout_bot3;

    reg [DATA_W-1:0] exp_top0 [0:MAX_EXP-1];
    reg [DATA_W-1:0] exp_top1 [0:MAX_EXP-1];
    reg [DATA_W-1:0] exp_top2 [0:MAX_EXP-1];
    reg [DATA_W-1:0] exp_top3 [0:MAX_EXP-1];
    reg [DATA_W-1:0] exp_bot0 [0:MAX_EXP-1];
    reg [DATA_W-1:0] exp_bot1 [0:MAX_EXP-1];
    reg [DATA_W-1:0] exp_bot2 [0:MAX_EXP-1];
    reg [DATA_W-1:0] exp_bot3 [0:MAX_EXP-1];

    integer exp_count;
    integer got_count;
    integer fail_count;

    inplace_transpose_buf_8lane_2beat #(
        .DATA_W(DATA_W)
    ) dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .valid_in (valid_in),
        .lane_cfg (lane_cfg),
        .mode     (mode),
        .din0     (din0),
        .din1     (din1),
        .din2     (din2),
        .din3     (din3),
        .din4     (din4),
        .din5     (din5),
        .din6     (din6),
        .din7     (din7),
        .valid_out(valid_out),
        .dout_top0(dout_top0),
        .dout_top1(dout_top1),
        .dout_top2(dout_top2),
        .dout_top3(dout_top3),
        .dout_bot0(dout_bot0),
        .dout_bot1(dout_bot1),
        .dout_bot2(dout_bot2),
        .dout_bot3(dout_bot3)
    );

    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    initial begin
        $dumpfile("/mnt/c/python_work/realtek_pc/PIF_schedule_reorder/wave_8lane_2beat.vcd");
        $dumpvars(0, tb_inplace_transpose_buf_8lane_2beat);
    end

    always @(posedge clk) begin
        #1;
        if (valid_out) begin
            if (got_count >= exp_count) begin
                $display("FAIL extra out#%0d got top={%0d,%0d,%0d,%0d} bot={%0d,%0d,%0d,%0d}",
                         got_count,
                         dout_top0, dout_top1, dout_top2, dout_top3,
                         dout_bot0, dout_bot1, dout_bot2, dout_bot3);
                fail_count = fail_count + 1;
            end else if (dout_top0 !== exp_top0[got_count] ||
                         dout_top1 !== exp_top1[got_count] ||
                         dout_top2 !== exp_top2[got_count] ||
                         dout_top3 !== exp_top3[got_count] ||
                         dout_bot0 !== exp_bot0[got_count] ||
                         dout_bot1 !== exp_bot1[got_count] ||
                         dout_bot2 !== exp_bot2[got_count] ||
                         dout_bot3 !== exp_bot3[got_count]) begin
                $display("FAIL out#%0d exp top={%0d,%0d,%0d,%0d} bot={%0d,%0d,%0d,%0d} got top={%0d,%0d,%0d,%0d} bot={%0d,%0d,%0d,%0d}",
                         got_count,
                         exp_top0[got_count], exp_top1[got_count], exp_top2[got_count], exp_top3[got_count],
                         exp_bot0[got_count], exp_bot1[got_count], exp_bot2[got_count], exp_bot3[got_count],
                         dout_top0, dout_top1, dout_top2, dout_top3,
                         dout_bot0, dout_bot1, dout_bot2, dout_bot3);
                fail_count = fail_count + 1;
            end
            got_count = got_count + 1;
        end
    end

    task clear_inputs;
        begin
            valid_in = 1'b0;
            din0 = '0; din1 = '0; din2 = '0; din3 = '0;
            din4 = '0; din5 = '0; din6 = '0; din7 = '0;
        end
    endtask

    task clear_expected;
        integer i;
        begin
            exp_count = 0;
            got_count = 0;
            for (i = 0; i < MAX_EXP; i = i + 1) begin
                exp_top0[i] = '0; exp_top1[i] = '0; exp_top2[i] = '0; exp_top3[i] = '0;
                exp_bot0[i] = '0; exp_bot1[i] = '0; exp_bot2[i] = '0; exp_bot3[i] = '0;
            end
        end
    endtask

    task push_expected;
        input [DATA_W-1:0] t0;
        input [DATA_W-1:0] t1;
        input [DATA_W-1:0] t2;
        input [DATA_W-1:0] t3;
        input [DATA_W-1:0] b0;
        input [DATA_W-1:0] b1;
        input [DATA_W-1:0] b2;
        input [DATA_W-1:0] b3;
        begin
            exp_top0[exp_count] = t0; exp_top1[exp_count] = t1; exp_top2[exp_count] = t2; exp_top3[exp_count] = t3;
            exp_bot0[exp_count] = b0; exp_bot1[exp_count] = b1; exp_bot2[exp_count] = b2; exp_bot3[exp_count] = b3;
            exp_count = exp_count + 1;
        end
    endtask

    task build_expected;
        input lane_cfg_sel;
        input [1:0] mode_sel;
        input integer groups;
        integer g;
        integer lane_idx;
        integer base;
        begin
            clear_expected;
            if (lane_cfg_sel == LANE8 && mode_sel == MODE_PHY) begin
                for (g = 0; g < groups; g = g + 1) begin
                    for (lane_idx = 0; lane_idx < 8; lane_idx = lane_idx + 1) begin
                        base = lane_idx * 16 + g * 8;
                        push_expected(base + 0, base + 1, base + 2, base + 3,
                                      base + 4, base + 5, base + 6, base + 7);
                    end
                end
            end else if (lane_cfg_sel == LANE8 && mode_sel == MODE_VLANE) begin
                for (g = 0; g < groups; g = g + 1) begin
                    push_expected(0   + g*8, 1   + g*8, 2   + g*8, 3   + g*8,
                                  4   + g*8, 5   + g*8, 6   + g*8, 7   + g*8);
                    push_expected(32  + g*8, 33  + g*8, 34  + g*8, 35  + g*8,
                                  36  + g*8, 37  + g*8, 38  + g*8, 39  + g*8);
                    push_expected(64  + g*8, 65  + g*8, 66  + g*8, 67  + g*8,
                                  68  + g*8, 69  + g*8, 70  + g*8, 71  + g*8);
                    push_expected(112 + g*8, 113 + g*8, 114 + g*8, 115 + g*8,
                                  116 + g*8, 117 + g*8, 118 + g*8, 119 + g*8);
                end
            end else if (lane_cfg_sel == LANE4 && mode_sel == MODE_PHY) begin
                for (g = 0; g < groups; g = g + 1) begin
                    for (lane_idx = 0; lane_idx < 4; lane_idx = lane_idx + 1) begin
                        base = lane_idx * 16 + g * 8;
                        push_expected(base + 0, base + 1, base + 2, base + 3,
                                      0, 0, 0, 0);
                        push_expected(base + 4, base + 5, base + 6, base + 7,
                                      0, 0, 0, 0);
                    end
                end
            end else begin
                for (g = 0; g < groups; g = g + 1) begin
                    push_expected(160 + g*8, 161 + g*8, 162 + g*8, 163 + g*8,
                                  0, 0, 0, 0);
                    push_expected(164 + g*8, 165 + g*8, 166 + g*8, 167 + g*8,
                                  0, 0, 0, 0);
                    push_expected(192 + g*8, 193 + g*8, 194 + g*8, 195 + g*8,
                                  0, 0, 0, 0);
                    push_expected(196 + g*8, 197 + g*8, 198 + g*8, 199 + g*8,
                                  0, 0, 0, 0);
                end
            end
        end
    endtask

    task drive_pattern;
        input lane_cfg_sel;
        input [1:0] mode_sel;
        input integer cycle_num;
        begin
            valid_in = 1'b1;
            if (lane_cfg_sel == LANE8 && mode_sel == MODE_PHY) begin
                din0 = cycle_num;
                din1 = 16 + cycle_num;
                din2 = 32 + cycle_num;
                din3 = 48 + cycle_num;
                din4 = 64 + cycle_num;
                din5 = 80 + cycle_num;
                din6 = 96 + cycle_num;
                din7 = 112 + cycle_num;
            end else if (lane_cfg_sel == LANE8 && mode_sel == MODE_VLANE) begin
                din0 = 2 * cycle_num;
                din1 = 2 * cycle_num + 1;
                din2 = 32 + 2 * cycle_num;
                din3 = 32 + 2 * cycle_num + 1;
                din4 = 64 + 2 * cycle_num;
                din5 = 64 + 2 * cycle_num + 1;
                din6 = 112 + 2 * cycle_num;
                din7 = 112 + 2 * cycle_num + 1;
            end else if (lane_cfg_sel == LANE4 && mode_sel == MODE_PHY) begin
                din0 = cycle_num;
                din1 = 16 + cycle_num;
                din2 = 32 + cycle_num;
                din3 = 48 + cycle_num;
                din4 = 0;
                din5 = 0;
                din6 = 0;
                din7 = 0;
            end else begin
                din0 = 160 + 2 * cycle_num;
                din1 = 160 + 2 * cycle_num + 1;
                din2 = 192 + 2 * cycle_num;
                din3 = 192 + 2 * cycle_num + 1;
                din4 = 0;
                din5 = 0;
                din6 = 0;
                din7 = 0;
            end
        end
    endtask

    task run_case;
        input [127:0] case_name;
        input lane_cfg_sel;
        input [1:0] mode_sel;
        input integer input_cycles;
        input integer groups;
        integer i;
        integer timeout;
        begin
            $display("\n=== %0s ===", case_name);
            build_expected(lane_cfg_sel, mode_sel, groups);
            clear_inputs;
            lane_cfg = lane_cfg_sel;
            mode = mode_sel;
            rst_n = 1'b0;
            repeat (2) @(posedge clk);
            rst_n = 1'b1;
            @(posedge clk);

            for (i = 0; i < input_cycles; i = i + 1) begin
                @(posedge clk);
                #1;
                drive_pattern(lane_cfg_sel, mode_sel, i);
            end

            @(posedge clk);
            #1;
            clear_inputs;

            timeout = 0;
            while (got_count < exp_count && timeout < exp_count + 40) begin
                @(posedge clk);
                timeout = timeout + 1;
            end

            if (got_count != exp_count) begin
                $display("FAIL %0s expected %0d outputs, got %0d", case_name, exp_count, got_count);
                fail_count = fail_count + 1;
            end else begin
                $display("PASS %0s checked %0d outputs", case_name, exp_count);
            end

            repeat (3) @(posedge clk);
        end
    endtask

    initial begin
        fail_count = 0;
        rst_n = 1'b0;
        lane_cfg = LANE8;
        mode = MODE_PHY;
        clear_inputs;
        clear_expected;

        run_case("LANE8 PHY",   LANE8, MODE_PHY,   24, 3);
        run_case("LANE8 VLANE", LANE8, MODE_VLANE, 12, 3);
        run_case("LANE4 PHY",   LANE4, MODE_PHY,   24, 3);
        run_case("LANE4 VLANE", LANE4, MODE_VLANE, 12, 3);

        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("FAILED: %0d mismatches", fail_count);
        $finish;
    end

endmodule
