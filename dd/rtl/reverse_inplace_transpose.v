`timescale 1ns/1ps

// =============================================================================
// Module : reverse_inplace_transpose
// Description : Converts chunk format back to per-lane-per-cycle format using
//               two 8x8 ping-pong buffers. Write rows (one chunk per beat),
//               read columns (one sample per lane per cycle) = classic matrix
//               transpose.
//
//               Fixed latency: T0..T7 fill first buffer (INIT_FILL), T9 first
//               output. All modes (LANE8/LANE4) share the same 9T startup.
//
// Target : FPGA / ASIC generic
// =============================================================================

module reverse_inplace_transpose (
    clk, rst_n, lane_cfg, valid_in,
    din_top0, din_top1, din_top2, din_top3,
    din_bot0, din_bot1, din_bot2, din_bot3,
    valid_out,
    dout0, dout1, dout2, dout3, dout4, dout5, dout6, dout7
);

    parameter DATA_W = 32;

    // =========================================================================
    // Port declarations
    // =========================================================================
    input              clk, rst_n;
    input              lane_cfg;         // 0 = LANE8, 1 = LANE4
    input              valid_in;
    input  [DATA_W-1:0] din_top0, din_top1, din_top2, din_top3;
    input  [DATA_W-1:0] din_bot0, din_bot1, din_bot2, din_bot3;
    output reg         valid_out;
    output [DATA_W-1:0] dout0, dout1, dout2, dout3, dout4, dout5, dout6, dout7;

    // =========================================================================
    // Local parameters
    // =========================================================================
    localparam LANE8 = 1'b0;
    localparam LANE4 = 1'b1;

    localparam [1:0] INIT_FILL = 2'd0;
    localparam [1:0] STREAM    = 2'd1;

    // =========================================================================
    // Ping-pong buffers: two 8-row x 8-col matrices
    // =========================================================================
    reg [DATA_W-1:0] buf_0 [0:7][0:7];
    reg [DATA_W-1:0] buf_1 [0:7][0:7];

    // =========================================================================
    // Write-path state
    // =========================================================================
    reg [1:0]  state;
    reg        wr_sel;          // 0 = write buf_0, 1 = write buf_1
    reg [2:0]  wr_row;          // current write row
    reg        l4_beat;         // LANE4: 0 = first half, 1 = second half
    reg        prev_valid;      // for fresh-burst detection

    // =========================================================================
    // Read-path state
    // =========================================================================
    reg        rd_sel;          // captured at read start
    reg        reading;         // read FSM active
    reg [2:0]  rd_col;          // current read column (0..7)
    reg        rd_start;        // pulse: trigger read next cycle

    // =========================================================================
    // Output data registers
    // =========================================================================
    reg [DATA_W-1:0] rd_data [0:7];

    integer i, j;

    // =========================================================================
    // Fresh-burst edge detection
    // =========================================================================
    wire fresh_burst = valid_in & ~prev_valid;

    // =========================================================================
    // Write completion detection
    // =========================================================================
    wire wr_last_lane8 = ~lane_cfg & valid_in & (wr_row == 3'd7) & ~fresh_burst;
    wire wr_last_lane4 =  lane_cfg & valid_in & l4_beat & (wr_row == 3'd3) & ~fresh_burst;
    wire wr_last       = wr_last_lane8 | wr_last_lane4;

    // =========================================================================
    // prev_valid register
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prev_valid <= 1'b0;
        end else begin
            prev_valid <= valid_in;
        end
    end

    // =========================================================================
    // Write path + state machine
    //
    // INIT_FILL : collect first 8 beats into buf_0, no output.
    //   When buf_0 is full -> transition to STREAM, flip wr_sel, pulse rd_start.
    //
    // STREAM : ping-pong. Write to wr_sel buffer while reading from other.
    //   When current write buffer is full -> flip wr_sel, pulse rd_start.
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= INIT_FILL;
            wr_sel   <= 1'b0;
            wr_row   <= 3'd0;
            l4_beat  <= 1'b0;
            rd_start <= 1'b0;
            for (i = 0; i < 8; i = i + 1) begin
                for (j = 0; j < 8; j = j + 1) begin
                    buf_0[i][j] <= {DATA_W{1'b0}};
                    buf_1[i][j] <= {DATA_W{1'b0}};
                end
            end
        end else begin
            rd_start <= 1'b0;   // default: one-cycle pulse

            // --- Fresh burst: reset to INIT_FILL ---
            if (fresh_burst) begin
                state   <= INIT_FILL;
                wr_sel  <= 1'b0;
                wr_row  <= 3'd0;
                l4_beat <= 1'b0;
            end

            // --- Write data ---
            if (valid_in) begin
                if (lane_cfg == LANE8) begin
                    // LANE8: write full row per beat
                    if (wr_sel == 1'b0) begin
                        buf_0[wr_row][0] <= din_top0;
                        buf_0[wr_row][1] <= din_top1;
                        buf_0[wr_row][2] <= din_top2;
                        buf_0[wr_row][3] <= din_top3;
                        buf_0[wr_row][4] <= din_bot0;
                        buf_0[wr_row][5] <= din_bot1;
                        buf_0[wr_row][6] <= din_bot2;
                        buf_0[wr_row][7] <= din_bot3;
                    end else begin
                        buf_1[wr_row][0] <= din_top0;
                        buf_1[wr_row][1] <= din_top1;
                        buf_1[wr_row][2] <= din_top2;
                        buf_1[wr_row][3] <= din_top3;
                        buf_1[wr_row][4] <= din_bot0;
                        buf_1[wr_row][5] <= din_bot1;
                        buf_1[wr_row][6] <= din_bot2;
                        buf_1[wr_row][7] <= din_bot3;
                    end

                    if (fresh_burst) begin
                        wr_row <= 3'd1;
                    end else if (wr_row == 3'd7) begin
                        // Buffer full: flip and trigger read
                        wr_sel   <= ~wr_sel;
                        wr_row   <= 3'd0;
                        rd_start <= 1'b1;
                        if (state == INIT_FILL) begin
                            state <= STREAM;
                        end else begin
                            state <= state;  // hold
                        end
                    end else begin
                        wr_row <= wr_row + 3'd1;
                    end
                end else begin
                    // LANE4: two beats per row (first half / second half)
                    if (fresh_burst) begin
                        // First beat of new burst: write top half of row 0
                        if (wr_sel == 1'b0) begin
                            buf_0[0][0] <= din_top0;
                            buf_0[0][1] <= din_top1;
                            buf_0[0][2] <= din_top2;
                            buf_0[0][3] <= din_top3;
                        end else begin
                            buf_1[0][0] <= din_top0;
                            buf_1[0][1] <= din_top1;
                            buf_1[0][2] <= din_top2;
                            buf_1[0][3] <= din_top3;
                        end
                        l4_beat <= 1'b1;
                        wr_row  <= 3'd0;
                    end else if (l4_beat == 1'b0) begin
                        // First beat of row: write cols [0:3]
                        if (wr_sel == 1'b0) begin
                            buf_0[wr_row][0] <= din_top0;
                            buf_0[wr_row][1] <= din_top1;
                            buf_0[wr_row][2] <= din_top2;
                            buf_0[wr_row][3] <= din_top3;
                        end else begin
                            buf_1[wr_row][0] <= din_top0;
                            buf_1[wr_row][1] <= din_top1;
                            buf_1[wr_row][2] <= din_top2;
                            buf_1[wr_row][3] <= din_top3;
                        end
                        l4_beat <= 1'b1;
                    end else begin
                        // Second beat of row: write cols [4:7]
                        if (wr_sel == 1'b0) begin
                            buf_0[wr_row][4] <= din_top0;
                            buf_0[wr_row][5] <= din_top1;
                            buf_0[wr_row][6] <= din_top2;
                            buf_0[wr_row][7] <= din_top3;
                        end else begin
                            buf_1[wr_row][4] <= din_top0;
                            buf_1[wr_row][5] <= din_top1;
                            buf_1[wr_row][6] <= din_top2;
                            buf_1[wr_row][7] <= din_top3;
                        end
                        l4_beat <= 1'b0;
                        if (wr_row == 3'd3) begin
                            // Buffer full (4 rows): flip and trigger read
                            wr_sel   <= ~wr_sel;
                            wr_row   <= 3'd0;
                            rd_start <= 1'b1;
                            if (state == INIT_FILL) begin
                                state <= STREAM;
                            end else begin
                                state <= state;  // hold
                            end
                        end else begin
                            wr_row <= wr_row + 3'd1;
                        end
                    end
                end
            end

            // --- Partial flush: valid drops before buffer is full (STREAM only) ---
            if (state == STREAM && prev_valid && !valid_in && (wr_row != 3'd0 || l4_beat)) begin
                if (lane_cfg == LANE8) begin
                    // Zero-fill remaining rows
                    for (i = 0; i < 8; i = i + 1) begin
                        if (i[2:0] >= wr_row) begin
                            for (j = 0; j < 8; j = j + 1) begin
                                if (wr_sel == 1'b0) begin
                                    buf_0[i][j] <= {DATA_W{1'b0}};
                                end else begin
                                    buf_1[i][j] <= {DATA_W{1'b0}};
                                end
                            end
                        end
                    end
                end else begin
                    // LANE4: zero-fill remaining rows (rows >= wr_row or >= 4)
                    for (i = 0; i < 8; i = i + 1) begin
                        if (i[2:0] >= wr_row || i[2:0] >= 3'd4) begin
                            for (j = 0; j < 8; j = j + 1) begin
                                if (wr_sel == 1'b0) begin
                                    buf_0[i][j] <= {DATA_W{1'b0}};
                                end else begin
                                    buf_1[i][j] <= {DATA_W{1'b0}};
                                end
                            end
                        end
                    end
                end
                wr_sel   <= ~wr_sel;
                wr_row   <= 3'd0;
                l4_beat  <= 1'b0;
                rd_start <= 1'b1;
            end
        end
    end

    // =========================================================================
    // Read path: column-wise read = transpose output
    //
    // Only active in STREAM state. Triggered by rd_start pulse.
    // Uses rd_sel to capture which buffer to read from.
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_sel    <= 1'b0;
            reading   <= 1'b0;
            rd_col    <= 3'd0;
            valid_out <= 1'b0;
            for (i = 0; i < 8; i = i + 1) begin
                rd_data[i] <= {DATA_W{1'b0}};
            end
        end else begin
            if (fresh_burst) begin
                // Fresh burst kills any ongoing read
                reading   <= 1'b0;
                valid_out <= 1'b0;
            end else if (rd_start) begin
                // Start reading the just-completed buffer
                rd_sel    <= ~wr_sel;
                reading   <= 1'b1;
                rd_col    <= 3'd0;
                valid_out <= 1'b1;
                // First column read (col 0)
                for (i = 0; i < 8; i = i + 1) begin
                    if (wr_sel == 1'b1) begin
                        rd_data[i] <= buf_0[i][0];
                    end else begin
                        rd_data[i] <= buf_1[i][0];
                    end
                end
            end else if (reading) begin
                if (rd_col == 3'd7) begin
                    // Last column done
                    reading   <= 1'b0;
                    valid_out <= 1'b0;
                end else begin
                    rd_col    <= rd_col + 3'd1;
                    valid_out <= 1'b1;
                    for (i = 0; i < 8; i = i + 1) begin
                        if (rd_sel == 1'b0) begin
                            rd_data[i] <= buf_0[i][rd_col + 1];
                        end else begin
                            rd_data[i] <= buf_1[i][rd_col + 1];
                        end
                    end
                end
            end else begin
                valid_out <= 1'b0;
            end
        end
    end

    // =========================================================================
    // Output assignments
    // =========================================================================
    assign dout0 = rd_data[0];
    assign dout1 = rd_data[1];
    assign dout2 = rd_data[2];
    assign dout3 = rd_data[3];
    assign dout4 = rd_data[4];
    assign dout5 = rd_data[5];
    assign dout6 = rd_data[6];
    assign dout7 = rd_data[7];

endmodule
