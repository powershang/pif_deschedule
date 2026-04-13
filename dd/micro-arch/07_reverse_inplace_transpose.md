# reverse_inplace_transpose

## Function

Converts chunk format back to per-lane-per-cycle format using two 8x8 ping-pong buffers. This is the **inverse** of `inplace_transpose_buf_8lane_2beat`: the forward module writes columns and reads rows (per-lane-per-cycle → chunk), while this module writes rows and reads columns (chunk → per-lane-per-cycle).

Each input beat writes one row (LANE8) or half a row (LANE4) into the write buffer. Column-wise readout from the completed buffer produces one sample per lane per cycle — the original per-lane-per-cycle format.

## Interface

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| clk | in | 1 | Clock (= descheduler clk_out, slow clock) |
| rst_n | in | 1 | Active-low async reset |
| lane_cfg | in | 1 | 0=LANE8 (8 lanes), 1=LANE4 (4 lanes) |
| valid_in | in | 1 | Input valid (chunk data from descheduler) |
| din_top0..3 | in | DATA_W | Top 4 samples of chunk |
| din_bot0..3 | in | DATA_W | Bottom 4 samples of chunk (0 in LANE4 mode) |
| valid_out | out | 1 | Output valid (per-lane-per-cycle data) |
| dout0..7 | out | DATA_W | 8-lane output (per-lane-per-cycle) |

## Architecture

### Ping-pong Buffers

Two 8x8 matrices (`buf_0`, `buf_1`), each holding 8 rows x 8 columns of DATA_W-wide samples.

- **Write side**: fills one buffer while the other is being read
- **Read side**: column-wise readout = matrix transpose
- `wr_sel` selects the active write buffer; the opposite buffer is available for read

### State Machine

```
         fresh_burst
             │
             ▼
    ┌─── INIT_FILL ───┐
    │   (fill buf_0)   │
    │   8 beats        │
    │   no output      │
    └────────┬─────────┘
             │ wr_last (buffer full)
             ▼
    ┌──── STREAM ──────┐
    │  write buf_X     │◄──┐
    │  read buf_Y      │   │ wr_last (swap)
    │  ping-pong       │───┘
    └──────────────────┘
```

- **INIT_FILL**: First 8 beats fill `buf_0`. No output during this phase. On buffer full, transition to STREAM, flip `wr_sel`, pulse `rd_start`.
- **STREAM**: Continuous ping-pong. Write new data into `wr_sel` buffer while reading from the opposite buffer. On each buffer full, flip `wr_sel` and pulse `rd_start`.
- **Fresh burst** (`valid_in` rising edge): Reset to INIT_FILL from any state.

### Write Path

**LANE8 mode** (lane_cfg=0):
- 1 row per beat: `buf[wr_row][0..7] = {din_top0..3, din_bot0..3}`
- 8 beats fill one 8x8 buffer (wr_row: 0→7)
- Buffer full when `wr_row == 7`

**LANE4 mode** (lane_cfg=1):
- 2 beats per row (half-row each): beat0 writes `buf[wr_row][0..3]`, beat1 writes `buf[wr_row][4..7]`
- Only uses din_top0..3 (din_bot is 0 in LANE4)
- 4 rows x 2 beats = 8 beats fill one buffer (wr_row: 0→3)
- Buffer full when `wr_row == 3 && l4_beat == 1`

### Read Path

Column-wise readout produces the transpose:

```
dout[lane] = buf[lane][rd_col]    for lane = 0..7
```

- Triggered by `rd_start` pulse (one cycle after INIT_FILL→STREAM transition or buffer swap)
- `rd_col` sweeps 0→7 over 8 cycles
- `valid_out` asserts for 8 consecutive cycles per read burst
- `rd_sel` latched at read start to select the just-completed buffer

### Partial Flush

In STREAM state only, if `valid_in` drops before the write buffer is full (mid-burst termination):

1. Zero-fill all remaining rows in the current write buffer
2. Flip `wr_sel`, pulse `rd_start`
3. Read proceeds normally — zero-filled rows produce zero output for unused lanes

## Timing

### Fixed 9T Latency (all modes identical)

```
Beat:  T0   T1   T2   T3   T4   T5   T6   T7 | T8    T9   T10  ...
State: ------------ INIT_FILL --------------- | ---- STREAM -----
Write: row0 row1 row2 row3 row4 row5 row6 row7| row0' row1' row2' ...  (new data to buf_1)
Read:  -    -    -    -    -    -    -    -    | -     col0  col1  ... (from buf_0)
Valid: 0    0    0    0    0    0    0    0    | 0     1     1     ...
```

Note: `valid_out` first asserts at T9, not T8. The INIT_FILL→STREAM transition happens at T7 (NBA), `rd_start` pulses at T7, read data is captured at T8 (NBA), and `valid_out` asserts at T8 (NBA) — visible at T9.

### LANE8 Example (8L mode)

Input (chunk format from descheduler, one chunk per beat):
```
beat0: din = {L0[0],L0[1],L0[2],L0[3], L0[4],L0[5],L0[6],L0[7]}   ← Lane0 chunk
beat1: din = {L1[0],L1[1],L1[2],L1[3], L1[4],L1[5],L1[6],L1[7]}   ← Lane1 chunk
...
beat7: din = {L7[0],L7[1],L7[2],L7[3], L7[4],L7[5],L7[6],L7[7]}   ← Lane7 chunk
```

Buffer contents after fill (row = lane, col = time):
```
        col0    col1    col2    col3    col4    col5    col6    col7
row0:  L0[0]  L0[1]  L0[2]  L0[3]  L0[4]  L0[5]  L0[6]  L0[7]
row1:  L1[0]  L1[1]  L1[2]  L1[3]  L1[4]  L1[5]  L1[6]  L1[7]
...
row7:  L7[0]  L7[1]  L7[2]  L7[3]  L7[4]  L7[5]  L7[6]  L7[7]
```

Column-wise readout (dout[lane] = buf[lane][rd_col]):
```
rd_col=0: dout = {L0[0], L1[0], L2[0], ..., L7[0]}  ← all lanes, time 0
rd_col=1: dout = {L0[1], L1[1], L2[1], ..., L7[1]}  ← all lanes, time 1
...
rd_col=7: dout = {L0[7], L1[7], L2[7], ..., L7[7]}  ← all lanes, time 7
```

This is exactly the per-lane-per-cycle format: each output cycle carries one sample from every lane.

### LANE4 Example (4L mode)

Input (chunk format, 2 beats per lane chunk):
```
beat0: din_top = {L0[0],L0[1],L0[2],L0[3]}  → buf[0][0..3]
beat1: din_top = {L0[4],L0[5],L0[6],L0[7]}  → buf[0][4..7]
beat2: din_top = {L1[0],L1[1],L1[2],L1[3]}  → buf[1][0..3]
beat3: din_top = {L1[4],L1[5],L1[6],L1[7]}  → buf[1][4..7]
...
beat6: din_top = {L3[0],L3[1],L3[2],L3[3]}  → buf[3][0..3]
beat7: din_top = {L3[4],L3[5],L3[6],L3[7]}  → buf[3][4..7]
```

Column-wise readout:
```
rd_col=0: dout = {L0[0], L1[0], L2[0], L3[0], 0, 0, 0, 0}
rd_col=1: dout = {L0[1], L1[1], L2[1], L3[1], 0, 0, 0, 0}
...
```

Rows 4-7 are zero (only 4 lanes), so dout4..7 = 0.

## Error Handling

- **Fresh burst** (`valid_in` rising edge after gap): resets to INIT_FILL, discards partial data
- **Mid-burst valid drop** (STREAM state): triggers partial flush with zero-fill, ensures buffered data is output
- **Mid-burst valid drop** (INIT_FILL state): data in buf_0 is silently discarded (no output was started)
