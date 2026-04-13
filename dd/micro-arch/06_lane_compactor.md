# lane_compactor

## Function

Post-compaction stage after descheduler.

### 為什麼需要 Compactor

系統中 serialized bus 只有 din[0]/din[1] 承載有效資料，din[2]/din[3] tie-0。Descheduler 忠實還原後，output 每個 group 的 index 2/3 也是 0（half-filled）。

```
descheduler output (half-filled):
  even beat: a_top = {A0, A1, 0, 0}
  odd  beat: a_top = {B0, B1, 0, 0}
```

Compactor 把相鄰 2 拍合併成 1 拍 full output：

```
compactor output (full):
  merged: a_top = {A0, A1, B0, B1}
```

Output rate = descheduler rate / 2，但每筆 data width 完整。

### Compactor output 的語義

Compactor output 仍然是 chunk 格式（同一條 lane 的連續 sample），不是 per-lane-per-cycle 格式。後續仍需 inverse transpose 才能還原為 scheduler_top 的原始 din 格式。

以 4L PHY 為例（Lane0={0..7}, Lane1={8..15}）：
```
descheduler output（half-filled beat 流）：
  beat0: a_top = {0, 1, 0, 0}     ← Lane0 sample[0,1]
  beat1: a_top = {2, 3, 0, 0}     ← Lane0 sample[2,3]
  beat2: a_top = {4, 5, 0, 0}     ← Lane0 sample[4,5]
  beat3: a_top = {6, 7, 0, 0}     ← Lane0 sample[6,7]
  beat4: a_top = {8, 9, 0, 0}     ← Lane1 sample[0,1]
  ...

compactor output（merged，仍是 chunk 格式）：
  out0: a_top = {0, 1, 2, 3}      ← Lane0 sample[0..3]
  out1: a_top = {4, 5, 6, 7}      ← Lane0 sample[4..7]
  out2: a_top = {8, 9,10,11}      ← Lane1 sample[0..3]
  out3: a_top = {12,13,14,15}     ← Lane1 sample[4..7]

最終 descheduler_top output（per-lane-per-cycle，等於原始 din）：
  cycle0: a_top = {0, 8, 0, 0}    ← Lane0[0], Lane1[0]
  cycle1: a_top = {1, 9, 0, 0}    ← Lane0[1], Lane1[1]
  ...
```

## Interface

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| clk | in | 1 | = descheduler clk_out (slow clock) |
| rst_n | in | 1 | Active-low async reset |
| valid_in | in | 1 | From descheduler valid_out |
| a_top0..3_in, ... | in | DATA_W | N-lane input (lane2/3 of each group = 0) |
| valid_out | out | 1 | At div2 rate |
| a_top0..3, ... | out | DATA_W | Full 4-lane output per group (chunk format) |

## Operation

| Phase | Action |
|-------|--------|
| Even (phase=0) | Store input lane0, lane1 of each group |
| Odd (phase=1) | Output: stored lane0,1 + current lane0,1 → lane0,1,2,3 |

## Timing

```
valid_in:  1   1   1   1   1   1   0
phase:     0   1   0   1   0   1
valid_out: 0   1   1   1   0
output:    — [merged0] [merged1] [merged2]
```

Output rate = input rate / 2. Output valid is continuous when input valid is continuous.

## Error Handling

- Fresh burst (valid_in rising edge after gap): reset `phase` to 0 (even)
- Prevents stale stored data from being merged with new burst data
