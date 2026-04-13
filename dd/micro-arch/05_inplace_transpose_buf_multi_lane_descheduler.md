# inplace_transpose_buf_multi_lane_descheduler

## Function

4-lane to N-lane deserializer (Stage 1 of two-stage descheduler). Receives serialized 4-lane data on fast clock (clk_in), collects N/4 phases, applies 12L de-rotation, and outputs de-rotated data in **chunk format** on slow clock (clk_out). One pulse of `valid_out` per collection toggle.

The output is in chunk format (same as forward `inplace_transpose_buf_8lane_2beat` output), **not** per-lane-per-cycle format. The downstream `reverse_inplace_transpose` module performs the chunk-to-per-lane-per-cycle conversion.

## Interface

| Port | Dir | Width | Domain | Description |
|------|-----|-------|--------|-------------|
| clk_in | in | 1 | fast | Serialized input clock |
| clk_out | in | 1 | slow | Chunk output clock |
| rst_n | in | 1 | — | Active-low async reset |
| lane_mode | in | 2 | — | 00=4L, 01=8L, 10=12L, 11=16L |
| valid_in | in | 1 | clk_in | Input valid |
| din0..3 | in | DATA_W | clk_in | 4-lane serialized input |
| valid_out | out | 1 | clk_out | Output valid (one pulse per toggle) |
| a_top0..3, a_bot0..3 | out | DATA_W | clk_out | Group A chunk output |
| b_top0..3, b_bot0..3 | out | DATA_W | clk_out | Group B chunk output |

## Architecture

### clk_in domain: Collection FSM + Hold Buffer

```
din → col_p* (phase buffer) → hold_p* (snapshot) → flip col_done_toggle
```

- **FSM states**: IDLE, COLLECT_4L, COLLECT_8L, COLLECT_12L, COLLECT_16L
- 4L: single-phase, snapshot directly (no FSM needed)
- 8L/12L/16L: collect N/4 phases, then snapshot to hold_p*
- **Hold buffer**: prevents data corruption in back-to-back mode

### clk_out domain: Toggle Detection + De-rotation MUX + Chunk Output

- Detects `col_done_toggle` change → one pulse of `valid_out`
- Applies 12L de-rotation MUX to restore correct group assignment
- Outputs de-rotated data directly in chunk format (no accumulation, no streaming)

---

## Output Format

The descheduler output is in **chunk format**:

- Each output pulse carries one chunk per active group (a_top, a_bot, b_top, b_bot)
- Each chunk contains 4 consecutive samples from the same lane (e.g., a_top = {L0[0], L0[1], L0[2], L0[3]})
- This is the same format as the forward `inplace_transpose_buf_8lane_2beat` output
- One `valid_out` pulse per slow clock cycle when a collection completes

---

## 12L De-rotation

### Scheduler 12L Phase Sequence (rotation at source)

The scheduler applies rotation on odd cycles to balance timing:

```
S0 (even): phase0 = a_top, phase1 = a_bot, phase2 = b_top
S1 (odd) : phase0 = b_top, phase1 = a_top, phase2 = a_bot  ← ROTATED!
S2 (even): phase0 = a_top, phase1 = a_bot, phase2 = b_top
S3 (odd) : phase0 = b_top, phase1 = a_top, phase2 = a_bot  ← ROTATED!
```

### Descheduler De-rotation MUX

The descheduler must undo the rotation. `hold_cycle_odd` tracks whether the collected data came from an even or odd scheduler cycle:

```
Even (hold_cycle_odd=0): derot_at = hold_p0 (a_top), derot_ab = hold_p1 (a_bot), derot_bt = hold_p2 (b_top)
Odd  (hold_cycle_odd=1): derot_at = hold_p1 (a_top), derot_ab = hold_p2 (a_bot), derot_bt = hold_p0 (b_top)
```

MUX implementation (per data index):
```verilog
derot_at = (MODE_12L && hold_cycle_odd) ? hold_p1 : hold_p0;
derot_ab = (MODE_12L && hold_cycle_odd) ? hold_p2 : hold_p1;
derot_bt = (MODE_12L && hold_cycle_odd) ? hold_p0 : hold_p2;
derot_bb = hold_p3;  // 16L only, no rotation
```

For non-12L modes, the MUX passthrough is correct: hold_p0→a_top, hold_p1→a_bot, hold_p2→b_top, hold_p3→b_bot.

---

## Use Cases + Timing Diagrams

### Case 1: 4L mode

clk_in = clk_out (same clock, ratio 1:1)

Descheduler receives chunks from scheduler:
```
clk_in:     |  R0  |  R1  |  R2  |  R3  |
valid_in:   |  1   |  1   |  1   |  1   |
din:        | {0,1,2,3} | {4,5,6,7} | {8,9,10,11} | {12,13,14,15} |
```

Descheduler output (chunk format, one toggle per input beat):
```
clk_out:    |  W0  |  W1  |  W2  |  W3  |  W4  |
valid_out:  |  0   |  1   |  1   |  1   |  1   |
a_top:      |  -   | {0,1,2,3} | {4,5,6,7} | {8,9,10,11} | {12,13,14,15} |
a_bot:      |  all 0 |
b_top/bot:  |  all 0 |
```

### Case 2: 8L mode

clk_in = fast (10ns), clk_out = slow (20ns), ratio 2:1.

Descheduler receives 2 phases per slow cycle:
```
clk_in:     | R0 | R1 | R2 | R3 | R4 | R5 | R6 | R7 | ...
valid_in:   | 1  | 1  | 1  | 1  | 1  | 1  | 1  | 1  | ...
din:        |{0,1,2,3}|{4,5,6,7}|{8,9,10,11}|{12,13,14,15}|...

phase:      | 0  | 1→done | 0  | 1→done | ...
```

Descheduler output (chunk format):
```
clk_out:    |<── W0 ──>|<── W1 ──>|<── W2 ──>| ...
valid_out:  |    0     |    1     |    1     | ...
a_top:      |    -     |{0,1,2,3} |{8,9,10,11}| ...   ← Lane0 chunk, Lane1 chunk, ...
a_bot:      |    -     |{4,5,6,7} |{12,13,14,15}| ... ← Lane4 chunk, Lane5 chunk, ...
b_top/bot:  |  all 0   |
```

### Case 3: 16L mode

clk_in = fast (10ns), clk_out = slow (40ns), ratio 4:1.

Descheduler receives 4 phases per slow cycle:
```
phase:      | 0  | 1  | 2  | 3→done | 0  | 1  | 2  | 3→done |
```

Descheduler output (chunk format):
```
clk_out:    |<────── W0 ──────>|<────── W1 ──────>| ...
valid_out:  |        0         |        1         | ...
a_top:      |        -         | a_top_chunk      | ...
a_bot:      |        -         | a_bot_chunk      | ...
b_top:      |        -         | b_top_chunk      | ...
b_bot:      |        -         | b_bot_chunk      | ...
```

### Case 4: 12L mode (with de-rotation)

clk_in = fast (10ns), clk_out = slow (30ns), ratio 3:1.

Descheduler receives 3 phases per slow cycle (with rotation on odd cycles):
```
--- Even cycle 0: phase0=a_top_chunk, phase1=a_bot_chunk, phase2=b_top_chunk ---
--- Odd cycle 1:  phase0=b_top_chunk, phase1=a_top_chunk, phase2=a_bot_chunk (rotated) ---
```

De-rotation MUX restores correct assignment:
```
Even: a_top=hold_p0(a_top), a_bot=hold_p1(a_bot), b_top=hold_p2(b_top)  ← direct
Odd:  a_top=hold_p1(a_top), a_bot=hold_p2(a_bot), b_top=hold_p0(b_top)  ← de-rotated
```

Descheduler output (chunk format, after de-rotation):
```
clk_out:    |<── W0 (even) ──>|<── W1 (odd) ───>| ...
valid_out:  |       0         |       1          | ...
a_top:      |       -         | a_top_chunk      | ...
a_bot:      |       -         | a_bot_chunk      | ...
b_top:      |       -         | b_top_chunk      | ...
b_bot:      |       all 0     |
```

---

## Error Handling

- If valid_in drops mid-collection (in_state != IDLE && !valid_in): abort to IDLE
- Partial collection data discarded; next valid_in starts fresh
- `in_cycle_odd` resets on valid_in rising edge (fresh burst = even)
