# QCS6490 AFE 路径状态：是否真的"被封"？

> 基于上游内核源码的逐行分析，区分事实与推测

## 1. 核心问题

用户提出："QCS6490 Linux 上游的 AFE 方向被封，USB offload 没有可用的实现路径。"

本文档逐一验证这个断言。

## 2. 事实清单

### 事实 1：AFE 代码在上游内核中完整存在

```
sound/soc/qcom/qdsp6/q6afe.c          — AFE 核心，APR 协议
sound/soc/qcom/qdsp6/q6afe-dai.c      — AFE DAI 驱动
sound/soc/qcom/qdsp6/q6afe-clocks.c   — AFE 时钟管理
sound/soc/qcom/qdsp6/q6usb.c          — USB offload ASoC 组件
```

这些文件**没有被删除、没有被标记 deprecated、没有被 #ifdef 排除**。
它们是可编译、可加载的内核模块。

**结论：AFE 代码没有被"封"。**

### 事实 2：USB offload 驱动也在上游

```
sound/usb/qcom/qc_audio_offload.c     — USB 侧 class driver
sound/usb/qcom/usb_audio_qmi_v01.c    — QMI 协议定义
sound/usb/qcom/mixer_usb_offload.c    — mixer 控制
include/sound/q6usboffload.h          — 共享头文件
include/sound/soc-usb.h               — SoC-USB 框架
```

**结论：USB offload 内核基础设施完整。**

### 事实 3：AudioReach 不包含 USB 支持

```bash
# 在以下文件中搜索 "usb" (不区分大小写)：
q6apm.c:       0 matches
q6apm-dai.c:   0 matches
audioreach.c:  0 matches
topology.c:    0 matches
```

**结论：AudioReach 路径确实没有 USB offload 实现。**

### 事实 4：q6usb.c 只依赖 AFE

```c
// q6usb.c 的 #include
#include "q6afe.h"     // 唯一的 QDSP6 依赖

// q6usb.c 的核心调用
q6afe_port_set_usb_cfg()
q6afe_port_start()
q6afe_port_stop()
```

**结论：USB offload 的 ASoC 层绑定在 AFE 上，没有 AudioReach 替代实现。**

### 事实 5：QCS6490 设备树**显式删除了 APR 节点**

这是最关键的发现。在 `qcs6490-audioreach.dtsi` 中：

```dts
/delete-node/ apr;
```

**设备树显式删除了 APR (Asynchronous Packet Router) 节点。**

这意味着：
- APR 协议栈在 QCS6490 上**不会被初始化**
- `q6afe.ko` 即使编译了也**无法注册**，因为没有 APR bus 上的父设备
- AFE service 在内核侧**完全不可达**

同时，设备树只注册了：
- `qcom,q6apm` — AudioReach Audio Process Manager
- `qcom,q6prm` — Proxy Resource Manager
- 使用 GPR (Generic Packet Router) 协议

### 事实 6：q6apm-lpass-dais.c 有 USB 端口定义但无 ops 实现

```c
// q6dsp-lpass-ports.c 中定义了 USB_RX 端口
{
    .id = USB_RX,
    .name = "USB_RX",
    .stream_name = "USB Playback",
    // ...
}
```

端口定义存在，但需要 `cfg->q6usb_ops` 才能工作。而 `q6apm-lpass-dais.c` 中：

```bash
$ grep -n "q6usb_ops" q6apm-lpass-dais.c
# 零结果
```

**端口定义是空壳，没有实际的 USB offload 操作函数。**

## 3. 结论：不再是"未知"

之前的分析将 ADSP 固件是否包含 AFE service 列为"关键未知项"。
但设备树的 `/delete-node/ apr;` 已经回答了这个问题：

**即使 ADSP 固件包含 AFE service，内核侧也无法与之通信，因为 APR 协议栈被设备树删除了。**

这不是固件问题，是**设备树层面的架构决策**。

### 理论上的绕过方式

1. **修改设备树，恢复 APR 节点** — 但这需要同时确认 ADSP 固件确实有 AFE service
2. **在 q6apm 路径中实现 USB offload** — 需要大量内核开发工作
3. **使用 vendor 内核** — 可能有不同的设备树配置

## 4. 实机验证仍有价值

虽然设备树层面已经明确删除了 APR，但以下验证在实机上仍有意义：

### 4.1 确认 APR bus 确实不存在

```bash
# 如果 APR bus 不存在，这个目录应该为空或不存在
ls -la /sys/bus/apr/devices/ 2>/dev/null
# 预期：目录不存在或为空

# GPR 设备应该存在
ls -la /sys/bus/gpr/devices/
# 预期：有 gpr 设备
```

### 4.2 检查 ADSP 固件中是否有 AFE service

```bash
# 即使内核侧不用，固件中可能仍包含 AFE
strings /lib/firmware/qcom/qcs6490/adsp*.mbn 2>/dev/null | grep -i "afe" | head -10
# 如果有结果，说明固件有 AFE service，只是内核侧没有对接
# 这为"恢复 APR 节点"方案提供了可行性依据
```

### 4.3 尝试恢复 APR 节点（高级实验）

```bash
# 修改设备树，移除 /delete-node/ apr; 并添加 APR 节点
# 重新编译 DTB，重启
# 检查 APR bus 是否出现，AFE 是否能注册
# 这是验证"双栈共存"可行性的唯一方法
```

## 5. 对"AFE 被封"说法的最终评估

| 断言 | 评估 | 依据 |
|------|------|------|
| AFE 代码被从上游删除 | **错误** | 代码完整存在于 mainline |
| AFE 在 QCS6490 上被禁用 | **正确** | 设备树 `/delete-node/ apr;` |
| USB offload 在当前配置下不可用 | **正确** | APR 被删 + q6apm 无 USB ops |
| AudioReach 不支持 USB offload | **正确** | q6apm 零 USB 引用 |
| 完全没有可能性 | **不确定** | 取决于固件是否保留 AFE service |

## 6. 实际情况

### 6.1 Wesley Cheng 的 USB offload 上游工作

Wesley Cheng (Qualcomm) 在 2023-2024 年持续提交 USB offload 补丁到上游，包括 `q6usb.c`、`qc_audio_offload.c`、`xhci-sideband.c`。

关键问题：这些补丁针对哪些 SoC？

- `q6usb.c` 依赖 `q6afe.h` — 只能在 AFE/APR 路径上工作
- 这意味着 USB offload 上游化的目标可能是**仍使用 APR 的旧 SoC**（如 SM8250/SM8350）
- 或者 Qualcomm 计划未来在 q6apm 中也添加 USB 支持，但**目前还没有**

### 6.2 三条可能的前进路径

**路径 A：恢复 APR + AFE（实验性）**
- 修改设备树，恢复 APR 节点
- 如果 ADSP 固件包含 AFE service，可能可以让 q6afe + q6usb 工作
- 风险：可能与 q6apm 冲突，固件可能不支持
- 难度：中等，需要设备树和内核配置经验

**路径 B：为 q6apm 实现 USB offload（大工程）**
- 在 `q6apm-lpass-dais.c` 中实现 `q6usb_ops`
- 重写 `q6usb.c` 以使用 GPR/APM 协议而非 APR/AFE
- 需要理解 AudioReach 图拓扑如何路由到 USB
- 难度：高，需要深入的 AudioReach 和内核音频知识

**路径 C：标准 USB Audio（立即可用）**
- 使用 `snd-usb-audio` + PipeWire/PulseAudio
- 不经过 DSP，CPU 处理所有音频
- 功耗较高，但功能完整
- 难度：零

## 7. 修正后的结论

**"AFE 被封"基本正确，但需要精确表述：**

> QCS6490 上游设备树通过 `/delete-node/ apr;` 显式禁用了 APR 协议栈。
> 这导致 AFE service 在内核侧不可达，进而导致依赖 AFE 的 USB offload 路径断开。
> 同时，AudioReach (q6apm) 路径没有 USB offload 实现。
>
> USB offload 在 QCS6490 主线内核的当前配置下**确实不可用**。
>
> 但这不是代码被删除，而是**配置层面的禁用**。
> 如果 ADSP 固件保留了 AFE service，通过修改设备树恢复 APR 节点，
> 理论上可以重新启用 AFE 路径。这需要实机验证。

**短期建议：使用标准 snd-usb-audio + PipeWire，不走 DSP offload。**
