# USB Audio Offload on QCS6490 (Radxa Q6A) — 深度研究增量报告 v3

## 研究日期：2026-02-26
## 对比基线：`DEEP_RESEARCH_2026-02-25.md`（2026-02-25）
## 核验范围：Linux 主线内核 + AudioReach 上游仓库 + 本项目 GitHub 状态

---

## 零、结论先行（今天的增量结论）

截至 **2026-02-26**，相对 2026-02-25 的结论没有出现新的上游解锁点：

1. Linux 主线仍未把 USB offload 接入 AudioReach/q6apm 路径。
2. `q6usb.c` 仍然硬依赖 `q6afe`（APR/AFE 栈），未解耦到 q6apm。
3. AudioReach SPF/PAL 侧 USB 模块定义依旧完整，说明“固件/用户空间准备好，内核桥接缺失”的判断继续成立。
4. 本研究仓库在 GitHub 上仍无 open PR、无 issue，最近 push 时间仍是 2026-02-25。

---

## 一、Linux 主线增量核验（相对 2026-02-25）

### 1.1 关键文件提交增量（`since=2026-02-25T00:00:00Z`）

| 路径 | 2/25 后新提交 | 最近一次提交 | 结论 |
|------|---------------|--------------|------|
| `sound/soc/qcom/qdsp6/q6usb.c` | 无 | `f74aa1e909e7` (2025-11-17) | 仍未解耦 q6afe |
| `sound/soc/qcom/qdsp6/q6apm-lpass-dais.c` | 无 | `f7a5195c2d28` (2025-09-16) | 仍无 USB DAI 逻辑 |
| `sound/soc/qcom/qdsp6/audioreach.h` | 无 | `4ab48cc63e15` (2025-12-22) | 仍无 USB module ID |
| `sound/soc/soc-usb.c` | 无 | `bf4afc53b77a` (2026-02-22) | 仅通用 soc-usb 维护 |
| `sound/usb/qcom/qc_audio_offload.c` | 无 | `189f164e573e` (2026-02-22) | 无 AudioReach 专项接入 |
| `include/sound/q6usboffload.h` | 无 | `72b0b8b29980` (2025-04-11) | 接口稳定，无新增桥接字段 |
| `include/sound/soc-usb.h` | 无 | `234ed325920c` (2025-04-11) | 仍是通用 API，未感知 q6apm |

> 说明：`soc-usb.c` 与 `qc_audio_offload.c` 在 2026-02-22 有更新，但都早于 2026-02-25 基线，不构成今天的新解锁。

### 1.2 符号级复核（HEAD 内容）

#### A. `q6usb.c` 仍直接绑定 AFE

仍可见：

```c
#include <dt-bindings/sound/qcom,q6afe.h>
#include "q6afe.h"
...
q6usb_afe = q6afe_port_get_from_id(cpu_dai->dev, USB_RX);
...
ret = afe_port_send_usb_dev_param(q6usb_afe, ...);
```

这说明 q6usb 的关键通知路径仍经由 AFE，不是 q6apm。

#### B. `q6apm-lpass-dais.c` 仍无 USB 相关逻辑

文件仍只有 `q6dma/q6i2s/q6hdmi` 相关 ops 配置，没有 USB 专用 `hw_params` 或 `q6usb_ops`。

#### C. `audioreach.h` 仍无 USB 模块定义

仍未出现：
- `MODULE_ID_USB_AUDIO_SINK` (`0x0700104F`)
- `MODULE_ID_USB_AUDIO_SOURCE` (`0x07001050`)
- `PARAM_ID_USB_AUDIO_INTF_CFG` (`0x080010D6`)

#### D. `soc-usb.c` 仍为中立桥接层

`soc-usb.c` 仍只做 SoC USB 上下文管理（connect/disconnect/route/jack），未直接感知 q6apm/GPR。

---

## 二、AudioReach 上游核验（SPF/PAL）

### 2.1 SPF: USB API 仍完整存在

`audioreach-graphservices/spf/api/modules/usb_api.h` 仍定义：

```c
#define MODULE_ID_USB_AUDIO_SINK     0x0700104F
#define MODULE_ID_USB_AUDIO_SOURCE   0x07001050
#define PARAM_ID_USB_AUDIO_INTF_CFG  0x080010D6
```

该文件最近提交：`9b412bded584`（2026-01-30），提交信息为版权/SPDX 维护，不是功能变更。

### 2.2 PAL: USB 图配置与 payload 路径仍在

- `session/src/PayloadBuilder.cpp` 仍有 `PARAM_ID_USB_AUDIO_INTF_CFG` 与 `payloadUsbAudioConfig(...)`。
- `configs/qcm6490/usecaseKvManager.xml` 仍有 USB RX/TX 设备图项（`0xA2000005` / `0xA3000005`）。

两者最近提交均为 `39d15d243c05`（2024-10-30，初始提交）。

---

## 三、本仓库 GitHub 状态（研究项目本身）

对 `niver2002/audioreach-usb-offload-research` 的远端核验：

- 默认分支：`main`
- open PR：0
- issues（all）：空列表
- 最近 push：`2026-02-25T09:36:47Z`

结论：目前仍是“文档与补丁草案驱动”的研究阶段，没有外部 PR/issue 反馈流进入。

---

## 四、方向 B / E 的可行性更新（2026-02-26）

### 4.1 方向 B（q6apm 完整支持）状态

仍可行，但工作量不变，且上游暂无现成切入点：

1. `audioreach.h` 补 USB module/param 定义
2. `audioreach.c` 增加 USB media format 参数下发
3. `q6apm-lpass-dais.c` 补 USB DAI ops
4. `q6usb.c` 去除 AFE 硬依赖

### 4.2 方向 E（最小化改动）状态

仍是当前最现实的研究路径，原因不变：

- USB 数据通道核心在 QMI + XHCI sideband（`qc_audio_offload.c`）
- 图配置在 q6apm/GPR
- 主要卡点是 `q6usb -> q6afe` 的历史耦合

新增风险提醒：

1. APR 平台兼容性必须保留（不能破坏 Fairphone 5 等现有路径）。
2. Capture 路径在 `soc-usb.h` 仍有 “not tested yet” 注释，验证优先级应先放 playback。
3. `usb_token/svc_interval` 的来源与同步路径需要在 q6apm 图配置里有清晰归属（避免重复配置或竞态）。

---

## 五、与 2026-02-25 报告相比的“新增信息”

今天新增的不是“新机制”，而是“新时间点核验结果”：

1. 用 2026-02-26 的时间窗再次确认：关键阻塞文件在 2/25 之后仍无相关提交。
2. 确认 `soc-usb.c` / `qc_audio_offload.c` 最近提交点都在 2026-02-22，且非架构解锁改动。
3. 确认项目远端协作状态仍为 PR=0 / Issue=0，后续推进仍需本仓库主动输出可审阅材料（RFC patch 或验证日志）。

---

## 六、下一步执行建议（可直接落地）

1. 以现有 `patches/0001~0006` 为基础整理一版“可编译验证分支”，优先验证 playback。
2. 在本仓库补充 `q6usb` 解耦依赖图（已新增 `analysis/06-q6usb-decoupling-dependency-map.md`）。
3. 准备面向上游的 RFC 描述模板：明确“保留 APR 行为 + 新增 AudioReach 路径”的兼容策略与测试矩阵。

---

## 附录：本次核验使用的关键 API 查询（可复现）

```text
GET repos/torvalds/linux/commits?path=sound/soc/qcom/qdsp6/q6usb.c&since=2026-02-25T00:00:00Z
GET repos/torvalds/linux/commits?path=sound/soc/qcom/qdsp6/q6apm-lpass-dais.c&since=2026-02-25T00:00:00Z
GET repos/torvalds/linux/commits?path=sound/soc/qcom/qdsp6/audioreach.h&since=2026-02-25T00:00:00Z
GET repos/torvalds/linux/commits?path=sound/soc/soc-usb.c&since=2026-02-25T00:00:00Z
GET repos/torvalds/linux/commits?path=sound/usb/qcom/qc_audio_offload.c&since=2026-02-25T00:00:00Z
GET repos/audioreach/audioreach-graphservices/commits?path=spf/api/modules/usb_api.h&per_page=1
GET repos/audioreach/audioreach-pal/commits?path=session/src/PayloadBuilder.cpp&per_page=1
GET repos/niver2002/audioreach-usb-offload-research/issues?state=all&per_page=30
```

