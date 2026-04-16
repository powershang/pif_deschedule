# lanedata_8n_align_process

## Function

Burst padding preprocessor with **dual alignment mode**. Observes a continuous
`valid_in` burst and pads the output so the downstream sees aligned data.

| Mode | `align_mode` | Behavior |
|------|-------------|----------|
| 8N-mode | 1 | Pad with Cn/Cn+1 replay until total output length is a multiple of 8 |
| 4N-mode | 0 | Phase 1: pad with Cn/Cn+1 replay until length is a multiple of 4. Phase 2: unconditionally append 4 zero beats. |

### tail_buf semantics

Fixed-index buffer (not a ring buffer):

| Slot | Content | Written when |
|------|---------|-------------|
| `tail_buf[0]` | Cn -- beat 0 of the current chunk | `beat_mod_q == 0` (and at fresh burst start) |
| `tail_buf[1]` | Cn+1 -- beat 1 of the current chunk | `beat_mod_q == 1` |

No writes occur for beats 2..7 within a chunk. Replay always starts from
**Cn** (`tail_buf[0]`), then alternates Cn+1, Cn, Cn+1, ...

The old `tail_buf_top_q` ring-buffer pointer has been removed.

### Input invariant vs. defensive error_flag

System-level invariant: burst length is guaranteed even (rem in {0,2,4,6}).
The RTL still pads correctly for odd rem and raises `error_flag` to expose any
upstream violation.

### 8N-mode padding rules

| rem = len mod 8 | pad_total | replay sequence (from Cn) | error_flag |
|---|---|---|---|
| 0 | 0 | -- | 0 |
| 2 | 6 | Cn, Cn+1, Cn, Cn+1, Cn, Cn+1 | 0 |
| 4 | 4 | Cn, Cn+1, Cn, Cn+1 | 0 |
| 6 | 2 | Cn, Cn+1 | 0 |
| 1,3,5,7 | 8-rem | don't care | **1** |

### 4N-mode padding rules

**Phase 1** (pad to next multiple of 4):

| rem4 = len mod 4 | pad_phase1 | replay sequence (from Cn) | error_flag |
|---|---|---|---|
| 0 | 0 | -- | 0 |
| 2 | 2 | Cn, Cn+1 | 0 |
| 1,3 | 4-rem4 | don't care | **1** |

Cn, Cn+1 here refer to beat 0 and beat 1 of the current chunk (the most
recent chunk boundary seen by `beat_mod_q`).

**Phase 2** (unconditional zero fill): 4 beats of all-zero data.

Total pad = pad_phase1 + 4. Output total length = ceil(input_len / 4) * 4 + 4.

## Interface

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| clk | in | 1 | Clock |
| rst_n | in | 1 | Active-low async reset |
| valid_in | in | 1 | Input data valid |
| align_mode | in | 1 | 0 = 4N-align, 1 = 8N-align |
| virtual_lane_en | in | 1 | **Accepted for port compatibility; does not affect behavior** |
| din0..din15 | in | DATA_W each | 16-lane input data |
| valid_out | out | 1 | Output data valid (registered, 1T latency) |
| dout0..dout15 | out | DATA_W each | 16-lane output data |
| error_flag | out | 1 | Set when rem is odd (invariant violation); sticky within the burst |

---

## Use Cases + Timing Diagrams

All timing diagrams show signals **after** the posedge (registered output has
1T latency relative to input).

### 8N-mode Cases

#### Case 1: 8N, len=8 (rem=0, no pad)

```
align_mode = 1

cycle:      0   1   2   3   4   5   6   7   8   9
valid_in:   1   1   1   1   1   1   1   1   0   0
din[0]:    D0  D1  D2  D3  D4  D5  D6  D7   -   -

valid_out:  0   1   1   1   1   1   1   1   1   0
dout[0]:    -  D0  D1  D2  D3  D4  D5  D6  D7   -
error_flag: 0
```

#### Case 2: 8N, len=6 (rem=6, pad 2 beats)

```
align_mode = 1

cycle:      0   1   2   3   4   5   6   7   8   9
valid_in:   1   1   1   1   1   1   0   0   0   0
din[0]:    D0  D1  D2  D3  D4  D5   -   -   -   -

valid_out:  0   1   1   1   1   1   1   1   1   0
dout[0]:    -  D0  D1  D2  D3  D4  D5  D0  D1   -
                                    pad: Cn, Cn+1
error_flag: 0

Cn=D0, Cn+1=D1 (chunk 0 beat 0/1; only one 8-beat chunk started)
```

#### Case 3: 8N, len=4 (rem=4, pad 4 beats)

```
align_mode = 1

cycle:      0   1   2   3   4   5   6   7   8   9
valid_in:   1   1   1   1   0   0   0   0   0   0
din[0]:    D0  D1  D2  D3   -   -   -   -   -   -

valid_out:  0   1   1   1   1   1   1   1   1   0
dout[0]:    -  D0  D1  D2  D3  D0  D1  D0  D1   -
                                pad: Cn, Cn+1, Cn, Cn+1
error_flag: 0

Cn=D0, Cn+1=D1
```

#### Case 4: 8N, len=2 (rem=2, pad 6 beats)

```
align_mode = 1

cycle:      0   1   2   3   4   5   6   7   8   9
valid_in:   1   1   0   0   0   0   0   0   0   0
din[0]:    D0  D1   -   -   -   -   -   -   -   -

valid_out:  0   1   1   1   1   1   1   1   1   0
dout[0]:    -  D0  D1  D0  D1  D0  D1  D0  D1   -
                    pad: Cn, Cn+1, Cn, Cn+1, Cn, Cn+1
error_flag: 0

Cn=D0, Cn+1=D1
```

#### Case 5: 8N, len=10 (rem=2, pad 6 beats, multi-chunk)

```
align_mode = 1

cycle:      0   1   2   3   4   5   6   7   8   9  10  11  12  13  14  15  16  17
valid_in:   1   1   1   1   1   1   1   1   1   1   0   0   0   0   0   0   0   0
din[0]:    D0  D1  D2  D3  D4  D5  D6  D7  D8  D9   -   -   -   -   -   -   -   -

valid_out:  0   1   1   1   1   1   1   1   1   1   1   1   1   1   1   1   1   0
dout[0]:    -  D0  D1  D2  D3  D4  D5  D6  D7  D8  D9  D8  D9  D8  D9  D8  D9   -
                                                        pad: Cn, Cn+1 x3
error_flag: 0

beat_mod_q wraps to 0 after D7 (8th input beat), starting chunk 1.
Cn=D8 (chunk 1 beat 0), Cn+1=D9 (chunk 1 beat 1).
```

#### Case 6: 8N, len=5 (rem=5, ERROR, pad 3 beats)

```
align_mode = 1

cycle:      0   1   2   3   4   5   6   7   8   9
valid_in:   1   1   1   1   1   0   0   0   0   0
din[0]:    D0  D1  D2  D3  D4   -   -   -   -   -

valid_out:  0   1   1   1   1   1   1   1   1   0
dout[0]:    -  D0  D1  D2  D3  D4  D0  D1  D0   -
                                    pad: Cn, Cn+1, Cn
error_flag: 1  (raised at burst end, sticky)

Cn=D0, Cn+1=D1
```

---

### 4N-mode Cases

#### Case 7: 4N, len=4 (rem4=0, phase1=0, phase2=4 zeros)

```
align_mode = 0

cycle:      0   1   2   3   4   5   6   7   8   9
valid_in:   1   1   1   1   0   0   0   0   0   0
din[0]:    D0  D1  D2  D3   -   -   -   -   -   -

valid_out:  0   1   1   1   1   1   1   1   1   0
dout[0]:    -  D0  D1  D2  D3   0   0   0   0   -
                                phase2: 4 zero beats
error_flag: 0

rem4 = 4 mod 4 = 0 => no phase1 replay. Phase 2 appends 4 zeros.
Output length = 4 + 4 = 8.
```

#### Case 8: 4N, len=6 (rem4=2, phase1=2, phase2=4 zeros)

```
align_mode = 0

cycle:      0   1   2   3   4   5   6   7   8   9  10  11  12  13
valid_in:   1   1   1   1   1   1   0   0   0   0   0   0   0   0
din[0]:    D0  D1  D2  D3  D4  D5   -   -   -   -   -   -   -   -

valid_out:  0   1   1   1   1   1   1   1   1   1   1   1   1   0
dout[0]:    -  D0  D1  D2  D3  D4  D5  Cn Cn+1  0   0   0   0   -
                                    phase1: Cn,Cn+1  phase2: 4 zeros
error_flag: 0

rem4 = 6 mod 4 = 2. pad_phase1 = 2: replay Cn, Cn+1.
Cn=D0, Cn+1=D1 (chunk 0 beat 0/1).
Output length = 6 + 2 + 4 = 12.
```

#### Case 9: 4N, len=8 (rem4=0, phase1=0, phase2=4 zeros)

```
align_mode = 0

cycle:      0   1   2   3   4   5   6   7   8   9  10  11  12  13
valid_in:   1   1   1   1   1   1   1   1   0   0   0   0   0   0
din[0]:    D0  D1  D2  D3  D4  D5  D6  D7   -   -   -   -   -   -

valid_out:  0   1   1   1   1   1   1   1   1   1   1   1   1   0
dout[0]:    -  D0  D1  D2  D3  D4  D5  D6  D7   0   0   0   0   -
                                             phase2: 4 zero beats
error_flag: 0

rem4 = 0. No phase1 replay. Phase 2 appends 4 zeros.
Output length = 8 + 4 = 12.
```

#### Case 10: 4N, len=2 (rem4=2, phase1=2, phase2=4 zeros)

```
align_mode = 0

cycle:      0   1   2   3   4   5   6   7   8   9
valid_in:   1   1   0   0   0   0   0   0   0   0
din[0]:    D0  D1   -   -   -   -   -   -   -   -

valid_out:  0   1   1   1   1   1   1   1   1   0
dout[0]:    -  D0  D1  Cn Cn+1  0   0   0   0   -
                    phase1:Cn,Cn+1  phase2: 4 zeros
error_flag: 0

Cn=D0, Cn+1=D1. Output length = 2 + 2 + 4 = 8.
```

---

## Micro-architecture

### State

| Reg | Width | Purpose |
|-----|-------|---------|
| `tail_buf[0..1][0..15]` | 2 x 16 x DATA_W | Fixed-index buffer: slot 0 = Cn (chunk beat 0), slot 1 = Cn+1 (chunk beat 1) |
| `beat_mod_q` | 3 | Input beat counter mod 8 |
| `pad_active_q` | 1 | Phase 1 replay padding in progress |
| `pad_left_q` | 3 | Remaining phase 1 pad beats (including current emit) |
| `replay_idx_q` | 1 | Slot to emit on the next pad cycle; toggles every cycle |
| `phase2_active_q` | 1 | Phase 2 zero-fill in progress (4N-mode only) |
| `phase2_left_q` | 3 | Remaining phase 2 zero beats |
| `prev_valid_q` | 1 | `valid_in` from previous cycle (edge detect) |
| `error_flag_q` | 1 | Sticky error within a burst |

### Data flow

1. **Input phase** (`valid_in=1`)
   - Fresh burst (`prev_valid_q=0`): write beat into `tail_buf[0]` as Cn,
     set `beat_mod_q <= 1`, clear all sticky / phase state.
   - Continuing: pass data through. Write `tail_buf[0]` when `beat_mod_q == 0`
     (new chunk boundary), write `tail_buf[1]` when `beat_mod_q == 1`. No
     tail_buf writes for beats 2..7. Increment `beat_mod_q` mod 8.
   - `dout_vec` = input beat, `valid_out=1`.

2. **Burst end** (`prev_valid_q=1 && valid_in=0`)
   - **8N-mode** (`align_mode=1`):
     - `rem_now = beat_mod_q`; `pad_total = (rem_now==0) ? 0 : 8 - rem_now`.
     - If rem is odd: raise `error_flag_q` (sticky).
     - If `pad_total > 0`: emit first pad beat from `tail_buf[0]` (Cn), set
       `replay_idx_q <= 1` so the next cycle emits Cn+1. Set
       `pad_left_q <= pad_total - 1`, `pad_active_q` high iff more remain.
     - If `pad_total == 0`: burst already aligned, reset `beat_mod_q`.
   - **4N-mode** (`align_mode=0`):
     - `rem4 = beat_mod_q[1:0]`; `pad_phase1 = (rem4==0) ? 0 : 4 - rem4`.
     - If rem4 is odd: raise `error_flag_q` (sticky).
     - If `pad_phase1 > 0`: emit first pad beat from `tail_buf[0]` (Cn), set
       `replay_idx_q <= 1`. If `pad_phase1 == 1`, skip directly to phase 2
       (set `phase2_active_q`, `phase2_left_q <= 4`). Otherwise, enter
       `pad_active_q` for the remaining phase 1 beats.
     - If `pad_phase1 == 0`: emit first zero beat immediately, set
       `phase2_active_q`, `phase2_left_q <= 3`.

3. **Phase 1 padding** (`pad_active_q=1`)
   - Emit `tail_buf[replay_idx_q]`, toggle `replay_idx_q`.
   - Decrement `pad_left_q`. When it reaches 1:
     - 8N-mode: clear `pad_active_q`, reset `beat_mod_q`.
     - 4N-mode: clear `pad_active_q`, transition to phase 2
       (`phase2_active_q <= 1`, `phase2_left_q <= 4`).

4. **Phase 2 zero-fill** (`phase2_active_q=1`, 4N-mode only)
   - Emit all-zero data on all lanes. `valid_out=1`.
   - Decrement `phase2_left_q`. When it reaches 1: clear `phase2_active_q`,
     reset `beat_mod_q`.

### Key implementation decisions

- **Fixed-index tail_buf** replaces the old ring-buffer + `tail_buf_top_q`.
  Only beat 0 and beat 1 of each chunk are captured; no pointer tracking
  needed. The replay pattern always starts from `tail_buf[0]` (Cn).
- **`align_mode` selects 8N vs 4N** at burst end. The input phase and
  tail_buf capture logic are shared; the mode only affects how `pad_total` /
  `pad_phase1` are computed and whether phase 2 follows.
- **Phase 2 zero-fill** is unconditional in 4N-mode (always 4 beats),
  providing a known gap that downstream logic can use as a delimiter.
- **error_flag is sticky within a burst** (`error_flag_q`): downstream
  consumers see a stable flag until the next fresh burst clears it.
- **virtual_lane_en** is retained for `scheduler_top` port compatibility
  but tied to an unused wire internally.
