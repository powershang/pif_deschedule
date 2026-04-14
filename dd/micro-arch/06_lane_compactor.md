# lane_compactor

## Function

Dual-clock 4:2 compactor. Captures selected beats from a fast input
stream (reverse-transpose output on `clk_out`) and re-emits full 8-lane
beats at half rate on `clk_out_div2`. Both clocks come from the **same
PLL with a fixed 2:1 phase relation**, so no asynchronous CDC
synchronisers are used.

### 為什麼需要 Compactor

系統中 serialized bus 只有 din[0]/din[1] 承載有效資料，din[2]/din[3] tie-0。Descheduler 忠實還原後，output 每個 group 的 index 2/3 也是 0（half-filled）。此外 reverse-transpose 以 `clk_out` 速率連續輸出 half-filled beats，下游實際需要的是 clk_out/2 速率的完整 beat，因此 compactor 同時負責 (a) 合併 2 筆 half-filled → 1 筆 full、(b) 做時脈域轉換 (`clk_out` → `clk_out_div2`)。

## Clocking

```
clk_in (scheduler 端)
  │   × ratio (PLL)
  ▼
clk_out       -> compactor 輸入時脈 (clk_in_fast)
  │   ÷ 2 (PLL tap，不是 async divider)
  ▼
clk_out_div2  -> compactor 輸出時脈 (clk_out_slow)
```

- `clk_in_fast` 與 `clk_out_slow` 同源、邊緣對齊（`clk_out_slow` 的上升沿對齊 `clk_in_fast` 的偶數上升沿）
- 跨域 path：`reg_a` / `reg_b` 在 `clk_in_fast` 寫、`clk_out_slow` 讀。因為同源固定相位，**不需要 two-flop 同步器、也不需要 toggle-sync**，依 PLL 時序設計即可。
- Reset (`rst_n`) 同源且在兩個域的 flop 都以 `negedge rst_n` 做 async reset。

## Interface

| Port           | Dir | Width   | Description |
|----------------|-----|---------|-------------|
| clk_in_fast    | in  | 1       | = descheduler `clk_out`，輸入側時脈 |
| clk_out_slow   | in  | 1       | = `clk_in_fast / 2` (same PLL)，輸出側時脈 |
| rst_n          | in  | 1       | Active-low async reset |
| valid_in       | in  | 1       | Reverse-transpose 的 `valid_out`（clk_in_fast 域）|
| a_top0..3_in, a_bot0..3_in, b_top0..3_in, b_bot0..3_in | in | DATA_W | 16 路 N-lane 輸入 (8 lane × 2 group) |
| lane_len_0 .. lane_len_15 | in  | 13      | Per-lane beat-count limit (見下方 Per-lane length limiter) |
| valid_out      | out | **16**  | Per-lane compactor 輸出 valid (clk_out_slow 域)；bit i 對應第 i 條 lane |
| a_top0..3, a_bot0..3, b_top0..3, b_bot0..3 | out | DATA_W | 16 路 full output (clk_out_slow 域)。對於超限 lane，bus 維持上一拍值，下游須以 `valid_out[i]` gate |

## Per-lane length limiter

每條 lane 都有一個獨立的 13-bit beat counter `lane_cnt[i]`，搭配對應的 `lane_len_<i>` 上限暫存器，限制該 lane 在「同一段 burst 內」最多可以送出多少 beat。超過後該 lane 的 `valid_out[i]` 拉低，data bus 不變但語意上 don't care。

### Lane 編號 ↔ valid_out bit mapping

| bit | lane     | bit | lane     |
|-----|----------|-----|----------|
| 0   | a_top0   | 8   | b_top0   |
| 1   | a_top1   | 9   | b_top1   |
| 2   | a_top2   | 10  | b_top2   |
| 3   | a_top3   | 11  | b_top3   |
| 4   | a_bot0   | 12  | b_bot0   |
| 5   | a_bot1   | 13  | b_bot1   |
| 6   | a_bot2   | 14  | b_bot2   |
| 7   | a_bot3   | 15  | b_bot3   |

### 行為（每個 `clk_out_slow` cycle，per lane i）

- compactor 內部 valid (`valid_out_inner`) = 1 且 `lane_cnt[i] < lane_len_<i>`：`valid_out[i] = 1`，`lane_cnt[i] += 1`
- compactor 內部 valid = 1 且 `lane_cnt[i] >= lane_len_<i>`：`valid_out[i] = 0`（超限，data bus don't care），counter hold
- compactor 內部 valid = 0 (burst 結束)：`lane_cnt[i] <= 0`（下個 valid 段是新 burst，從零數）

### 關鍵設計決策

- **Burst 邊界使用 `valid_out_inner`**（slow 域），而非 fast 域 `valid_in`：counter 與 valid_out_r 同 clock domain，省掉 CDC，且 burst 結束邊界自然對齊到 slow tick。
- **Data bus 行為**：超限 lane 不單獨 hold per-lane data，整條 16-lane data bus 在 idle 時就會 hold 在最後一筆 valid beat（既有行為），因此「超限 lane data」會 bleed 過去的舊值。下游必須只看 `valid_out[i]` 決定是否取資料。
- **Counter 寬度**：13-bit 上限 = 8191 beats，遠超實際單一 burst 最大長度。
- **Reset**：所有 `lane_cnt[i]` async reset 到 0；burst 結束 (`valid_out_inner == 0`) 也會 sync clear 到 0。

## Operation

### clk_in_fast 域（寫入）

維護一個 2-bit `wr_phase`，在 `valid_in` 期間 0→1→2→3→0 … 循環：

| wr_phase | 動作 |
|----------|------|
| 0 | 把 16 路輸入寫入 **reg_a** |
| 1 | 把 16 路輸入寫入 **reg_b** |
| 2 | 不更新任何 reg（輸入被丟） |
| 3 | 不更新任何 reg（輸入被丟） |

Fresh-burst 偵測：`valid_in` 的 rising edge（`valid_in & ~valid_in_d1`）會強制將當拍的資料存入 reg_a，並把 `wr_phase` 設為 1，保證 burst 第一筆永遠落在 reg_a。`valid_in` 為 0 時 `wr_phase` 歸 0 以備下一個 burst。

### clk_out_slow 域（讀出）

維護一個 1-bit `rd_phase`，在 `valid_in` 期間每個 `clk_out_slow` 上升沿 toggle：

| rd_phase | 輸出來源 |
|----------|----------|
| 0 | `reg_a` → output flops |
| 1 | `reg_b` → output flops |

`valid_out` 直接從 `clk_out_slow` domain sample `valid_in` 並 registered。`valid_in` 為 0 時 `rd_phase` 歸 0，下一個 burst 從 reg_a 開始讀，與 wr 側 fresh-burst 行為對稱。

## Timing (8L PHY，連續 burst 範例)

輸入（`clk_in_fast`，rev 送來 24 拍連續 valid）：

```
cyc:       0   1   2   3   4   5   6   7   8   9   a   b   ...  17
data:      R0  R1  R2  R3  R4  R5  R6  R7  R8  R9  Ra  Rb  ...  R23
wr_phase:  0   1   2   3   0   1   2   3   0   1   2   3
reg_a <=   R0              R4              R8
reg_b <=       R1              R5              R9
(R2,R3,R6,R7,Ra,Rb,... 被丟)
```

輸出（`clk_out_slow` = `clk_in_fast / 2`，對齊偶數 fast cycle）：

```
div2 cyc:  0   1   2   3   4   5   ...  11
rd_phase:  0   1   0   1   0   1
data_out:  R0  R1  R4  R5  R8  R9  ...  R21
valid_out: 1   1   1   1   1   1   ...  1
```

24 個 fast-cycle valid → 12 個 slow-cycle valid 連續。

## Error Handling

- Fresh burst (valid_in 從 0→1)：寫入側把第一筆存到 reg_a，`wr_phase` 從 0 跳到 1；讀出側下一個 `clk_out_slow` edge 以 `rd_phase==0` 取 reg_a。
- 連續兩個 burst 中間必須至少有一個 `valid_in==0` 的 fast cycle，`wr_phase` 才能歸 0。系統實際行為由 rev_transpose 控制。
- `valid_in` 掉下去時 `valid_out` 在下一個 `clk_out_slow` edge 也跟著落下（單級 register delay）。

## Notes

- 所有 16 路 (a_top0..3, a_bot0..3, b_top0..3, b_bot0..3) 都會被存入 reg_a/reg_b，不像舊版只存 lane0/lane1。Group B 若在 4L/8L 模式未啟用，上游會送 0，不影響正確性。
- Synthesis 提示：`reg_a` / `reg_b` 需要 multi-cycle 或 false-path 約束於 `clk_in_fast` → `clk_out_slow`（同源但跨 edge）；由 top-level SDC 管。
