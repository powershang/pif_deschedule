# inplace_transpose_buf_multi_lane_descheduler

## Function

4-lane to N-lane deserializer. Receives serialized 4-lane data on fast clock (clk_in), reassembles into N-lane output on slow clock (clk_out). Reverse of the scheduler.

## Interface

| Port | Dir | Width | Domain | Description |
|------|-----|-------|--------|-------------|
| clk_in | in | 1 | fast | Serialized input clock |
| clk_out | in | 1 | slow | Restored output clock |
| rst_n | in | 1 | — | Active-low async reset |
| lane_mode | in | 2 | — | 00=4L, 01=8L, 10=12L, 11=16L |
| valid_in | in | 1 | clk_in | Input valid |
| din0..3 | in | DATA_W | clk_in | 4-lane serialized input |
| valid_out | out | 1 | clk_out | Output valid |
| a_top0..3, a_bot0..3 | out | DATA_W | clk_out | Group A output |
| b_top0..3, b_bot0..3 | out | DATA_W | clk_out | Group B output |

## Architecture

### clk_in domain: Collection FSM + Hold Buffer

```
din → col_p* (phase buffer) → hold_p* (snapshot) → flip col_done_toggle
```

- **FSM states**: IDLE, COLLECT_8L, COLLECT_12L, COLLECT_16L
- 4L: single-phase, snapshot directly (no FSM needed)
- 8L/12L/16L: collect N/4 phases, then snapshot to hold_p*
- **Hold buffer**: prevents data corruption in back-to-back mode

### clk_out domain: Toggle Detection + De-rotation MUX

- Detects `col_done_toggle` change → latches hold_p* through de-rotation MUX

---

## Use Cases + Timing Diagrams

### Case 1: 4L mode

clk_in = clk_out (same clock, ratio 1:1)

Input: single phase, direct pass-through.

```
clk_in:     |  R0  |  R1  |  R2  |  R3  |  R4  |
valid_in:   |  1   |  1   |  1   |  1   |  0   |
din:        | {10,11,12,13} | {20,21,22,23} | {30,31,32,33} | {40,41,42,43} |

Collection: snapshot hold_p0 = din immediately, flip toggle

clk_out:    |  W0  |  W1  |  W2  |  W3  |  W4  |  W5  |
valid_out:  |  0   |  1   |  1   |  1   |  1   |  0   |
a_top:      |  -   | {10,11,12,13} | {20,21,22,23} | {30,31,32,33} | {40,41,42,43} |
a_bot:      |  -   | {0,0,0,0} | ... |
b_top/bot:  |  all 0 |
```

### Case 2: 8L mode

clk_in = fast (10ns), clk_out = slow (20ns), ratio 2:1.

Input: 2 phases per slow cycle (phase0=a_top, phase1=a_bot).

```
clk_in:     | R0 | R1 | R2 | R3 | R4 | R5 | R6 | R7 |
valid_in:   | 1  | 1  | 1  | 1  | 1  | 1  | 1  | 1  |
din:        |a_top0|a_bot0|a_top1|a_bot1|a_top2|a_bot2|a_top3|a_bot3|
            |{10,..,13}|{14,..,17}|{20,..,23}|{24,..,27}|{30,..,33}|{34,..,37}|{40,..,43}|{44,..,47}|

phase:      | 0  | 1→done | 0  | 1→done | 0  | 1→done | 0  | 1→done |

clk_out:    |<── W0 ──>|<── W1 ──>|<── W2 ──>|<── W3 ──>|<── W4 ──>|
valid_out:  |    0     |    1     |    1     |    1     |    1     |
a_top:      |    -     |{10,11,12,13}|{20,21,22,23}|{30,31,32,33}|{40,41,42,43}|
a_bot:      |    -     |{14,15,16,17}|{24,25,26,27}|{34,35,36,37}|{44,45,46,47}|
b_top/bot:  |  all 0   |
```

### Case 3: 16L mode

clk_in = fast (10ns), clk_out = slow (40ns), ratio 4:1.

Input: 4 phases per slow cycle (a_top, a_bot, b_top, b_bot).

```
clk_in:     | R0 | R1 | R2 | R3 | R4 | R5 | R6 | R7 |
valid_in:   | 1  | 1  | 1  | 1  | 1  | 1  | 1  | 1  |
din:        |a_top0|a_bot0|b_top0|b_bot0|a_top1|a_bot1|b_top1|b_bot1|
            |{10,..,13}|{14,..,17}|{18,..,1b}|{1c,..,1f}|{20,..,23}|{24,..,27}|{28,..,2b}|{2c,..,2f}|

phase:      | 0  | 1  | 2  | 3→done | 0  | 1  | 2  | 3→done |

clk_out:    |<────── W0 ──────>|<────── W1 ──────>|
valid_out:  |        0         |        1         |        1         |
a_top:      |        -         |{10,11,12,13}     |{20,21,22,23}     |
a_bot:      |        -         |{14,15,16,17}     |{24,25,26,27}     |
b_top:      |        -         |{18,19,1a,1b}     |{28,29,2a,2b}     |
b_bot:      |        -         |{1c,1d,1e,1f}     |{2c,2d,2e,2f}     |
```

### Case 4: 12L mode (with de-rotation)

clk_in = fast (10ns), clk_out = slow (30ns), ratio 3:1.

Scheduler 的 12L rotation：
- Even cycle output: a_top, a_bot, b_top
- Odd cycle output: b_top, a_top, a_bot (rotated)

Descheduler 收到的 serialized data 帶有 rotation，需要反旋轉還原。

```
clk_in:     | R0 | R1 | R2 | R3 | R4 | R5 | R6 | R7 | R8 | R9 |R10 |R11 |
valid_in:   | 1  | 1  | 1  | 1  | 1  | 1  | 1  | 1  | 1  | 1  | 1  | 1  |

--- Even cycle 0 (scheduler sent: a_top, a_bot, b_top) ---
din R0: {10,11,12,13}  = a_top0
din R1: {14,15,16,17}  = a_bot0
din R2: {18,19,1a,1b}  = b_top0

--- Odd cycle 1 (scheduler sent: b_top, a_top, a_bot — rotated!) ---
din R3: {28,29,2a,2b}  = b_top1 (was phase2, now phase0)
din R4: {20,21,22,23}  = a_top1 (was phase0, now phase1)
din R5: {24,25,26,27}  = a_bot1 (was phase1, now phase2)

--- Even cycle 2 ---
din R6: {30,31,32,33}  = a_top2
din R7: {34,35,36,37}  = a_bot2
din R8: {38,39,3a,3b}  = b_top2

--- Odd cycle 3 ---
din R9:  {48,49,4a,4b} = b_top3
din R10: {40,41,42,43} = a_top3
din R11: {44,45,46,47} = a_bot3

Descheduler de-rotation output:

clk_out:    |<── W0 (even) ──>|<── W1 (odd) ───>|<── W2 (even) ──>|<── W3 (odd) ───>|
valid_out:  |       0         |       1          |       1          |       1          |       1     |
a_top:      |       -         |{10,11,12,13}     |{20,21,22,23}     |{30,31,32,33}     |{40,41,42,43}|
a_bot:      |       -         |{14,15,16,17}     |{24,25,26,27}     |{34,35,36,37}     |{44,45,46,47}|
b_top:      |       -         |{18,19,1a,1b}     |{28,29,2a,2b}     |{38,39,3a,3b}     |{48,49,4a,4b}|
b_bot:      |       all 0     |

De-rotation MUX:
  Even: a_top=col_p0, a_bot=col_p1, b_top=col_p2 (direct)
  Odd:  a_top=col_p1, a_bot=col_p2, b_top=col_p0 (de-rotated)
```

---

## Error Handling

- If valid_in drops mid-collection (in_state != IDLE && !valid_in): abort to IDLE
- Partial collection data discarded; next valid_in starts fresh
- `in_cycle_odd` resets on valid_in rising edge (fresh burst = even)
