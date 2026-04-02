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

## Interface

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| clk | in | 1 | = descheduler clk_out (slow clock) |
| rst_n | in | 1 | Active-low async reset |
| valid_in | in | 1 | From descheduler valid_out |
| a_top0..3_in, ... | in | DATA_W | N-lane input (lane2/3 of each group = 0) |
| valid_out | out | 1 | At div2 rate |
| a_top0..3, ... | out | DATA_W | Full 4-lane output per group |

## Operation

| Phase | Action |
|-------|--------|
| Even (phase=0) | Store input lane0, lane1 of each group |
| Odd (phase=1) | Output: stored lane0,1 + current lane0,1 → lane0,1,2,3 |

## Timing

```
valid_in:  1   1   1   1   0
phase:     0   1   0   1
valid_out:     0   1   0   1
output:        —  [merged0]  — [merged1]
```

Output rate = input rate / 2.

## Error Handling

- Fresh burst (valid_in rising edge after gap): reset `phase` to 0 (even)
- Prevents stale stored data from being merged with new burst data
