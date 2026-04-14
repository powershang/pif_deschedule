# lanedata_8n_align_process

## Function

Burst padding preprocessor. Observes a continuous `valid_in` burst, and if the
length is not a multiple of 8, appends pad beats so the total output length
becomes a multiple of 8 (8N).

Padding uses a **unified pattern** (independent of rem parity):

    pad sequence = { c_{N-1}, cN, c_{N-1}, cN, ... }   // always starts from c_{N-1}

where `cN` = last input beat, `c_{N-1}` = beat before last.

### Input invariant vs. defensive error_flag

System-level invariant: burst length is guaranteed even (rem in {0,2,4,6}). The
RTL still pads correctly for odd rem and raises `error_flag` to expose any
upstream violation.

| rem (= len mod 8) | pad_total | replay sequence                                  | error_flag |
|-------------------|-----------|--------------------------------------------------|-----------|
| 0                 | 0         | -                                                | 0         |
| 1                 | 7         | c_{N-1}, cN, c_{N-1}, cN, c_{N-1}, cN, c_{N-1}   | **1**     |
| 2                 | 6         | c_{N-1}, cN, c_{N-1}, cN, c_{N-1}, cN            | 0         |
| 3                 | 5         | c_{N-1}, cN, c_{N-1}, cN, c_{N-1}                | **1**     |
| 4                 | 4         | c_{N-1}, cN, c_{N-1}, cN                         | 0         |
| 5                 | 3         | c_{N-1}, cN, c_{N-1}                             | **1**     |
| 6                 | 2         | c_{N-1}, cN                                      | 0         |
| 7                 | 1         | c_{N-1}                                          | **1**     |

## Interface

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| clk | in | 1 | Clock |
| rst_n | in | 1 | Active-low async reset |
| valid_in | in | 1 | Input data valid |
| virtual_lane_en | in | 1 | **Accepted for port compatibility with the old 4N block; does not affect behavior** (8N alignment applies uniformly to PHY and VLANE). |
| din0..din15 | in | DATA_W each | 16-lane input data |
| valid_out | out | 1 | Output data valid (registered, 1T latency) |
| dout0..dout15 | out | DATA_W each | 16-lane output data |
| error_flag | out | 1 | Set when rem is odd (invariant violation); sticky within the burst |

---

## Use Cases + Timing Diagrams

### Case 1: len=8 (rem=0, no pad)

```
cycle:      0   1   2   3   4   5   6   7   8   9
valid_in:   1   1   1   1   1   1   1   1   0   0
din[0]:    D0  D1  D2  D3  D4  D5  D6  D7   -   -

valid_out:  0   1   1   1   1   1   1   1   1   0
dout[0]:    -  D0  D1  D2  D3  D4  D5  D6  D7   -
error_flag: 0
```

### Case 2: len=6 (rem=6, pad 2 beats)

```
cycle:      0   1   2   3   4   5   6   7   8
valid_in:   1   1   1   1   1   1   0   0   0
din[0]:    D0  D1  D2  D3  D4  D5   -   -   -

valid_out:  0   1   1   1   1   1   1   1   1
dout[0]:    -  D0  D1  D2  D3  D4  D5  D4  D5
                                        pad: c_{N-1}, cN
error_flag: 0
```

### Case 3: len=4 (rem=4, pad 4 beats)

```
cycle:      0   1   2   3   4   5   6   7   8
valid_in:   1   1   1   1   0   0   0   0   0
din[0]:    D0  D1  D2  D3   -   -   -   -   -

valid_out:  0   1   1   1   1   1   1   1   1
dout[0]:    -  D0  D1  D2  D3  D2  D3  D2  D3
                                    pad: c_{N-1}, cN, c_{N-1}, cN
error_flag: 0
```

### Case 4: len=2 (rem=2, pad 6 beats)

```
cycle:      0   1   2   3   4   5   6   7   8   9
valid_in:   1   1   0   0   0   0   0   0   0   0
din[0]:    D0  D1   -   -   -   -   -   -   -   -

valid_out:  0   1   1   1   1   1   1   1   1   0
dout[0]:    -  D0  D1  D0  D1  D0  D1  D0  D1   -
                        pad: c_{N-1}, cN, c_{N-1}, cN, c_{N-1}, cN
error_flag: 0
```

### Case 5: len=5 (rem=5, ERROR, pad 3 beats)

```
cycle:      0   1   2   3   4   5   6   7   8
valid_in:   1   1   1   1   1   0   0   0   0
din[0]:    D0  D1  D2  D3  D4   -   -   -   -

valid_out:  0   1   1   1   1   1   1   1   1
dout[0]:    -  D0  D1  D2  D3  D4  D3  D4  D3
                                    pad: c_{N-1}, cN, c_{N-1}
error_flag: 1  (raised at cycle 5, sticky)
```

---

## Micro-architecture

### State

| Reg | Width | Purpose |
|-----|-------|---------|
| `tail_buf[0..1][0..15]` | 2 x 16 x DATA_W | Ring buffer of the last 2 input beats |
| `tail_buf_top_q` | 1 | Slot index that currently holds cN (last beat); the other slot holds c_{N-1} |
| `beat_mod_q` | 3 | Input beat counter mod 8 |
| `pad_active_q` | 1 | Padding in progress |
| `pad_left_q` | 3 | Remaining pad beats after the current one |
| `replay_idx_q` | 1 | Slot to emit on the next pad cycle; toggles every pad cycle |
| `prev_valid_q` | 1 | `valid_in` from previous cycle (edge detect) |
| `error_flag_q` | 1 | Sticky error within a burst |

### Data flow

1. **Input phase** (`valid_in=1`)
   - Fresh burst: write beat into `tail_buf[0]`, `tail_buf_top_q <= 0`, `beat_mod_q <= 1`, clear sticky state.
   - Continuing: write into `tail_buf[~tail_buf_top_q]`, flip `tail_buf_top_q`, increment `beat_mod_q` mod 8.
   - `dout_vec` passes the input beat straight through, `valid_out=1`.

2. **Burst end** (`prev_valid_q=1 && valid_in=0`)
   - `rem_now = beat_mod_q`; `pad_total = (rem_now==0) ? 0 : 8 - rem_now`.
   - If rem is odd: raise `error_flag_q` (sticky) and `error_flag` (registered).
   - Emit the first pad beat this cycle from `tail_buf[~tail_buf_top_q]` (= c_{N-1}).
   - Set `replay_idx_q <= tail_buf_top_q` so the next pad cycle emits cN.
   - `pad_left_q <= pad_total - 1`; `pad_active_q` high iff more pad beats remain.

3. **Padding phase** (`pad_active_q=1`)
   - Emit `tail_buf[replay_idx_q]`, toggle `replay_idx_q` each cycle.
   - Decrement `pad_left_q`; when it reaches 1, clear `pad_active_q` and reset `beat_mod_q <= 0` on that last pad cycle.

### Key implementation decisions

- **Unified replay via 2-deep tail_buf + toggle**: simpler than the 4N design's
  `replay_base` / `replay_two_q` mechanism. The pattern is always
  `c_{N-1}, cN, c_{N-1}, cN, ...`, so a single toggle suffices.
- **`tail_buf_top_q` flips every input beat**: identifies cN vs c_{N-1} at
  burst end regardless of length or parity. No extra bookkeeping needed.
- **error_flag is sticky within a burst** (`error_flag_q`): matches the 4N
  module's behavior so downstream consumers see a stable flag until the next
  fresh burst clears it.
- **virtual_lane_en is tied to an unused wire**: retained for scheduler_top
  port compatibility. 8N alignment is applied uniformly; VLANE no longer has
  a 2-beat alignment fast path.
