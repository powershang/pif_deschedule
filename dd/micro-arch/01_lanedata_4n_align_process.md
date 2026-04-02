# lanedata_4n_align_process

## Function

Burst padding preprocessor. Observes a continuous `valid_in` burst, and if the length is not a multiple of the required alignment, appends pad beats to reach alignment.

## Interface

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| clk | in | 1 | Clock |
| rst_n | in | 1 | Active-low async reset |
| valid_in | in | 1 | Input data valid |
| virtual_lane_en | in | 1 | 0=PHY mode, 1=VLANE mode |
| din0..din15 | in | DATA_W each | 16-lane input data |
| valid_out | out | 1 | Output data valid (registered, 1T latency) |
| dout0..dout15 | out | DATA_W each | 16-lane output data |
| error_flag | out | 1 | Abnormal burst length detected |

Note: 不需要 `lane_mode`。所有 lane 共用同一條 `valid_in`，不使用的 lanes 一起經過 align 後，後級不會消費。

---

## Use Cases + Timing Diagrams

### Case 1: PHY len=8 (rem=0, no pad)

```
cycle:      0   1   2   3   4   5   6   7   8   9
valid_in:   1   1   1   1   1   1   1   1   0   0
din[0]:    D0  D1  D2  D3  D4  D5  D6  D7   -   -

valid_out:  0   1   1   1   1   1   1   1   1   0
dout[0]:    -  D0  D1  D2  D3  D4  D5  D6  D7   -
error_flag: 0
```

Aligned: 8 = 4N → no pad needed.

### Case 2: PHY len=6 (rem=2, pad 2 beats)

```
cycle:      0   1   2   3   4   5   6   7   8
valid_in:   1   1   1   1   1   1   0   0   0
din[0]:    D0  D1  D2  D3  D4  D5   -   -   -

valid_out:  0   1   1   1   1   1   1   1   1
dout[0]:    -  D0  D1  D2  D3  D4  D5  D4  D5
                                        ^^pad^^
error_flag: 0
```

rem=2: repeat last 2 beats (D4, D5). Total output 8 = 4N.

### Case 3: PHY len=5 (rem=1, error, pad 3 beats)

```
cycle:      0   1   2   3   4   5   6   7   8
valid_in:   1   1   1   1   1   0   0   0   0
din[0]:    D0  D1  D2  D3  D4   -   -   -   -

valid_out:  0   1   1   1   1   1   1   1   1
dout[0]:    -  D0  D1  D2  D3  D4  D4  D4  D4
                                    ^^^pad^^^
error_flag: 1
```

rem=1: error case, repeat last beat ×3. Total output 8 = 4N.

### Case 4: PHY len=3 (rem=3, error, pad 1 beat)

```
cycle:      0   1   2   3   4
valid_in:   1   1   1   0   0
din[0]:    D0  D1  D2   -   -

valid_out:  0   1   1   1   1
dout[0]:    -  D0  D1  D2  D2
                        ^pad^
error_flag: 1
```

rem=3: error case, repeat last beat ×1. Total output 4 = 4N.

### Case 5: VLANE len=6 (even, no pad)

```
cycle:      0   1   2   3   4   5   6   7
valid_in:   1   1   1   1   1   1   0   0
din[0]:    D0  D1  D2  D3  D4  D5   -   -

valid_out:  0   1   1   1   1   1   1   0
dout[0]:    -  D0  D1  D2  D3  D4  D5   -
error_flag: 0
```

VLANE even (6 cycles) → no pad needed.

### Case 6: VLANE len=5 (odd, error, pad 1 beat)

```
cycle:      0   1   2   3   4   5   6
valid_in:   1   1   1   1   1   0   0
din[0]:    D0  D1  D2  D3  D4   -   -

valid_out:  0   1   1   1   1   1   1
dout[0]:    -  D0  D1  D2  D3  D4  D4
                                ^pad^
error_flag: 1
```

VLANE odd → pad 1 beat (repeat last). Total output 6 = even.

### Case 7: VLANE len=2 (even, no pad)

```
cycle:      0   1   2   3
valid_in:   1   1   0   0

valid_out:  0   1   1   0
dout[0]:    -  D0  D1   -
error_flag: 0
```

---

## Padding Rules Summary

### PHY mode (virtual_lane_en=0)

Alignment unit = 4 cycles.

| Remainder | Pad beats | Pattern | error_flag |
|-----------|-----------|---------|------------|
| 0 (len=4,8,12..) | 0 | — | 0 |
| 2 (len=2,6,10..) | 2 | repeat last 2 beats | 0 |
| 1 (len=1,5,9..) | 3 | repeat last beat | 1 |
| 3 (len=3,7,11..) | 1 | repeat last beat | 1 |

### VLANE mode (virtual_lane_en=1)

Alignment unit = 2 cycles (even).

| Remainder | Pad beats | Pattern | error_flag |
|-----------|-----------|---------|------------|
| even (len=2,4,6..) | 0 | — | 0 |
| odd (len=1,3,5..) | 1 | repeat last beat | 1 |

---

## Key Behavior

- **valid_out is continuous**: no gap from first to last output beat within a burst (including pad)
- **1T registered output**: valid_out appears 1 cycle after valid_in
- **Fresh burst reset**: every valid_in rising edge resets beat_mod_q=0, pad state, error_flag
- **tail_buf[0..3]**: circular buffer records last 4 input beats for replay
- **replay_two_q**: distinguishes 2-beat replay (PHY rem=2) from 1-beat replay (all others)
