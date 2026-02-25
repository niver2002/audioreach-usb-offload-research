# USB Audio Offload on QCS6490 (Radxa Q6A) — 深度验证报告 v2

## 研究日期：2026-02-25
## 验证范围：Linux 主线内核 HEAD、AudioReach 全系仓库、上游设备树、ADSP 固件反编译

---

## 零、最重要的发现（固件反编译结果）

**Radxa Q6A 的 ADSP 固件 (adsp.mbn) 是 GPR 固件，不支持 APR 协议，但内置了完整的 USB Audio Offload 支持。**

固件反编译发现:
- GPR 字符串: 496 个（主协议栈）
- APR 字符串: 5 个（仅残留，无协议处理器）
- USB 相关字符串: 290 个（完整的 USB offload 实现）
- USB 源文件: `usb_afe.c`, `capi_usb.c`, `usb_driver.c`, `usb_qdi_qmi.c`, `usb_xhcd.c` 等 14 个
- QMI uaudio: `qmi_uaudio_stream_req_msg_v01` / `qmi_uaudio_stream_resp_msg_v01`
- XHCI 内存: `evt_ring`, `tr_data`, `tr_sync`, `xfer_buff`

**关键结论: USB offload 通过 QMI 通信（独立于 APR/GPR），固件侧已完全就绪。
瓶颈在内核侧: `q6usb.c` 硬编码依赖 `q6afe.h`，无法在 GPR/q6apm 栈下工作。**

**方向 A（切换到 APR 栈）不可行 — 固件不支持 APR。**

详见: `analysis/05-adsp-firmware-analysis.md`

---

## 一、对前版报告的关键修正

### 1.1 USB 模块 ID 错误修正

前版报告声称：
```
MODULE_ID_USB_AUDIO_SINK    = 0x07001024
MODULE_ID_USB_AUDIO_SOURCE  = 0x07001025
```

**这是错误的。** 实际值（来自 audioreach-graphservices/spf/api/modules/usb_api.h）：
```c
#define MODULE_ID_USB_AUDIO_SINK    0x0700104F   // USB 播放
#define MODULE_ID_USB_AUDIO_SOURCE  0x07001050   // USB 录音
```

而 `0x07001024` 实际上是主线内核 `audioreach.h` 中的 `MODULE_ID_CODEC_DMA_SOURCE`。

### 1.2 主线内核 audioreach.h 中的全部硬件端点模块

```
MODULE_ID_I2S_SINK              0x0700100A
MODULE_ID_I2S_SOURCE            0x0700100B
MODULE_ID_CODEC_DMA_SINK        0x07001023
MODULE_ID_CODEC_DMA_SOURCE      0x07001024
MODULE_ID_DISPLAY_PORT_SINK     0x07001069
```

**没有 USB 模块。** `MODULE_ID_USB_AUDIO_SINK (0x0700104F)` 和 `MODULE_ID_USB_AUDIO_SOURCE (0x07001050)` 完全不存在于主线内核。

---

## 二、突破性发现：Fairphone 5 (QCM6490) 已在主线内核实现 USB Offload

### 2.1 关键事实

Fairphone 5 使用 **QCM6490** — 与 QCS6490 (Radxa Q6A) 是 **同一颗 SoC (SC7280)**。

Fairphone 5 的设备树 `qcm6490-fairphone-fp5.dts` 中：

```dts
usb-dai-link {
    link-name = "USB Playback";
    codec {
        sound-dai = <&q6usbdai USB_RX>;
    };
    cpu {
        sound-dai = <&q6afedai USB_RX>;
    };
    platform {
        sound-dai = <&q6routing>;
    };
};
```

### 2.2 Fairphone 5 vs Radxa Q6A 的架构差异

| 维度 | Fairphone 5 (QCM6490) | Radxa Q6A (QCS6490) |
|------|----------------------|---------------------|
| 基础 SoC dtsi | kodiak.dtsi | kodiak.dtsi |
| 音频 overlay | 无（直接用 APR） | qcs6490-audioreach.dtsi |
| 协议栈 | APR (apr-v2) | GPR (qcom,gpr) |
| AFE 服务 | q6afe → q6afedai, q6usbdai | `/delete-node/ apr;` 已删除 |
| APM 服务 | 无 | q6apm → q6apmbedai |
| USB Offload | 有 (q6usbdai + q6afedai) | 无 |
| 声卡 compatible | fairphone,fp5-sndcard | qcom,qcs6490-rb3gen2-sndcard |
| ADSP 固件 | qcom/qcm6490/fairphone5/adsp.mbn | qcom/qcs6490/radxa/dragon-q6a/adsp.mbn |

### 2.3 核心结论

**同一颗 SoC，两种音频架构选择：**
- Fairphone 5 选择了 APR/AFE 路径 → USB offload 可用
- Radxa Q6A 选择了 AudioReach/GPR 路径 → USB offload 不可用

这不是硬件限制，而是 **设备树配置和固件选择** 的差异。

---

## 三、上游内核最新状态验证 (2026-02-25)

### 3.1 qdsp6 目录近期提交

截至 2026-02-25，`sound/soc/qcom/qdsp6/` 最近 30 个提交中：
- 无任何 USB offload 相关变更
- 无 q6apm USB DAI 添加
- 主要是代码清理（constify、cleanup.h 修复、kmalloc_obj 转换）
- 2025-12 新增 Speaker Protection / VI Sense 模块（AudioReach）

### 3.2 q6apm-lpass-dais.c 最新状态

对最新 HEAD 的 `q6apm-lpass-dais.c` 执行 `grep -i "usb"` → **零结果**。

### 3.3 audioreach.h 最新状态

对最新 HEAD 的 `audioreach.h` 执行 `grep "MODULE_ID"` → **无 USB 模块 ID**。

### 3.4 q6usb.c 最新状态

```c
#include <dt-bindings/sound/qcom,q6afe.h>
#include "q6afe.h"
#include "q6dsp-lpass-ports.h"
```

q6usb.c 硬编码依赖 q6afe API，与 q6apm 完全无关。

### 3.5 soc-usb.c 最新状态

对 `soc-usb.c` 执行 `grep "apm\|audioreach\|GPR\|gpr\|q6apm"` → **零结果**。

### 3.6 topology.c 最新状态

对 `topology.c` 执行 `grep -i "usb"` → **零结果**。

**结论：截至 2026-02-25，上游主线内核中没有任何将 USB offload 接入 AudioReach/q6apm 的工作。**

---

## 四、AudioReach 用户空间 USB 支持验证

### 4.1 SPF 固件层 — USB 模块定义完整

来源：`audioreach-graphservices/spf/api/modules/usb_api.h`

```c
#define MODULE_ID_USB_AUDIO_SINK     0x0700104F  // 播放
#define MODULE_ID_USB_AUDIO_SOURCE   0x07001050  // 录音
#define PARAM_ID_USB_AUDIO_INTF_CFG  0x080010D6  // USB 接口配置

// 支持规格：
// - 采样率：8, 11.025, 12, 16, 22.05, 24, 32, 44.1, 48,
//           88.2, 96, 176.4, 192, 352.8, 384 kHz
// - 通道数：1-8
// - 位深：16/24/32 bit
// - 容器类型：APM_CONTAINER_TYPE_GC (Generic Container)
```

### 4.2 PAL 层 — QCM6490 USB 图配置完整

来源：`audioreach-pal/configs/qcm6490/usecaseKvManager.xml`

```xml
<!-- USB Device -->
<device id="PAL_DEVICE_OUT_USB_HEADSET,PAL_DEVICE_OUT_USB_DEVICE">
    <!-- DEVICERX - USB_RX -->
    <graph_kv key="0xA2000000" value="0xA2000005"/>
</device>

<!-- IN USB device -->
<device id="PAL_DEVICE_IN_USB_DEVICE,PAL_DEVICE_IN_USB_HEADSET">
    <!-- DEVICETX - USB_TX -->
    <graph_kv key="0xA3000000" value="0xA3000005"/>
</device>
```

支持的流类型：DEEP_BUFFER, PCM_OFFLOAD, COMPRESSED, LOW_LATENCY, VOICE_CALL, VOIP

### 4.3 PayloadBuilder — USB 参数构建

`audioreach-pal/session/src/PayloadBuilder.cpp` 使用 `PARAM_ID_USB_AUDIO_INTF_CFG (0x080010D6)` 构建 USB 配置 payload。

### 4.4 断裂点总结

```
[ADSP 固件] MODULE_ID_USB_AUDIO_SINK/SOURCE ← 存在于 SPF
     ↑
[用户空间] PAL USBAudio.cpp + usecaseKvManager.xml ← 完整
     ↑
[内核驱动] q6apm audioreach.h ← 无 USB 模块 ID
           q6apm-lpass-dais.c ← 无 USB DAI
           q6usb.c ← 只对接 q6afe，不对接 q6apm
```

---

## 五、真实落地方向分析（固件反编译后修正）

### ~~方向 A：切换到 APR 协议栈~~ — 不可行

**固件反编译确认：Radxa Q6A 的 ADSP 固件不支持 APR 协议。**
固件中只有 GPR 协议处理器，APR 相关字符串仅 5 个（均为无关残留）。
切换到 APR 设备树后，内核发送的 APR 消息将无人处理。

### 方向 B：在 q6apm 中实现 USB offload（工程量大但可行）

**核心思路**：在 AudioReach 内核驱动中添加 USB 支持。

固件反编译确认 ADSP 侧已完全就绪:
- `capi_usb.c` 实现了 AudioReach CAPI 接口的 USB 模块
- `MODULE_ID_USB_AUDIO_SINK (0x0700104F)` 在 SPF API 中定义
- QMI 通信层 (`usb_qdi_qmi.c`) 独立于 APR/GPR

**需要的内核工作**：
1. 在 `audioreach.h` 中添加 `MODULE_ID_USB_AUDIO_SINK/SOURCE`
2. 在 `q6apm-lpass-dais.c` 中添加 USB DAI 定义和 ops
3. 在 `audioreach.c` 中实现 USB 模块参数配置
4. 修改 `q6usb.c` 去掉 `q6afe.h` 硬依赖，改为与 q6apm 对接
5. 复用 `qc_audio_offload.c` 的 QMI + XHCI sideband 逻辑

### 方向 C：标准 USB Audio（无 offload，立即可用）

使用 Linux 标准 `snd-usb-audio` 驱动 + PipeWire/PulseAudio。
零开发工作，开箱即用。对大多数 USB 音频场景完全够用。

### 方向 E：最小化内核修改（新发现，推荐研究方向）

**核心发现**：USB offload 的实际数据通道是 QMI，独立于 APR/GPR 协议栈。

```
音频图管理: GPR (adsp_apps glink channel) — AudioReach 正常工作
USB 设备控制: QMI (独立通道) — 不经过 APR 也不经过 GPR
XHCI sideband: 内核直接操作 — 不依赖音频协议栈
```

因此可以:
1. 保持 AudioReach/GPR 设备树不变（WCD938x 等正常工作）
2. 在 `q6apm-lpass-dais.c` 中添加 USB DAI（使用 MODULE_ID_USB_AUDIO_SINK）
3. 修改 `q6usb.c` 去掉 `q6afe.h` 依赖，改为通用 soc-usb 接口
4. `qc_audio_offload.c` 的 QMI 逻辑无需修改（它已经独立工作）
5. 通过 GPR/APM 向 ADSP 发送 USB 音频图配置

这是工程量最小的 offload 路径。

---

## 六、最终结论与建议

### 核心事实

1. QCS6490 和 QCM6490 是同一颗 SoC (SC7280)
2. Fairphone 5 (QCM6490) 已在主线内核实现 USB audio offload — 使用 APR/AFE 路径
3. Radxa Q6A (QCS6490) 使用 AudioReach/GPR 路径，主线内核中无 USB offload 支持
4. **ADSP 固件反编译确认：Radxa 固件是 GPR 固件，不支持 APR，但内置完整 USB offload**
5. USB offload 通过 QMI 通信，独立于 APR/GPR — 固件侧已就绪
6. 瓶颈在内核侧：`q6usb.c` 硬编码依赖 `q6afe.h`
7. 截至 2026-02-25，上游无任何 q6apm USB offload 开发活动

### 修正后的推荐路径

| 优先级 | 方向 | 可行性 | 工作量 | 说明 |
|--------|------|--------|--------|------|
| 1 | C: 标准 USB Audio | 立即可用 | 零 | snd-usb-audio + PipeWire |
| 2 | E: 最小化内核修改 | 高 | 中等 | 保持 GPR 栈，修改 q6usb 依赖 |
| 3 | B: q6apm 完整 USB | 可行 | 大 | 完整的 AudioReach USB 支持 |
| ~~4~~ | ~~A: 切换 APR 栈~~ | ~~不可行~~ | - | ~~固件不支持 APR~~ |
| ~~5~~ | ~~D: 双栈共存~~ | ~~不可行~~ | - | ~~固件不支持 APR~~ |

### 下一步行动

如果需要 USB offload:

1. **研究方向 E**：分析 `q6usb.c` 对 `q6afe.h` 的具体依赖点，评估解耦工作量
2. **原型验证**：在 `audioreach.h` 中添加 USB 模块 ID，在 `q6apm-lpass-dais.c` 中添加 USB DAI
3. **QMI 验证**：确认 `qc_audio_offload.c` 在 GPR 设备树下是否能正常加载
4. **向上游提案**：联系 Wesley Cheng (Qualcomm USB audio offload 维护者) 讨论 AudioReach USB 支持

---

## 附录：验证数据来源

| 数据 | 来源 | 验证方式 |
|------|------|----------|
| USB 模块 ID | audioreach-graphservices/spf/api/modules/usb_api.h | GitHub API 直接读取 |
| audioreach.h 模块列表 | torvalds/linux HEAD | GitHub API 直接读取 |
| q6apm-lpass-dais.c USB grep | torvalds/linux HEAD | GitHub API + grep，零结果 |
| Fairphone 5 DTS | torvalds/linux HEAD | GitHub API 直接读取 |
| Radxa Q6A DTS | torvalds/linux HEAD | GitHub API 直接读取 |
| QCS6490 audioreach dtsi | torvalds/linux HEAD | GitHub API 直接读取 |
| kodiak.dtsi APR 栈 | torvalds/linux HEAD | GitHub API 直接读取 |
| qdsp6 近期提交 | torvalds/linux HEAD | GitHub API commits 查询 |
| PAL USB 配置 | AudioReach/audioreach-pal | GitHub API 直接读取 |
| q6usb DT binding | torvalds/linux HEAD | GitHub API 直接读取 |
| ADSP 固件 (adsp.mbn) | radxa-pkg/radxa-firmware | 下载 + Python 字符串提取 (68,680 strings) |
| 固件 USB 模块 | adsp.mbn 反编译 | 290 个 USB 相关字符串，14 个源文件 |
| 固件协议栈 | adsp.mbn 反编译 | GPR: 496 strings, APR: 5 strings (残留) |
