# inplace_transpose_buf_multi_lane_scheduler

## Function

N-lane to 4-lane serializer. Receives chunk data on slow clock (clk_in), outputs serialized 4-lane data on fast clock (clk_out).

## Interface

| Port | Dir | Width | Domain | Description |
|------|-----|-------|--------|-------------|
| clk_in | in | 1 | slow | Input clock (data side) |
| clk_out | in | 1 | fast | Output clock (serialized side) |
| rst_n | in | 1 | — | Active-low async reset |
| lane_mode | in | 2 | — | 00=4L, 01=8L, 10=12L, 11=16L |
| a_valid_in | in | 1 | clk_in | Group A valid |
| a_top0..3, a_bot0..3 | in | DATA_W | clk_in | Group A data (8 samples) |
| b_valid_in | in | 1 | clk_in | Group B valid |
| b_top0..3, b_bot0..3 | in | DATA_W | clk_in | Group B data (8 samples) |
| valid_out | out | 1 | clk_out | Serialized output valid |
| dout0..3 | out | DATA_W | clk_out | Serialized 4-lane output |

## Pipeline

```
clk_in: a_valid_in → lat_* (1T) → a_valid_w1t
clk_out: win_trigger(=a_valid_w1t) → sched_dout/sched_valid (1T)

Total latency: 1 clk_in + 1 clk_out
```

## Input Data Arrangement (from multi_lane_out)

```
a_top = {sample[0], sample[1], sample[2], sample[3]}  ← 前 4 sample
a_bot = {sample[4], sample[5], sample[6], sample[7]}  ← 後 4 sample
b_top, b_bot 同理（Group B）
```

---

## Use Cases + Timing Diagrams

### Case 1: 4L mode (ratio 1:1)

每個 slow cycle 輸出 1 個 fast beat。

Input（slow clock, from multi_lane_out LANE4 2-beat stream）：
```
clk_in:     | S0 | S1 | S2 | S3 |
a_valid:    | 1  | 1  | 1  | 1  |
a_top:      |{0,1,2,3}|{4,5,6,7}|{16,17,18,19}|{20,21,22,23}|
a_bot:      |{0,0,0,0}|{0,0,0,0}|{0,0,0,0}    |{0,0,0,0}    |
```

Output（fast clock = slow clock）：
```
clk_out:    | F0 | F1 | F2 | F3 | F4 |
valid_out:  | 0  | 0  | 1  | 1  | 1  | 1  |
dout:       |    |    |{0,1,2,3}|{4,5,6,7}|{16,17,18,19}|{20,21,22,23}|
```

### Case 2: 8L mode (ratio 2:1)

每個 slow cycle 輸出 2 個 fast beats。

Input:
```
clk_in:     |<── S0 ──>|<── S1 ──>|
a_valid:    |    1     |    1     |
a_top:      |{0,1,2,3} |{16,17,18,19}|
a_bot:      |{4,5,6,7} |{20,21,22,23}|
```

Output:
```
clk_out:    | F0 | F1 | F2 | F3 | F4 | F5 |
valid_out:  | 0  | 0  | 1  | 1  | 1  | 1  |
dout:       |    |    |a_top0     |a_bot0     |a_top1      |a_bot1      |
            |    |    |{0,1,2,3}  |{4,5,6,7}  |{16,17,18,19}|{20,21,22,23}|
```

### Case 3: 16L mode (ratio 4:1)

每個 slow cycle 輸出 4 個 fast beats。

Input:
```
clk_in:     |<──────── S0 ────────>|<──────── S1 ────────>|
a_valid:    |          1           |          1           |
a_top:      |{10,11,12,13}        |{20,21,22,23}        |
a_bot:      |{14,15,16,17}        |{24,25,26,27}        |
b_top:      |{18,19,1a,1b}        |{28,29,2a,2b}        |
b_bot:      |{1c,1d,1e,1f}        |{2c,2d,2e,2f}        |
```

Output:
```
clk_out:    | F0 | F1 | F2 | F3 | F4 | F5 | F6 | F7 | F8 | F9 |
valid_out:  | 0  | 0  | 1  | 1  | 1  | 1  | 1  | 1  | 1  | 1  |
dout:       |    |    |a_top0|a_bot0|b_top0|b_bot0|a_top1|a_bot1|b_top1|b_bot1|
```

Phase order: a_top → a_bot → b_top → b_bot

### Case 4: 12L mode (ratio 3:1, with rotation)

每個 slow cycle 輸出 3 個 fast beats，偶奇交替旋轉。

Input:
```
clk_in:     |<────── S0 ──────>|<────── S1 ──────>|<────── S2 ──────>|<────── S3 ──────>|
a_valid:    |        1         |        1         |        1         |        1         |
a_top:      |{10,11,12,13}    |{20,21,22,23}    |{30,31,32,33}    |{40,41,42,43}    |
a_bot:      |{14,15,16,17}    |{24,25,26,27}    |{34,35,36,37}    |{44,45,46,47}    |
b_top:      |{18,19,1a,1b}    |{28,29,2a,2b}    |{38,39,3a,3b}    |{48,49,4a,4b}    |
```

Output（注意偶奇 rotation）：
```
clk_out:    | F0 | F1 | F2 | F3 | F4 | F5 | F6 | F7 | F8 | F9 |F10 |F11 |F12 |F13 |
valid_out:  | 0  | 0  | 1  | 1  | 1  | 1  | 1  | 1  | 1  | 1  | 1  | 1  | 1  | 1  |

--- S0 (even): a_top → a_bot → b_top ---
F2: {10,11,12,13}  = a_top
F3: {14,15,16,17}  = a_bot
F4: {18,19,1a,1b}  = b_top

--- S1 (odd, rotated): b_top → a_top → a_bot ---
F5: {28,29,2a,2b}  = b_top  ← 原 phase2 移到 phase0
F6: {20,21,22,23}  = a_top  ← 原 phase0 移到 phase1
F7: {24,25,26,27}  = a_bot  ← 原 phase1 移到 phase2

--- S2 (even): a_top → a_bot → b_top ---
F8:  {30,31,32,33} = a_top
F9:  {34,35,36,37} = a_bot
F10: {38,39,3a,3b} = b_top

--- S3 (odd, rotated): b_top → a_top → a_bot ---
F11: {48,49,4a,4b} = b_top
F12: {40,41,42,43} = a_top
F13: {44,45,46,47} = a_bot
```

### 12L Rotation 說明

目的：確保 serialized bus 上每個 time slot 對應到固定的 physical lane group，減少 lane-level timing skew。

| Cycle parity | Phase 0 | Phase 1 | Phase 2 |
|-------------|---------|---------|---------|
| Even | a_top | a_bot | b_top |
| Odd | b_top | a_top | a_bot |

對 descheduler 來說，需要做反旋轉（de-rotation）才能還原。

---

## 12L Rotation Tracking

- `out_cycle_odd_cnt`：clk_out domain，每次 `win_trigger` 時 toggle
- `out_cycle_odd_latch`：`win_trigger` 時 snapshot pre-toggle value（= 本 window 的 parity）
- Fresh burst（`win_trigger` rising edge）：reset `out_cycle_odd_cnt` to 0（even start）

## Error Handling

- Fresh burst detection via `win_trigger_prev`: resets 12L odd/even counter
- FSM naturally returns to IDLE after completing phase_max
