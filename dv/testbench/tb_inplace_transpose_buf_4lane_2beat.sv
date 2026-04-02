`timescale 1ns/1ps

module tb_inplace_transpose_buf_4lane_2beat;

    parameter DATA_W = 8;
    parameter CLK_PERIOD = 10;
    parameter NUM_EXP = 12;

    reg               clk;
    reg               rst_n;
    reg               valid_in;
    reg               mode;
    reg  [DATA_W-1:0] din [0:3];
    wire              valid_out;
    wire [DATA_W-1:0] dout [0:3];

    wire [DATA_W-1:0] din0_2beat=din[0], din1_2beat=din[1];
    wire [DATA_W-1:0] din2_2beat=din[2], din3_2beat=din[3];
    wire [DATA_W-1:0] dout0_2beat=dout[0], dout1_2beat=dout[1];
    wire [DATA_W-1:0] dout2_2beat=dout[2], dout3_2beat=dout[3];
    wire [1:0] dut_state_2beat = dut.state;
    wire [2:0] dut_phase_cnt_2beat = dut.phase_cnt;

    reg [DATA_W-1:0] exp_phy4   [0:NUM_EXP-1][0:3];
    reg [DATA_W-1:0] exp_2vlane [0:NUM_EXP-1][0:3];

    integer out_idx;
    integer fail_count;
    integer cycle_cnt;

    inplace_transpose_buf_4lane_2beat #(.DATA_W(DATA_W)) dut (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(valid_in),
        .mode(mode),
        .din0(din[0]),
        .din1(din[1]),
        .din2(din[2]),
        .din3(din[3]),
        .valid_out(valid_out),
        .dout0(dout[0]),
        .dout1(dout[1]),
        .dout2(dout[2]),
        .dout3(dout[3])
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    always @(posedge clk) begin
        if (valid_out) begin
            integer j;
            integer ok;
            ok = 1;
            if (out_idx < NUM_EXP) begin
                for (j = 0; j < 4; j = j + 1) begin
                    if (mode == 1'b0) begin
                        if (dout[j] !== exp_phy4[out_idx][j]) begin
                            $display("FAIL 2beat PHY4 out#%0d dout[%0d]: got %0d, exp %0d",
                                     out_idx, j, dout[j], exp_phy4[out_idx][j]);
                            ok = 0;
                            fail_count = fail_count + 1;
                        end
                    end else begin
                        if (dout[j] !== exp_2vlane[out_idx][j]) begin
                            $display("FAIL 2beat 2VLANE out#%0d dout[%0d]: got %0d, exp %0d",
                                     out_idx, j, dout[j], exp_2vlane[out_idx][j]);
                            ok = 0;
                            fail_count = fail_count + 1;
                        end
                    end
                end
                if (ok) begin
                    $display("PASS 2beat mode=%0d out#%0d at cycle_cnt=%0d: dout={%0d,%0d,%0d,%0d}",
                             mode, out_idx, cycle_cnt, dout[0], dout[1], dout[2], dout[3]);
                end
            end
            out_idx = out_idx + 1;
        end
    end

    initial begin
        $dumpfile("/mnt/c/python_work/realtek_pc/PIF_schedule_reorder/wave_4lane_2beat.vcd");
        $dumpvars(0, tb_inplace_transpose_buf_4lane_2beat);
        $dumpvars(0, din[0], din[1], din[2], din[3]);
        $dumpvars(0, dout[0], dout[1], dout[2], dout[3]);

        fail_count = 0;
        rst_n = 0;
        valid_in = 0;
        mode = 1'b0;
        cycle_cnt = 0;
        out_idx = 0;
        for (integer ii = 0; ii < 4; ii = ii + 1)
            din[ii] = 0;

        exp_phy4[0][0]=0;   exp_phy4[0][1]=1;   exp_phy4[0][2]=2;   exp_phy4[0][3]=3;
        exp_phy4[1][0]=4;   exp_phy4[1][1]=5;   exp_phy4[1][2]=6;   exp_phy4[1][3]=7;
        exp_phy4[2][0]=16;  exp_phy4[2][1]=17;  exp_phy4[2][2]=18;  exp_phy4[2][3]=19;
        exp_phy4[3][0]=20;  exp_phy4[3][1]=21;  exp_phy4[3][2]=22;  exp_phy4[3][3]=23;
        exp_phy4[4][0]=32;  exp_phy4[4][1]=33;  exp_phy4[4][2]=34;  exp_phy4[4][3]=35;
        exp_phy4[5][0]=36;  exp_phy4[5][1]=37;  exp_phy4[5][2]=38;  exp_phy4[5][3]=39;
        exp_phy4[6][0]=48;  exp_phy4[6][1]=49;  exp_phy4[6][2]=50;  exp_phy4[6][3]=51;
        exp_phy4[7][0]=52;  exp_phy4[7][1]=53;  exp_phy4[7][2]=54;  exp_phy4[7][3]=55;
        exp_phy4[8][0]=8;   exp_phy4[8][1]=9;   exp_phy4[8][2]=10;  exp_phy4[8][3]=11;
        exp_phy4[9][0]=12;  exp_phy4[9][1]=13;  exp_phy4[9][2]=14;  exp_phy4[9][3]=15;
        exp_phy4[10][0]=24; exp_phy4[10][1]=25; exp_phy4[10][2]=26; exp_phy4[10][3]=27;
        exp_phy4[11][0]=28; exp_phy4[11][1]=29; exp_phy4[11][2]=30; exp_phy4[11][3]=31;

        exp_2vlane[0][0]=0;  exp_2vlane[0][1]=1;  exp_2vlane[0][2]=2;  exp_2vlane[0][3]=3;
        exp_2vlane[1][0]=4;  exp_2vlane[1][1]=5;  exp_2vlane[1][2]=6;  exp_2vlane[1][3]=7;
        exp_2vlane[2][0]=32; exp_2vlane[2][1]=33; exp_2vlane[2][2]=34; exp_2vlane[2][3]=35;
        exp_2vlane[3][0]=36; exp_2vlane[3][1]=37; exp_2vlane[3][2]=38; exp_2vlane[3][3]=39;
        exp_2vlane[4][0]=8;  exp_2vlane[4][1]=9;  exp_2vlane[4][2]=10; exp_2vlane[4][3]=11;
        exp_2vlane[5][0]=12; exp_2vlane[5][1]=13; exp_2vlane[5][2]=14; exp_2vlane[5][3]=15;
        exp_2vlane[6][0]=40; exp_2vlane[6][1]=41; exp_2vlane[6][2]=42; exp_2vlane[6][3]=43;
        exp_2vlane[7][0]=44; exp_2vlane[7][1]=45; exp_2vlane[7][2]=46; exp_2vlane[7][3]=47;
        exp_2vlane[8][0]=16; exp_2vlane[8][1]=17; exp_2vlane[8][2]=18; exp_2vlane[8][3]=19;
        exp_2vlane[9][0]=20; exp_2vlane[9][1]=21; exp_2vlane[9][2]=22; exp_2vlane[9][3]=23;
        exp_2vlane[10][0]=48; exp_2vlane[10][1]=49; exp_2vlane[10][2]=50; exp_2vlane[10][3]=51;
        exp_2vlane[11][0]=52; exp_2vlane[11][1]=53; exp_2vlane[11][2]=54; exp_2vlane[11][3]=55;

        @(posedge clk); #1; rst_n = 0;
        @(posedge clk); #1; rst_n = 1;

        // PHY4 mode
        cycle_cnt = 0;
        out_idx = 0;
        mode = 1'b0;
        repeat (32) begin
            @(posedge clk); #1;
            valid_in = 1;
            din[0] = cycle_cnt;
            din[1] = 16 + cycle_cnt;
            din[2] = 32 + cycle_cnt;
            din[3] = 48 + cycle_cnt;
            cycle_cnt = cycle_cnt + 1;
        end

        @(posedge clk); #1; valid_in = 0;
        repeat (8) @(posedge clk);

        // 2VLANE mode
        @(posedge clk); #1; rst_n = 0;
        @(posedge clk); #1; rst_n = 1;
        cycle_cnt = 0;
        out_idx = 0;
        mode = 1'b1;
        repeat (32) begin
            @(posedge clk); #1;
            valid_in = 1;
            din[0] = 2 * cycle_cnt;
            din[1] = 2 * cycle_cnt + 1;
            din[2] = 32 + 2 * cycle_cnt;
            din[3] = 32 + 2 * cycle_cnt + 1;
            cycle_cnt = cycle_cnt + 1;
        end

        @(posedge clk); #1; valid_in = 0;
        repeat (8) @(posedge clk);

        if (fail_count == 0)
            $display("ALL 2BEAT TESTS PASSED");
        else
            $display("FAILED 2BEAT: %0d mismatches", fail_count);

        $finish;
    end

endmodule
