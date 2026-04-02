# inplace_transpose_buf_8lane_2beat

## Function

Unified chunk accumulation block. Collects N-lane input data over multiple cycles, accumulates into 8-sample chunks, and streams out via a FIFO. Supports runtime configuration as LANE8 or LANE4.

## Interface

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| clk | in | 1 | Clock |
| rst_n | in | 1 | Active-low async reset |
| valid_in | in | 1 | Input data valid |
| lane_cfg | in | 1 | 0=LANE8, 1=LANE4 |
| mode | in | 2 | 00=PHY, 01=VLANE |
| din0..din7 | in | DATA_W each | 8-lane input |
| valid_out | out | 1 | Output valid |
| dout_top0..3 | out | DATA_W each | Top 4 samples of chunk |
| dout_bot0..3 | out | DATA_W each | Bottom 4 samples (0 in LANE4 mode) |

---

## LANE8 + PHY mode

每條 physical lane 各自獨立的連續資料流，每條 lane 累積 8 筆後形成一個 8-sample chunk。

### Input Data Pattern

每個 cycle，din0..din7 分別是 8 條 lane 在當前 time slot 的值：

```
         T0    T1    T2    T3    T4    T5    T6    T7
din0:   L0[0] L0[1] L0[2] L0[3] L0[4] L0[5] L0[6] L0[7]
din1:   L1[0] L1[1] L1[2] L1[3] L1[4] L1[5] L1[6] L1[7]
...
din7:   L7[0] L7[1] L7[2] L7[3] L7[4] L7[5] L7[6] L7[7]
```

### Output Order

每筆 output = 一條 lane 的完整 8 sample（top=前4, bot=後4）：

```
out#0: top={L0[0],L0[1],L0[2],L0[3]} bot={L0[4],L0[5],L0[6],L0[7]}
out#1: top={L1[0],L1[1],L1[2],L1[3]} bot={L1[4],L1[5],L1[6],L1[7]}
...
out#7: top={L7[0],L7[1],L7[2],L7[3]} bot={L7[4],L7[5],L7[6],L7[7]}
```

具體例子（DATA_W=8）：

```
Input:
  L0 = 0,1,2,3,4,5,6,7
  L1 = 16,17,18,19,20,21,22,23
  ...

Output:
  out#0 = top={0,1,2,3}   bot={4,5,6,7}
  out#1 = top={16,17,18,19} bot={20,21,22,23}
  ...
```

---

## LANE8 + VLANE mode

paired physical lanes 共同承載同一條 virtual lane（even/odd 拆分），每條 VLane 累積 8 elements 後形成一個 chunk。

### Input Data Pattern

din0+din1 = VLane0 的 even/odd，din2+din3 = VLane1，din4+din5 = VLane2，din6+din7 = VLane3。

每個 cycle 產生 2 個 elements per VLane：

```
         T0         T1         T2         T3
din0:   VL0[0]     VL0[2]     VL0[4]     VL0[6]
din1:   VL0[1]     VL0[3]     VL0[5]     VL0[7]
din2:   VL1[0]     VL1[2]     VL1[4]     VL1[6]
din3:   VL1[1]     VL1[3]     VL1[5]     VL1[7]
din4:   VL2[0]     VL2[2]     VL2[4]     VL2[6]
din5:   VL2[1]     VL2[3]     VL2[5]     VL2[7]
din6:   VL3[0]     VL3[2]     VL3[4]     VL3[6]
din7:   VL3[1]     VL3[3]     VL3[5]     VL3[7]
```

4 cycles 收滿一組（4 VLanes × 8 elements）。

### Output Order

每筆 output = 一條 VLane 的完整 8 elements：

```
out#0: top={VL0[0],VL0[1],VL0[2],VL0[3]} bot={VL0[4],VL0[5],VL0[6],VL0[7]}
out#1: top={VL1[0],VL1[1],VL1[2],VL1[3]} bot={VL1[4],VL1[5],VL1[6],VL1[7]}
out#2: top={VL2[0],VL2[1],VL2[2],VL2[3]} bot={VL2[4],VL2[5],VL2[6],VL2[7]}
out#3: top={VL3[0],VL3[1],VL3[2],VL3[3]} bot={VL3[4],VL3[5],VL3[6],VL3[7]}
```

具體例子：

```
Input:
  din0=0,2,4,6,...  din1=1,3,5,7,...   → VL0 = 0,1,2,3,4,5,6,7
  din2=32,34,...    din3=33,35,...      → VL1 = 32,33,34,35,...

Output:
  out#0 = top={0,1,2,3}   bot={4,5,6,7}
  out#1 = top={32,33,34,35} bot={36,37,38,39}
  ...
```

---

## LANE4 + PHY mode

只使用 din0..din3，din4..din7 忽略。每條 lane 累積 8 筆後輸出，分成 2-beat stream：

```
out#0: top={L0[0],L0[1],L0[2],L0[3]} bot={0,0,0,0}   (beat0)
out#1: top={L0[4],L0[5],L0[6],L0[7]} bot={0,0,0,0}   (beat1)
out#2: top={L1[0],L1[1],L1[2],L1[3]} bot={0,0,0,0}
out#3: top={L1[4],L1[5],L1[6],L1[7]} bot={0,0,0,0}
...
```

---

## LANE4 + VLANE mode

din0+din1 = VLane0 (even/odd)，din2+din3 = VLane1。4 cycles 收滿，2-beat stream：

```
out#0: top={VL0[0],VL0[1],VL0[2],VL0[3]} bot={0,0,0,0}
out#1: top={VL0[4],VL0[5],VL0[6],VL0[7]} bot={0,0,0,0}
out#2: top={VL1[0],VL1[1],VL1[2],VL1[3]} bot={0,0,0,0}
out#3: top={VL1[4],VL1[5],VL1[6],VL1[7]} bot={0,0,0,0}
```

---

## Internal Architecture

- **phy_acc[8][8]**: PHY mode accumulator (8 lanes × 8 time slots)
- **vl_acc[4][8]**: VLANE mode accumulator (4 VLanes × 8 elements)
- **fifo_mem[16][8]**: Output FIFO (16 entries × 8 samples)
- **phase_cnt**: counts 0..7 (PHY) or 0..3 (VLANE, wrapping)
- **state**: INIT_FILL → STREAM

## Startup Timing

All modes: T0..T7 accumulate → T9 first visible output.

## Error Handling

- Fresh burst (valid_in rising edge): soft reset phase_cnt, state, FIFO pointers
- Interrupted bursts discard partial accumulator data
