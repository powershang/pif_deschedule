# inplace_transpose_buf_multi_lane_out

## Function

Multi-lane output pack wrapper. Instantiates two `inplace_transpose_buf_8lane_2beat` blocks (u_buf_a, u_buf_b) and configures them based on `lane_mode`.

## Interface

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| clk, rst_n | in | 1 | Clock and reset |
| valid_in | in | 1 | Input valid |
| lane_mode | in | 2 | 00=4L, 01=8L, 10=12L, 11=16L |
| virtual_lane_en | in | 1 | 0=PHY, 1=VLANE |
| din0..din15 | in | DATA_W | 16-lane input |
| a_valid_out | out | 1 | Group A output valid |
| a_top0..3, a_bot0..3 | out | DATA_W | Group A output |
| b_valid_out | out | 1 | Group B output valid |
| b_top0..3, b_bot0..3 | out | DATA_W | Group B output |

## Configuration Mapping

| lane_mode | u_buf_a | u_buf_b | u_buf_b valid |
|-----------|---------|---------|--------------|
| 4L (00) | LANE4, din0..7 | LANE4, din8..15 | disabled (valid_in_b=0) |
| 8L (01) | LANE8, din0..7 | LANE4, din8..15 | disabled |
| 12L (10) | LANE8, din0..7 | LANE4, din8..11 | enabled |
| 16L (11) | LANE8, din0..7 | LANE8, din8..15 | enabled |

`valid_in_b = valid_in & lane_mode[1]` — Group B only active for 12L/16L.
