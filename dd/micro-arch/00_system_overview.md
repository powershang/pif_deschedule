# System Overview

## Data Path

```
                    clk_in (slow)                          clk_out (fast)
  N-lane input ──▶ [scheduler_top] ──▶ 4-lane serialized ──▶ [descheduler_top] ──▶ N-lane output
                                                                (compacted)
```

## Top Blocks

| Block | Function | clk_in | clk_out |
|-------|----------|--------|---------|
| `scheduler_top` | N-lane → 4-lane serialization | slow (data input) | fast (serialized output) |
| `descheduler_top` | 4-lane → N-lane deserialization + compaction | fast (serialized input) | slow (restored output) |

## Lane Mode

| lane_mode | Lanes | clk ratio | Scheduler phases/cycle |
|-----------|-------|-----------|----------------------|
| 2'b00 | 4L | 1:1 | 1 |
| 2'b01 | 8L | 1:2 | 2 |
| 2'b10 | 12L | 1:3 | 3 |
| 2'b11 | 16L | 1:4 | 4 |

## Data Width Constraint: din[2]/din[3] = 0

系統實際使用場景中，每個 group 只有 lane0/lane1 承載有效資料，lane2/lane3 固定為 0。

這個 constraint 貫穿整個 data path：

```
原始 N-lane input: 每個 group 只有 index 0,1 有值，index 2,3 = 0
                   例: a_top = {val0, val1, 0, 0}

→ scheduler 序列化後: 每個 phase 的 dout[2]/dout[3] = 0
                      例: dout = {val0, val1, 0, 0}

→ descheduler input: din[2]/din[3] 永遠是 0（2 port tie-0）

→ descheduler output: 每個 group 的 index 2,3 = 0
                      例: a_top = {val0, val1, 0, 0}

→ compactor: 合併 2 筆 descheduler output
             even: a_top = {A0, A1, 0, 0}
             odd:  a_top = {B0, B1, 0, 0}
             merged: a_top = {A0, A1, B0, B1}  ← 4 lanes 全填滿
```

**Compactor 存在的原因**：因為 serialized bus 實際只用 2 lane（din[0]/din[1]），另外 2 lane 是 0。descheduler 忠實還原後 output 也是 half-filled。Compactor 把相鄰 2 拍的 half-filled output 合併成 1 拍 full output，恢復原始 data width。

## Clock Relationship

- Same PLL, posedge aligned
- clk_in (slow) posedge falls between two clk_out (fast) posedges
- No CDC synchronizer needed

## Module Hierarchy

```
scheduler_top
├── lanedata_4n_align_process      # burst padding to 4N
├── inplace_transpose_buf_multi_lane_out  # chunk accumulation
│   ├── inplace_transpose_buf_8lane_2beat (u_buf_a)
│   └── inplace_transpose_buf_8lane_2beat (u_buf_b)
└── inplace_transpose_buf_multi_lane_scheduler  # N→4 serialization

descheduler_top
├── inplace_transpose_buf_multi_lane_descheduler  # 4→N deserialization
└── lane_compactor                                # merge 2 beats → 1

(deprecated) inplace_transpose_buf_4lane_2beat  # reference only
```

## Error Handling

All modules support mid-burst valid drop recovery:
- Every valid_in rising edge is treated as a fresh burst start
- Internal state (phase counters, FSMs, FIFO pointers) resets on rising edge
- Partial/corrupted data from interrupted bursts is discarded
