# inplace_transpose_buf_multi_lane_descheduler_top

## Function

Top-level deserialization block. Combines descheduler and lane compactor into one module.

## Interface

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| clk_in | in | 1 | Fast clock (4-lane serialized input side) |
| clk_out | in | 1 | Slow clock (N-lane restored output side) |
| rst_n | in | 1 | Active-low async reset |
| lane_mode | in | 2 | 00=4L, 01=8L, 10=12L, 11=16L |
| valid_in | in | 1 | Serialized input valid (clk_in domain) |
| din0..din3 | in | DATA_W | 4-lane serialized input |
| valid_out | out | 1 | Compacted output valid (clk_out domain) |
| a_top0..3, a_bot0..3 | out | DATA_W | Group A restored output |
| b_top0..3, b_bot0..3 | out | DATA_W | Group B restored output |
| dbg_state | out | 3 | Descheduler FSM state |
| dbg_fifo_cnt | out | 4 | Descheduler phase counter |

## Input Constraint

Descheduler 的 din[2]/din[3] 在系統中永遠是 0（tie-0），因為 scheduler 端每個 group 只有 index 0/1 承載有效資料。這是 compactor 需要存在的根本原因——把 descheduler 的 half-filled output 合併成 full output。

## Internal Pipeline

```
din[0:3] → [u_desched] → [u_compact] → a_top/bot, b_top/bot
            N/4 clk_in    2 clk_out
            + 1 clk_out
```

## Sub-modules

| Instance | Module | Function |
|----------|--------|----------|
| u_desched | inplace_transpose_buf_multi_lane_descheduler | 4→N deserialization |
| u_compact | lane_compactor | Merge 2 consecutive outputs → 1 full output |

## Loopback Verification

```
scheduler_top → descheduler_top = identity (verified in tb_loopback_desched_top)
```
