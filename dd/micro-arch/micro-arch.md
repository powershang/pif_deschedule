# inplace_transpose_buf_multi_lane_descheduler Microarchitecture Specification

**Version:** 1.0
**Date:** 2026-04-01
**Status:** Draft

---

## 1. Overview

`inplace_transpose_buf_multi_lane_descheduler` 是 `inplace_transpose_buf_multi_lane_scheduler`（序列化器）的反向模組。接收來自快時鐘域的 4-lane 序列化資料，收集 N/4 拍後，在慢時鐘域一次性輸出還原的 N-lane 資料。

主要特性：
- 支援 4 / 8 / 12 / 16 lane 模式，由 lane_mode[1:0] 選擇
- **clk_in = 快時鐘**（收集端）、**clk_out = 慢時鐘**（輸出端）— 與前級相反
- 12L 模式具有奇偶週期反旋轉機制（de-rotation）
- 同源 PLL，posedge 對齊，不需 CDC

### 1.1 Pipeline 架構

```
  din[0:3] ──▶ [clk_in: collect N/4 phases] ──▶ [clk_out 1T: de-rotate MUX + output DFF] ──▶ output
               ├── clk_in (fast) domain ────┤    ├── clk_out (slow) domain ──────────────┤
```

### 1.2 Top-level Block Diagram

```
                  ┌──────────────────────────────────────────────────────┐
                  │     inplace_transpose_buf_multi_lane_descheduler      │
                  │                                                        │
  valid_in  ─────▶│  [clk_in (fast)]            [clk_out (slow)]         │
  din[0:3]  ─────▶│  ┌──────────────┐  col_p*  ┌────────────────┐        │
                  │  │ Collection    │─────────▶│ De-rotation    │        │
                  │  │ FSM + Buffer  │  done    │ MUX + Out DFF  │──▶ a_top[0:3] │
                  │  │ + phase cnt   │─────────▶│                │──▶ a_bot[0:3] │
                  │  │ + odd/even    │          │                │──▶ b_top[0:3] │
                  │  └──────────────┘          │                │──▶ b_bot[0:3] │
                  │                             └────────────────┘──▶ valid_out  │
  lane_mode ─────▶│                                                        │
  clk_in   ──────▶│                                                        │
  clk_out  ──────▶│                   dbg_state[2:0], dbg_fifo_cnt[3:0]   │
  rst_n    ──────▶│                                                        │
                  └──────────────────────────────────────────────────────┘
```

---

## 2. Interface

### 2.1 Port List

| Port Name | Direction | Width | Description |
|-----------|-----------|-------|-------------|
| clk_in | input | 1 | 快時鐘，驅動收集 FSM 和 phase buffer |
| clk_out | input | 1 | 慢時鐘，驅動反旋轉 MUX 和輸出 DFF |
| rst_n | input | 1 | Active-low 非同步重置 |
| lane_mode[1:0] | input | 2 | 模式選擇：00=4L, 01=8L, 10=12L, 11=16L |
| valid_in | input | 1 | 輸入資料有效（clk_in domain） |
| din0 ~ din3 | input | 32 each | 4-lane 序列化輸入資料 |
| valid_out | output | 1 | 輸出資料有效（clk_out domain） |
| a_top0 ~ a_top3 | output | 32 each | Group A top 還原輸出 |
| a_bot0 ~ a_bot3 | output | 32 each | Group A bot 還原輸出 |
| b_top0 ~ b_top3 | output | 32 each | Group B top 還原輸出 |
| b_bot0 ~ b_bot3 | output | 32 each | Group B bot 還原輸出 |
| dbg_state[2:0] | output | 3 | 除錯：收集 FSM 狀態（in_state） |
| dbg_fifo_cnt[3:0] | output | 4 | 除錯：{1'b0, in_phase} |

### 2.2 Clock Relationship

```
clk_in（快時鐘）：基準時鐘，period = T
clk_out（慢時鐘）：頻率 = clk_in / N

  4L:  N=1  clk_out = clk_in
  8L:  N=2  clk_out = clk_in / 2
  12L: N=3  clk_out = clk_in / 3
  16L: N=4  clk_out = clk_in / 4
```

---

## 3. Functional Description

### 3.1 收集邏輯（clk_in domain）

| Mode | Phase 0 | Phase 1 | Phase 2 | Phase 3 | FSM 拍數 |
|------|---------|---------|---------|---------|---------|
| 4L   | din→col_p0 | - | - | - | 1（IDLE） |
| 8L   | din→col_p0 | din→col_p1 | - | - | 2 |
| 12L  | din→col_p0 | din→col_p1 | din→col_p2 | - | 3 |
| 16L  | din→col_p0 | din→col_p1 | din→col_p2 | din→col_p3 | 4 |

### 3.2 反旋轉 MUX（clk_out domain）

| Mode | in_cycle_odd_latch | a_top source | a_bot source | b_top source | b_bot source |
|------|-------------------|-------------|-------------|-------------|-------------|
| 4L   | -                 | col_p0      | -           | -           | -           |
| 8L   | -                 | col_p0      | col_p1      | -           | -           |
| 12L  | 0 (even)          | col_p0      | col_p1      | col_p2      | -           |
| 12L  | 1 (odd)           | col_p1      | col_p2      | col_p0      | -           |
| 16L  | -                 | col_p0      | col_p1      | col_p2      | col_p3      |

### 3.3 12L 反旋轉說明

前級序列化器的 12L Rotation Rule：
- 偶數週期：a_top → a_bot → b_top
- 奇數週期：b_top → a_top → a_bot（右移旋轉）

反向電路收集後需要還原：
- 偶數週期：col_p0=a_top, col_p1=a_bot, col_p2=b_top → 直通
- 奇數週期：col_p0=b_top, col_p1=a_top, col_p2=a_bot → 反旋轉
  - a_top ← col_p1, a_bot ← col_p2, b_top ← col_p0

### 3.4 奇偶追蹤

- `in_cycle_odd_cnt`：clk_in domain，每次收集窗口開始時 toggle
- `in_cycle_odd_latch`：窗口開始時 snapshot pre-toggle 值
- valid_in rising edge（`valid_in & ~valid_in_d1`）重置為 even（新 burst）

### 3.5 Reset 行為

rst_n 拉低時（非同步）：
- in_state 回到 IDLE
- in_phase 清零
- in_cycle_odd_cnt 清零
- 所有 col_p*、output DFF 清零
- valid_out 拉低

---

## 4. FSM 說明

### 4.1 FSM 狀態定義

| State | Encoding | 說明 |
|-------|----------|------|
| IDLE | 3'd0 | 等待 valid_in |
| COLLECT_4L | 3'd1 | 未使用（4L 單拍完成） |
| COLLECT_8L | 3'd2 | 8L 收集中 |
| COLLECT_12L | 3'd3 | 12L 收集中 |
| COLLECT_16L | 3'd4 | 16L 收集中 |

### 4.2 FSM 優先順序

```
if (in_state != IDLE) begin
    // 最高優先：busy 中推進 phase，收集 din
    // in_phase == phase_max → in_state <= IDLE + collection_done
    // 否則 in_phase <= in_phase + 1
end else if (valid_in) begin
    // 次優先：idle 且有 valid → 啟動新收集窗口
    // 擷取 phase 0，設定 in_state <= COLLECT_xL
end
```

### 4.3 phase_max

| in_state | phase_max | 說明 |
|----------|-----------|------|
| COLLECT_4L | 0 | 未使用 |
| COLLECT_8L | 1 | 2 phases |
| COLLECT_12L | 2 | 3 phases |
| COLLECT_16L | 3 | 4 phases |

---

## 5. 時序圖

### 5.1 16L 模式

```
clk_in (fast):  | R0 | R1 | R2 | R3 | R4 | R5 | R6 | R7 |
clk_out (slow): |<── W0 ──────────>|<── W1 ──────────>|

valid_in:       |  1 |  1 |  1 |  1 |  1 |  1 |  1 |  1 |
din:            | a_top a_bot b_top b_bot | a_top a_bot b_top b_bot |
collection_done:|  0    0    0    1  |  0    0    0    1  |
valid_out:      |  0  |           1  |             1     |
output:         |     | a_top/a_bot/b_top/b_bot | a_top/a_bot/b_top/b_bot |
```

### 5.2 12L 模式（偶→奇）

```
clk_in (fast):  | R0 | R1 | R2 | R3 | R4 | R5 |
clk_out (slow): |<── W0(even) ──>|<── W1(odd) ───>|

din:            | a_top a_bot b_top | b_top a_top a_bot |
collection_done:|  0    0    1  |  0    0    1  |

Output W0 (even, direct):
  a_top=col_p0, a_bot=col_p1, b_top=col_p2

Output W1 (odd, de-rotated):
  a_top=col_p1, a_bot=col_p2, b_top=col_p0
```

---

## 6. 驗證考量

### 關鍵測試場景

1. **4L 直通**：din → a_top，latency 驗證
2. **8L 2-phase**：收集 2 拍 → a_top/a_bot 還原
3. **16L 4-phase**：收集 4 拍 → a_top/a_bot/b_top/b_bot 還原
4. **12L 偶數**：直通映射驗證
5. **12L 奇數**：反旋轉映射驗證
6. **12L 連續多週期**：偶→奇→偶交替正確
7. **Loopback**：串接 scheduler → descheduler，驗證 identity
8. **rst_n 復位**：確認所有暫存器清零

### 設計決策

| # | 問題 | 決策 |
|---|------|------|
| 1 | collection_done 跨域方式？ | **registered 1T in clk_in, sampled by clk_out（同源 PLL 安全）** |
| 2 | 12L 奇偶追蹤？ | **clk_in domain in_cycle_odd_cnt，rising edge 重置為 even** |
| 3 | Pipeline latency？ | **收集 N/4 rclk + wclk 1T** |
