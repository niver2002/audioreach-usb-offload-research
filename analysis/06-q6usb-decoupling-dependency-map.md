# q6usb 解耦依赖图（面向 AudioReach/GPR）

## 文档日期

2026-02-26

---

## 目标

把 Linux 主线 `q6usb.c` 当前的 APR/AFE 耦合点拆清楚，明确“最小可落地改动”边界，支撑方向 E（最小化内核修改）验证。

---

## 一、当前上游依赖拓扑（HEAD）

### 1.1 q6usb 的关键调用链

`q6usb_hw_params()` 当前逻辑：

1. `snd_soc_usb_find_supported_format(...)`
2. `q6afe_port_get_from_id(cpu_dai->dev, USB_RX)`
3. `afe_port_send_usb_dev_param(q6usb_afe, card_idx, pcm_idx)`

关键点：步骤 2/3 来自 `q6afe.h`，是 APR/AFE 栈专属能力。

### 1.2 编译时硬耦合

当前 `q6usb.c` 直接包含：

```c
#include <dt-bindings/sound/qcom,q6afe.h>
#include "q6afe.h"
```

这会把 `q6usb` 固定到 AFE 语义，即使系统主音频栈使用 q6apm/GPR。

### 1.3 实际上已经“中立”的部分

`q6usb.c` 的这些路径本身不依赖 q6apm 或 q6afe：

1. `snd_soc_usb_*` 端口注册与连接通知
2. jack / route kcontrol 管理
3. auxiliary device `qc-usb-audio-offload` 创建
4. `q6usb_offload` 中 IOMMU/SID/intr 参数传递

结论：真正阻塞点集中在 `q6usb_hw_params()` 的 AFE 通知路径，而不是整个驱动框架。

---

## 二、与 `soc-usb` / `qc_audio_offload` 的关系

### 2.1 `soc-usb` 角色

`soc-usb.c` 提供通用桥接 API：

- `snd_soc_usb_connect/disconnect`
- `snd_soc_usb_update_offload_route`
- `snd_soc_usb_find_supported_format`

它不感知 q6apm/GPR，也不绑定 AFE，属于“可复用的中立层”。

### 2.2 `qc_audio_offload` 角色

`qc_audio_offload.c` 负责：

1. QMI UAUDIO 控制面
2. XHCI sideband 资源分配
3. IOMMU 映射

这条路径与 q6afe 无直接绑定，是方向 E 能成立的基础。

---

## 三、最小解耦方案（工程切分）

### 3.1 目标状态

在不破坏 APR 平台现有行为的前提下，使 `q6usb` 能在 AudioReach/GPR 平台注册并完成基础 offload 路由。

### 3.2 分阶段改动

1. 把 `q6usb.c` 中 AFE 专用调用抽象为可选后端（APR 可用时走原路径）。
2. 增加 AudioReach 路径所需的 USB 媒体格式参数入口（`audioreach.*`）。
3. 在 `q6apm-lpass-dais.c` 为 USB DAI 绑定 `hw_params`/生命周期 ops。
4. 在 DTS 中将 USB BE 连接到 q6apm 侧 CPU DAI（保持现有 q6usb codec 端）。

### 3.3 可维护性约束

1. APR 行为必须二进制等价或功能等价（Fairphone 5 类平台回归风险最低）。
2. 先做 playback；capture 在 `soc-usb.h` 中本身仍有“未完整验证”注释。
3. 所有新增字段必须明确来源：`usb_token`、`svc_interval`、`card/pcm route`。

---

## 四、与本仓库现有补丁的映射

| 补丁 | 作用 | 对应解耦阶段 |
|------|------|--------------|
| `0001` | `audioreach.h` 增加 USB module/param 定义 | 阶段 2 |
| `0002` | `audioreach.c` 增加 USB media format 下发 | 阶段 2 |
| `0003` | `q6apm-lpass-dais.c` 增加 USB DAI ops | 阶段 3 |
| `0004` | `q6usb.c` 去除 q6afe 硬依赖 | 阶段 1 |
| `0005` | DTS 增加 AudioReach USB offload 链路 | 阶段 4 |
| `0006` | Kconfig/help 更新 | 支撑性 |

---

## 五、当前仍需实证的问题

1. `q6usb_hw_params()` 去 AFE 后，USB 设备选择信息由谁最终注入图配置（q6apm 侧）需要明确单一真源。
2. `usb_token` 与 `svc_interval` 是否可由现有 QMI 事件链稳定映射，需真实日志验证。
3. 热插拔时 route 更新与 graph re-prepare 的竞态窗口，需压测（插拔 + 多 stream）。

---

## 六、结论

上游现状下，`q6usb` 不是“全盘重写”问题，而是一个“局部耦合点解耦”问题：

1. 框架层已具备中立桥接（soc-usb）。
2. 数据面已具备独立通道（QMI + XHCI sideband）。
3. 真正缺口集中在 q6apm 图配置与 `q6usb_hw_params` 的历史 AFE 绑定。

因此方向 E 仍是当前最具性价比的工程路径。
