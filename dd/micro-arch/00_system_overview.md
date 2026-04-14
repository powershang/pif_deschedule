# System Overview

## Data Path

```
                    clk_in (slow)                          clk_out (fast)
  N-lane input ──▶ [scheduler_top] ──▶ 4-lane serialized ──▶ [descheduler_top] ──▶ N-lane output
  (per-lane-per-cycle)                                        (per-lane-per-cycle)
```

**End-to-end identity**: `descheduler_top` output = `scheduler_top` input.

Each output cycle of `descheduler_top` carries one sample per lane, matching the original `scheduler_top` `din0..din15` format.

## Top Blocks

| Block | Function | clk_in | clk_out |
|-------|----------|--------|---------|
| `scheduler_top` | N-lane → 4-lane serialization (chunk accumulation + scheduling) | slow (data input) | fast (serialized output) |
| `descheduler_top` | 4-lane → N-lane deserialization (descheduling + reverse transpose + compaction) | fast (serialized input) | slow (restored output) |

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
原始 N-lane input: 每個 cycle 各 lane 各一個 sample
                   例 (4L PHY): din0=Lane0[t], din1=Lane1[t], din2=0, din3=0

→ chunk accumulation (8lane_2beat): 累積 8 個 cycle，轉置打包
                   例: a_top = {Lane0[0], Lane0[1], Lane0[2], Lane0[3]}

→ scheduler 序列化後: 每個 phase 的 dout[2]/dout[3] = 0
                      （因為原始 lane2/lane3 = 0，打包後自然也是 0）

→ descheduler input: din[2]/din[3] 永遠是 0（2 port tie-0）

→ descheduler Stage 1 output (chunk format): 每個 group 的 index 2/3 = 0

→ reverse_inplace_transpose output (per-lane-per-cycle, half-filled):
             每個 group 的 index 2/3 = 0

→ compactor: 合併 2 筆 half-filled output
             even: a_top = {A0, A1, 0, 0}
             odd:  a_top = {B0, B1, 0, 0}
             merged: a_top = {A0, A1, B0, B1}  ← 完整 per-lane-per-cycle
```

## Descheduler Two-Stage Architecture

The descheduler uses a two-stage pipeline to convert 4-lane serialized data back to N-lane per-lane-per-cycle format:

```
                Stage 1                     Stage 2                  Stage 3
4-lane ──▶ [descheduler] ──▶ chunk ──▶ [reverse_inplace_transpose] ──▶ [lane_compactor] ──▶ N-lane
           collection FSM              8x8 ping-pong transpose        merge half→full
           + 12L de-rotation           (inverse of 8lane_2beat)
           clk_in → clk_out           clk_out domain                 clk_out domain
```

- **Stage 1 (descheduler)**: Collects N/4 serialized phases, applies 12L de-rotation MUX, outputs chunk data via CDC toggle
- **Stage 2 (reverse_inplace_transpose)**: Inverse of `inplace_transpose_buf_8lane_2beat` — writes rows (one chunk per beat), reads columns (one sample per lane per cycle). Two instances: Group A (all modes) and Group B (12L/16L only). Uses 8x8 ping-pong buffers with 9T fixed latency.
- **Stage 3 (lane_compactor)**: Merges 2 consecutive half-filled per-lane-per-cycle outputs into 1 full output

## Clock Relationship

- Same PLL, posedge aligned
- clk_in (slow) posedge falls between two clk_out (fast) posedges
- No CDC synchronizer needed

## Module Hierarchy

```
scheduler_top
├── lanedata_8n_align_process      # burst padding to 8N
├── inplace_transpose_buf_multi_lane_out  # chunk accumulation
│   ├── inplace_transpose_buf_8lane_2beat (u_buf_a)
│   └── inplace_transpose_buf_8lane_2beat (u_buf_b)
└── inplace_transpose_buf_multi_lane_scheduler  # N→4 serialization

descheduler_top
├── inplace_transpose_buf_multi_lane_descheduler (u_desched)  # Stage 1: collection + de-rotation (chunk output)
├── reverse_inplace_transpose (u_rev_a)                       # Stage 2A: Group A reverse transpose
├── reverse_inplace_transpose (u_rev_b)                       # Stage 2B: Group B reverse transpose (12L/16L)
└── lane_compactor (u_compact)                                # Stage 3: merge 2 half-filled → 1 full

(deprecated) inplace_transpose_buf_4lane_2beat  # reference only
```

## Error Handling

All modules support mid-burst valid drop recovery:
- Every valid_in rising edge is treated as a fresh burst start
- Internal state (phase counters, FSMs, FIFO pointers) resets on rising edge
- Partial/corrupted data from interrupted bursts is discarded
