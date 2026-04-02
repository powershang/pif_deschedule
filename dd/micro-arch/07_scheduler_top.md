# inplace_transpose_buf_multi_lane_scheduler_top

## Function

Top-level serialization block. Combines 4N-alignment, chunk accumulation, and scheduling into one module.

## Interface

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| clk_in | in | 1 | Slow clock (N-lane input side) |
| clk_out | in | 1 | Fast clock (4-lane serialized output side) |
| rst_n | in | 1 | Active-low async reset |
| valid_in | in | 1 | Input data valid (clk_in domain) |
| lane_mode | in | 2 | 00=4L, 01=8L, 10=12L, 11=16L |
| virtual_lane_en | in | 1 | 0=PHY, 1=VLANE |
| din0..din15 | in | DATA_W | 16-lane input data |
| align_error_flag | out | 1 | Burst length alignment error |
| valid_out | out | 1 | Serialized output valid (clk_out domain) |
| dout0..dout3 | out | DATA_W | 4-lane serialized output |
| dbg_state | out | 3 | Scheduler FSM state |
| dbg_fifo_cnt | out | 4 | Scheduler phase counter |

## Internal Pipeline

```
din[0:15] → [u_align] → [u_out] → [u_sched] → dout[0:3]
             1T clk_in   9T clk_in  1T clk_in + 1T clk_out
```

## Sub-modules

| Instance | Module | Function |
|----------|--------|----------|
| u_align | lanedata_4n_align_process | Burst padding to 4N |
| u_out | inplace_transpose_buf_multi_lane_out | Chunk accumulation (2× 8lane_2beat) |
| u_sched | inplace_transpose_buf_multi_lane_scheduler | N→4 serialization |
