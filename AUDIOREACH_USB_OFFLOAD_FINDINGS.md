# AudioReach USB Offload 深度源码验证报告

## 研究日期
2025-02-24

## 研究范围
- AudioReach GitHub Organization 全部 17 个公开仓库
- Linux 主线内核 6.13-rc1 QDSP6 驱动
- AOSP hardware/qcom/audio-ar

---

## 一、核心发现：两层架构的断裂

AudioReach USB Audio 存在一个关键的架构断裂：

| 层级 | USB Audio 支持 | 状态 |
|------|---------------|------|
| 用户空间 (PAL/GSL/SPF) | MODULE_ID_USB_AUDIO_SINK/SOURCE, 完整 PAL 实现 | 有 |
| Linux 主线内核 (q6apm) | q6apm-lpass-dais.c 无 q6usb_ops | 无 |
| Linux 主线内核 (q6afe) | q6afe-dai.c 有完整 USB offload | 有，但 QCS6490 不用 |

结论：AudioReach 用户空间框架完整支持 USB Audio，但 Linux 主线内核的 q6apm 驱动没有接入 USB offload 路径。QCS6490 使用 q6apm 架构，因此 USB offload 在主线内核上不可用。

---

## 二、验证 1：Dynamic Resampler 只有 ARM32 预编译库

### 2.1 源码验证

audioreach/audioreach-graphservices 仓库中的 libdynamic_resampler：

    ar_util/spf_libs/
      libdynamic_resampler.a    (ARM32 ELF, 32-bit LSB relocatable)

通过 GitHub API 验证，该仓库中只有一个 .a 文件，且为 ARM32 架构。

### 2.2 影响分析

- QCS6490 (Radxa Q6A) 运行 AArch64 Linux
- libdynamic_resampler.a 是 ARM32 (armv7) 目标文件
- AArch64 工具链无法链接 ARM32 静态库
- 没有源码可供重新编译（闭源预编译）

### 2.3 结论

Dynamic Resampler 在 AArch64 平台上是死路。如果 SPF 图中需要动态重采样，必须寻找替代方案或请求 Qualcomm 提供 AArch64 版本。

---

## 三、验证 2：q6apm 架构中 USB Offload 路径缺失

### 3.1 Linux 主线内核中的两套 QDSP6 驱动

Linux 主线内核中存在两套并行的 Qualcomm 音频 DSP 驱动：

1. q6afe 系列 (sound/soc/qcom/qdsp6/q6afe*.c)
   - 传统 APR/AFE 接口
   - 支持 USB offload (q6afe-dai.c 中有 USB_RX/USB_TX DAI)
   - 适用于较老的 SoC 或 Android 下游内核

2. q6apm 系列 (sound/soc/qcom/qdsp6/q6apm*.c)
   - AudioReach/GPR 接口
   - q6apm-lpass-dais.c 定义 LPASS DAI
   - 无 USB offload DAI 定义
   - QCS6490 在主线内核中使用此架构

### 3.2 q6apm-lpass-dais.c 源码分析

q6apm-lpass-dais.c 中定义的 DAI 列表只有 LPASS 端口 DAI：
- WSA_CODEC_DMA_RX_0
- WSA_CODEC_DMA_TX_0
- RX_CODEC_DMA_RX_0
- TX_CODEC_DMA_TX_0
- VA_CODEC_DMA_TX_0
- 等等...

关键缺失：没有 USB_AUDIO_RX / USB_AUDIO_TX 类型的 DAI。

### 3.3 q6afe-dai.c 中的 USB 支持（对比）

q6afe-dai.c 中存在 USB_RX DAI 定义，包含：
- stream_name = "USB Playback"
- rates = SNDRV_PCM_RATE_8000_384000
- name = "USB_RX", id = USB_RX
- ops = q6afe_dai_ops

但 q6afe 和 q6apm 是互斥的两套驱动，QCS6490 在主线内核中走 q6apm 路径。

### 3.4 设备树验证

QCS6490 的设备树 (qcs6490-rb3gen2.dts) 中：
- 使用 "qcom,q6apm-dais" compatible
- 不使用 "qcom,q6afe-dais"
- 音频路由通过 LPASS CDC DMA 端口

### 3.5 结论

USB Offload 在 QCS6490 主线内核上不可用，因为：
1. q6apm 驱动没有 USB DAI
2. q6afe 驱动有 USB DAI 但 QCS6490 不使用 q6afe
3. 没有桥接层将 q6apm 连接到 USB offload

---

## 四、验证 3：AudioReach 用户空间的 USB 支持（完整但无内核对接）

### 4.1 PAL 层 USB 实现

audioreach-pal 仓库中存在完整的 USB 设备管理：

    session/src/USBDevice.cpp        - USB 设备枚举和配置
    session/inc/USBDevice.h          - USB 设备类定义
    device/src/USBAudio.cpp          - USB 音频设备实现

PAL 层可以：
- 枚举 USB 音频设备
- 解析 USB 描述符获取支持的格式
- 配置采样率、位深、通道数

### 4.2 SPF 模块

audioreach-spf 仓库中有 USB 模块定义：

    MODULE_ID_USB_AUDIO_SINK    (0x07001024)
    MODULE_ID_USB_AUDIO_SOURCE  (0x07001025)

这些模块在 DSP 固件中实现 USB 音频的数据搬运。

### 4.3 GSL 层

audioreach-graphservices 通过 GSL 将 PAL 的 USB 配置传递给 SPF 图。

### 4.4 断裂点

用户空间 (PAL -> GSL -> SPF) 的 USB 路径完整，但需要内核驱动提供：
1. USB 设备信息的传递通道（sideband/QMI）
2. ALSA PCM 到 DSP 图的连接
3. USB 控制器的 offload 配置

在 Android 下游内核中，这些由 vendor 驱动提供。在 Linux 主线内核中，q6apm 没有实现这些接口。

---

## 五、可行路径分析

### 5.1 路径 A：在 q6apm 中添加 USB DAI（工程量大）

需要：
- 在 q6apm-lpass-dais.c 中添加 USB_RX/USB_TX DAI
- 实现 q6apm 到 USB offload 的数据路径
- 实现 sideband 信息传递
- 需要深入理解 GPR 协议和 SPF 图配置

难度：高。需要内核开发经验和 Qualcomm DSP 协议知识。

### 5.2 路径 B：使用 q6afe 驱动（兼容性问题）

理论上可以尝试在 QCS6490 上使用 q6afe 驱动的 USB 部分，但：
- q6afe 和 q6apm 架构不同，混用可能导致冲突
- QCS6490 的 DSP 固件可能不支持 AFE 接口
- 设备树需要大幅修改

难度：高，且可能不可行。

### 5.3 路径 C：纯用户空间 USB Audio（绕过 offload）

不使用 DSP offload，直接在 CPU 上处理 USB 音频：
- 使用标准 ALSA USB audio 驱动 (snd-usb-audio)
- PulseAudio/PipeWire 在 CPU 上做混音和重采样
- 完全不涉及 AudioReach DSP 路径

优点：立即可用，无需内核修改
缺点：CPU 占用高，功耗大，延迟可能较高

### 5.4 路径 D：等待上游支持

Wesley Cheng (Qualcomm) 已经在主线内核中提交了 USB audio offload 的基础设施：
- sound/usb/qcom/ 目录下的 offload 支持
- 但目前只对接 q6afe，不对接 q6apm

可以关注上游开发进展，等待 q6apm USB offload 支持合入主线。

---

## 六、对之前文档的修正

### 6.1 需要删除或标记为不可用的内容

1. docs/02-usb-audio-offload.md - 描述的 USB offload 路径在 QCS6490 主线内核上不存在
2. docs/05-implementation-guide.md - 实现指南基于不存在的内核接口
3. topology/ 目录下的 USB 拓扑配置 - SPF 图配置正确但无法通过主线内核加载
4. scripts/ 目录下的测试脚本 - 测试的 offload 路径不存在

### 6.2 仍然有效的内容

1. docs/01-audioreach-architecture.md - 架构概述基本正确
2. docs/06-mfc-module.md - MFC 模块分析正确（但 dynamic_resampler 限制需标注）
3. docs/08-troubleshooting.md - 部分调试方法仍有参考价值

---

## 七、总结

### 核心事实

1. AudioReach 用户空间框架（PAL/GSL/SPF）完整支持 USB Audio offload
2. Linux 主线内核的 q6apm 驱动不支持 USB offload
3. Linux 主线内核的 q6afe 驱动支持 USB offload，但 QCS6490 不使用 q6afe
4. libdynamic_resampler.a 只有 ARM32 版本，AArch64 无法使用
5. 在 QCS6490 上实现 USB offload 需要显著的内核开发工作

### 建议

对于 Radxa Q6A (QCS6490) 上的 USB 音频需求：
- 短期：使用标准 snd-usb-audio + PipeWire（路径 C）
- 中期：关注上游 q6apm USB offload 开发进展（路径 D）
- 长期：如果有内核开发资源，可以尝试路径 A
