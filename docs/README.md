# AudioReach USB Offload 研究文档

> ⚠️ 本目录文档已于 2026-02-24 基于上游源码逐行分析完全重写。
> 初版文档存在 AFE 路径假设错误和 resampler 固件限制遗漏，详见 GitHub issue #66。

## 文档列表

### 01-audioreach-architecture.md - AudioReach 架构与 USB Offload 路径
- AudioReach Graph → Subgraph → Container → Module 层次结构
- 传统 AFE 数据路径 vs USB offload QMI+Sideband 路径的本质区别
- 上游源码中 USB offload 的真实模块关系
- 已知的架构限制

### 02-usb-audio-offload.md - USB Audio Offload 技术概述
- USB Audio Offload 架构组件和工作流程
- 关键数据结构和初始化流程
- 音频流启动/停止的完整流程
- 性能优化和错误处理

### 03-qmi-handling.md - QMI 处理机制
- QMI 架构和服务初始化
- Stream Request、Stream Indication、Memory Map Request 消息类型
- 错误处理、超时重试机制、同步机制
- 调试支持和最佳实践

### 04-sideband-interface.md - Sideband 接口技术
- 完整的 Sideband API 参考（注册、端点管理、传输环、中断、门铃）
- 详细的工作流程（初始化、启动、停止、清理）
- 数据结构、内存管理、同步机制
- 性能优化、调试支持、安全考虑

### 05-implementation-guide.md - 实现指南
- 真实的内核 CONFIG 选项和依赖关系
- 驱动加载顺序：xhci-sideband → snd-usb-audio → q6usb → qc-usb-audio-offload
- 设备树配置（基于真实 compatible strings）
- 上游限制与变通方案

### 06-mfc-module.md - DSP 模块与固件限制分析
- AudioReach USB 相关 DSP 模块
- MFC (Media Format Converter) 的真实作用
- `libdynamic_resampler.a` ARM32 限制问题深度分析
- `audioreach-engine` 仓库固件文件结构
- 对 QCS6490 (AArch64) 平台的影响
- 可能的替代方案探讨

### 07-radxa-q6a-implementation.md - Radxa Q6A 平台实现与限制
- QCS6490 真实硬件架构（DWC3 + XHCI）
- ADSP 固件实际状态和限制
- 真实可行的验证步骤
- 当前不可行的方案明确列表

### 08-troubleshooting.md - 故障排查指南
- 基于源码中 `dev_err`/`dev_dbg` 提取的真实日志关键字
- XHCI sideband 调试方法
- QMI 服务连接调试
- IOMMU 映射失败排查
- USB 设备枚举和 offload probe 排查

## 核心技术要点

本项目研究的 USB Audio Offload 真实数据路径：

```
q6usb.c (ASoC component)
    │
    ├── 创建 auxiliary device "q6usb.qc-usb-audio-offload"
    │
    ▼
qc_audio_offload.c (auxiliary driver)
    │
    ├── QMI: UAUDIO_STREAM_SERVICE
    ├── XHCI: xhci_sideband API
    └── IOMMU: uaudio_iommu_map()
    │
    ▼
ADSP 直接操作 XHCI transfer ring
```

关键发现：USB offload **不走** 传统 AFE 数据路径。

## 上游源码参考

- `sound/usb/qcom/qc_audio_offload.c` - QMI + sideband 桥接
- `sound/soc/qcom/qdsp6/q6usb.c` - ASoC USB component
- `drivers/usb/host/xhci-sideband.c` - XHCI sideband API
- `sound/soc/qcom/qdsp6/q6afe-dai.c` - AFE DAI（含 USB_RX port 定义）
- `sound/soc/qcom/qdsp6/q6afe.c` - AFE 底层实现

## 文档版本

- 重写日期：2026-02-24
- 基于内核版本：Linux 6.8+（上游 mainline）
- 重写原因：GitHub issue #66（AFE 路径被封 + resampler 固件限制）
