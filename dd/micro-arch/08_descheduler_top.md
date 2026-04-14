# inplace_transpose_buf_multi_lane_descheduler_top

## Function

Top-level deserialization block. Two-stage descheduler + lane compactor + reverse transpose. Receives 4-lane serialized data on fast clock and restores original per-lane-per-cycle format on slow clock. Output matches the original `scheduler_top` input (`din0..din15`): each output cycle carries one sample per lane.

## Interface

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| clk_in | in | 1 | Fast clock (4-lane serialized input side) |
| clk_out | in | 1 | Slow clock (N-lane restored output side) |
| rst_n | in | 1 | Active-low async reset |
| lane_mode | in | 2 | 00=4L, 01=8L, 10=12L, 11=16L |
| virtual_lane_en | in | 1 | 0=MODE_PHY chunk format, 1=MODE_VLANE chunk format (matches forward scheduler `mode`). Fed as `mode` to both `u_rev_a` and `u_rev_b`. |
| valid_in | in | 1 | Serialized input valid (clk_in domain) |
| din0..din3 | in | DATA_W | 4-lane serialized input |
| valid_out | out | 1 | Restored output valid (clk_out domain) |
| a_top0..3, a_bot0..3 | out | DATA_W | Group A restored output (per-lane-per-cycle) |
| b_top0..3, b_bot0..3 | out | DATA_W | Group B restored output (per-lane-per-cycle) |
| dbg_state | out | 3 | Descheduler FSM state |
| dbg_fifo_cnt | out | 4 | Descheduler phase counter |

## Output Format

Output is in **per-lane-per-cycle** format, matching `scheduler_top` din:
- Each output cycle: a_top0=Lane0 sample, a_top1=Lane1 sample, ..., b_bot3=Lane15 sample
- This is the inverse of the chunk accumulation + serialization performed by `scheduler_top`

## Input Constraint

Descheduler 的 din[2]/din[3] 在系統中永遠是 0（tie-0），因為 scheduler 端每個 group 只有 index 0/1 承載有效資料。這是 compactor 需要存在的根本原因——把 descheduler 的 half-filled output 合併成 full output。

## Two-Stage Architecture

```
                    Stage 1                 Stage 2              Stage 3
din[0:3] ──▶ [u_desched] ──▶ chunk ──▶ [u_rev_a / u_rev_b] ──▶ [u_compact] ──▶ dout
             collection FSM     │      reverse transpose         compactor
             + de-rotation      │      (per-lane-per-cycle)
                                │
             clk_in→clk_out     │      clk_out domain           clk_out domain
             CDC via toggle     │
```

### Data Flow

1. **Stage 1 — Descheduler** (`u_desched`): Collects N/4 phases from clk_in domain, applies 12L de-rotation, outputs chunk data on clk_out domain. One `valid_out` pulse per slow clock cycle.

2. **Stage 2 — Reverse Transpose** (`u_rev_a`, `u_rev_b`): Converts chunk format to per-lane-per-cycle format using 8x8 ping-pong buffers. Group A always active; Group B active only for 12L/16L modes. Fixed 9T latency.

3. **Stage 3 — Lane Compactor** (`u_compact`): Merges 2 consecutive half-filled outputs into 1 full output. Output rate = reverse_transpose rate / 2.

## Sub-modules

| Instance | Module | Function |
|----------|--------|----------|
| u_desched | inplace_transpose_buf_multi_lane_descheduler | Stage 1: 4→N deserialization + 12L de-rotation (chunk output) |
| u_rev_a | reverse_inplace_transpose | Stage 2A: Reverse transpose for Group A (all modes) |
| u_rev_b | reverse_inplace_transpose | Stage 2B: Reverse transpose for Group B (12L/16L only) |
| u_compact | lane_compactor | Stage 3: Merge 2 half-filled outputs → 1 full output |

## Lane Config Mapping

Each `reverse_inplace_transpose` instance receives a `lane_cfg` signal that controls whether it operates in LANE8 (8 rows, 1 beat/row) or LANE4 (4 rows, 2 beats/row) mode:

```
lane_cfg_a = (lane_mode == MODE_4L)  ? LANE4 : LANE8
lane_cfg_b = (lane_mode == MODE_16L) ? LANE8 : LANE4
```

| lane_mode | lane_cfg_a | lane_cfg_b | Group A lanes | Group B lanes |
|-----------|-----------|-----------|---------------|---------------|
| 4L  | LANE4 | LANE4 | Lane0..3 (4 rows) | inactive |
| 8L  | LANE8 | LANE4 | Lane0..7 (8 rows) | inactive |
| 12L | LANE8 | LANE4 | Lane0..7 (8 rows) | Lane8..11 (4 rows) |
| 16L | LANE8 | LANE8 | Lane0..7 (8 rows) | Lane8..15 (8 rows) |

## Group B Valid Gating

Group B is only active for 12L and 16L modes (`lane_mode[1] == 1`):

```verilog
wire b_valid = ds_valid_out & lane_mode[1];
```

For 4L/8L modes, `b_valid` is always 0, so `u_rev_b` receives no input and produces no output. This avoids spurious buffer fills from zero data.

## Virtual-Lane Mode (`virtual_lane_en`)

The top-level `virtual_lane_en` signal is forwarded as the `mode` input to both reverse-transpose instances, symmetric to the forward scheduler's `mode` input. It does not affect stage-1 descheduler behavior — the stage-1 chunk output is the same regardless of PHY/VLANE, and the format distinction is fully absorbed by the reverse transpose write path.

| virtual_lane_en | u_rev_a mode | u_rev_b mode | Expected chunk source |
|-----------------|--------------|--------------|-----------------------|
| 0 | MODE_PHY | MODE_PHY | forward scheduler with `mode=MODE_PHY` (per-physical-lane rows) |
| 1 | MODE_VLANE | MODE_VLANE | forward scheduler with `mode=MODE_VLANE` (vlane-interleaved chunks) |

See `07_reverse_inplace_transpose.md` "MODE_VLANE" section for the chunk layout and write-mapping details.

## Output Mapping

The `reverse_inplace_transpose` outputs 8 lanes (dout0..7). These map to the top/bot group format:

```
u_rev_a: dout[0] → a_top0    u_rev_b: dout[0] → b_top0
         dout[1] → a_top1             dout[1] → b_top1
         dout[2] → a_top2             dout[2] → b_top2
         dout[3] → a_top3             dout[3] → b_top3
         dout[4] → a_bot0             dout[4] → b_bot0
         dout[5] → a_bot1             dout[5] → b_bot1
         dout[6] → a_bot2             dout[6] → b_bot2
         dout[7] → a_bot3             dout[7] → b_bot3
```

## Latency

```
Stage 1 (descheduler): N/4 clk_in cycles (collection) + 1 clk_out cycle (toggle detection)
Stage 2 (reverse transpose): 9 clk_out cycles (INIT_FILL = 8 beats + 1 cycle NBA delay)
Stage 3 (compactor): 2 clk_out cycles (accumulate even + output on odd)
```

Total initial latency before first output: Stage 1 + Stage 2 + Stage 3. After pipeline fill, output is continuous at the expected rate for each mode.

## Loopback Verification

```
scheduler_top(din0..din15) → descheduler_top(dout) = identity
```

Output of descheduler_top equals the original per-lane-per-cycle input to scheduler_top. Verified in tb_loopback_desched_top.
