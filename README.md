# AudioReach USB Audio Offload 深度研究

> 基于 Qualcomm QCS6490 (Radxa Q6A) 平台的 USB Audio Offload 技术研究
>
> ⚠️ **重写版** — 初版存在致命技术错误（AFE 路径假设 + resampler 固件限制），已基于上游源码逐行分析完全重写。详见 [issue #66](https://github.com/niver2002/audioreach-usb-offload-research/issues/66)。

## 项目简介

本仓库是一个公开的中文技术文档库，深入分析 **USB Audio Offload** 在 **Qualcomm QCS6490 (Radxa Q6A)** 平台上的真实实现架构。

所有文档基于以下上游源码逐行分析：

| 源码文件 | 路径 | 作用 |
|---------|------|------|
| `qc_audio_offload.c` | `sound/usb/qcom/` | QMI + XHCI sideband 桥接驱动 |
| `q6usb.c` | `sound/soc/qcom/qdsp6/` | ASoC USB component |
| `xhci-sideband.c` | `drivers/usb/host/` | XHCI sideband API |
| `q6afe-dai.c` | `sound/soc/qcom/qdsp6/` | AFE DAI 定义 |
| `q6afe.c` | `sound/soc/qcom/qdsp6/` | AFE 底层实现 |

## 研究进展（按日期）

- [DEEP_RESEARCH_2026-02-26.md](DEEP_RESEARCH_2026-02-26.md) - 2026-02-26 增量核验：相对 2026-02-25 无新的上游解锁点，`q6usb -> q6afe` 耦合仍在。
- [DEEP_RESEARCH_2026-02-25.md](DEEP_RESEARCH_2026-02-25.md) - 2026-02-25 深度验证 v2：固件反编译确认 GPR 固件内置 USB offload，瓶颈在内核桥接。
- [analysis/06-q6usb-decoupling-dependency-map.md](analysis/06-q6usb-decoupling-dependency-map.md) - 2026-02-26 新增：`q6usb` 解耦依赖图与最小改动切分。

## 核心发现

USB Audio Offload **不走**传统的 AFE 数据路径。真实架构：

```
USB 设备插入
    │
    ▼
qc_usb_audio_offload_probe()
    ├── xhci_sideband_register()        ← 注册 sideband
    └── snd_soc_usb_connect()           ← 通知 ASoC
    │
    ▼
ADSP 发送 QMI 请求 (UAUDIO_STREAM_REQ)
    │
    ▼
handle_uaudio_stream_req()
    ├── xhci_sideband_add_endpoint()
    ├── xhci_sideband_get_endpoint_buffer()   ← transfer ring
    ├── xhci_sideband_create_interrupter()
    ├── xhci_sideband_get_event_buffer()      ← event ring
    └── uaudio_iommu_map()                    ← IOVA 映射给 ADSP
    │
    ▼
ADSP 直接操作 XHCI transfer ring 进行 isochronous 传输
```

## 已知的关键限制

1. **AFE 路径被封** — 上游源码中 USB offload 不经过 AFE 数据通路
2. **Dynamic Resampler 不可用** — `libdynamic_resampler.a` 只有 ARM32 版本，无法在 AArch64 平台链接
3. **ADSP USB 模块闭源** — DSP 端处理逻辑为 Qualcomm 闭源固件
4. **XHCI sideband 硬件依赖** — 需要 XHCI 控制器支持 secondary interrupter

## 目录结构

```
audioreach-usb-offload-research/
├── docs/                              # 技术研究文档（8 篇）
│   ├── 01-audioreach-architecture.md      # AudioReach 架构与 USB offload 路径
│   ├── 02-usb-audio-offload.md            # USB Audio Offload 技术概述
│   ├── 03-qmi-handling.md                 # QMI 处理机制
│   ├── 04-sideband-interface.md           # Sideband 接口技术
│   ├── 05-implementation-guide.md         # 实现指南
│   ├── 06-mfc-module.md                   # DSP 模块与固件限制分析
│   ├── 07-radxa-q6a-implementation.md     # Radxa Q6A 平台实现与限制
│   └── 08-troubleshooting.md              # 故障排查指南
├── topology/                          # 拓扑说明（非 M4 配置）
│   ├── README.md                          # 为什么 USB offload 不需要拓扑
│   ├── usb-offload-dapm-routing.txt       # 真实 DAPM routing
│   └── audioreach/README.md               # AudioReach 在 offload 中的有限作用
├── kernel/                            # 内核配置
│   ├── config/usb_audio_offload.config    # 内核 CONFIG 选项
│   └── dts/qcs6490-radxa-q6a-usb-audio.dtsi  # 设备树
├── scripts/                           # 工具脚本
│   ├── test-usb-offload.sh               # 测试脚本
│   └── setup-environment.sh              # 环境搭建脚本
└── examples/                          # 配置示例
    ├── alsa-configs/usb-offload.conf      # ALSA UCM 配置
    └── pulseaudio-configs/usb-offload-sink.pa  # PulseAudio 配置
```

## 技术栈

| 组件 | 说明 |
|------|------|
| SoC | Qualcomm QCS6490 |
| 开发板 | Radxa Q6A |
| DSP | Hexagon ADSP |
| 内核 | Linux 6.8+ (mainline) |
| USB 控制器 | DWC3 + XHCI |
| Offload 通道 | XHCI Sideband + Secondary Interrupter |
| 控制协议 | QMI (UAUDIO_STREAM_SERVICE) |
| ASoC 组件 | q6usb (auxiliary device) |

## 阅读顺序

1. [AudioReach 架构](docs/01-audioreach-architecture.md) — 理解框架层次和 USB offload 的特殊性
2. [USB Audio Offload 技术概述](docs/02-usb-audio-offload.md) — 整体架构和工作流程
3. [QMI 处理机制](docs/03-qmi-handling.md) — AP 与 ADSP 之间的控制通信
4. [Sideband 接口](docs/04-sideband-interface.md) — XHCI sideband API 详解
5. [实现指南](docs/05-implementation-guide.md) — 内核配置、驱动加载、设备树
6. [DSP 模块与固件限制](docs/06-mfc-module.md) — MFC、Dynamic Resampler 和 ARM32 限制
7. [Radxa Q6A 实现](docs/07-radxa-q6a-implementation.md) — 平台特定的实现与限制
8. [故障排查](docs/08-troubleshooting.md) — 基于真实驱动日志的排查方法

## 相关上游项目

- [audioreach-engine](https://github.com/AudIoReach/audioreach-engine) — DSP 引擎和预编译库
- [audioreach-graphservices](https://github.com/AudIoReach/audioreach-graphservices) — Graph 服务和 ACDB
- [audioreach-topology](https://github.com/AudIoReach/audioreach-topology) — 拓扑定义
- [Linux 内核 USB offload 驱动](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/sound/usb/qcom) — 上游 qc_audio_offload
- [Linux 内核 QDSP6 驱动](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/sound/soc/qcom/qdsp6) — 上游 q6usb

## 免责声明

本项目为独立技术研究，基于公开的开源代码和文档。ADSP 端的 USB 音频处理模块为 Qualcomm 闭源固件，本文档仅描述其公开接口和可观测行为。

## 许可证

MIT License — 详见 [LICENSE](LICENSE)
