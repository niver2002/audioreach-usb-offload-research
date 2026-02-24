# AudioReach USB Audio Offload 深度研究

> 基于 Qualcomm QCS6490 (Radxa Q6A) 平台的 USB Audio Offload 技术研究与实现指南

## 项目简介

本仓库是一个公开的中文技术文档库，详细阐述 **AudioReach 框架**如何在 **Radxa Q6A**（搭载 QCS6490 芯片）上实现 **USB 音频 Offload** 功能。

USB Audio Offload 允许音频数据直接由 ADSP (Audio DSP) 处理并通过 XHCI Sideband 接口传输到 USB 音频设备，绕过 CPU，从而实现：
- 显著降低 CPU 负载
- 降低系统功耗
- 减少音频延迟

## 目录结构

```
audioreach-usb-offload-research/
├── docs/                           # 技术研究文档
│   ├── 01-audioreach-architecture.md   # AudioReach 架构详解
│   ├── 02-usb-audio-offload.md           # USB Audio Offload 深度分析
│   ├── 03-implementation-guide.md        # 实现指南
│   ├── 04-mfc-module.md                # MFC 模块详解
│   ├── 05-radxa-q6a-implementation.md  # Radxa Q6A 实现方案
│   └── 06-troubleshooting.md           # 故障排查指南
├── topology/                       # AudioReach 拓扑配置
│   ├── audioreach/                     # M4 宏定义
│   │   └── module_usb.m4              # USB 模块宏
│   ├── QCS6490-Radxa-Q6A-USB.m4       # 完整 USB 拓扑
│   └── examples/                       # 拓扑示例
│       ├── usb-playback-simple.m4      # 简单播放拓扑
│       └── usb-playback-resampler.m4   # 带重采样器的播放拓扑
├── kernel/                         # 内核配置
│   ├── dts/                            # 设备树配置
│   │   └── qcs6490-radxa-q6a-usb-audio.dtsi
│   └── config/                         # 内核配置片段
│       └── usb_audio_offload.config
├── scripts/                        # 工具脚本
│   ├── test-usb-offload.sh            # 测试脚本
│   └── setup-environment.sh           # 环境搭建脚本
└── examples/                       # 配置示例
    ├── alsa-configs/                   # ALSA UCM 配置
    │   └── usb-offload.conf
    └── pulseaudio-configs/             # PulseAudio 配置
        └── usb-offload-sink.pa
```

## 技术栈

| 组件 | 说明 |
|------|------|
| SoC | Qualcomm QCS6490 |
| 开发板 | Radxa Q6A |
| DSP | Hexagon ADSP |
| 框架 | AudioReach (开源) |
| 内核 | Linux 6.8+ |
| USB | XHCI Sideband + Secondary Interrupter |
| 通信 | GPR (Generic Packet Router) over GLINK |

## 关键数据流

```
┌─────────────┐    ┌──────────┐    ┌──────────┐    ┌──────────────┐
│  用户空间    │    │  ASoC    │    │  ADSP    │    │  USB 设备    │
│  ALSA/Pulse │───→│ q6apm-dai│───→│ AudioReach│───→│  (DAC/耳机)  │
│             │    │ q6usb    │    │ Graph    │    │              │
└─────────────┘    └──────────┘    └──────────┘    └──────────────┘
                        │               │
                   GPR over GLINK   XHCI Sideband
                   (控制路径)       (数据路径, 零拷贝)
```

## 快速开始

1. 阅读 [AudioReach 架构详解](docs/01-audioreach-architecture.md) 了解框架基础
2. 阅读 [USB Audio Offload 深度分析](docs/02-usb-audio-offload.md) 了解 offload 原理
3. 阅读 [实现指南](docs/03-implementation-guide.md) 了解具体实现步骤
3. 参考 [Radxa Q6A 实现方案](docs/05-radxa-q6a-implementation.md) 进行实际部署
4. 遇到问题查看 [故障排查指南](docs/06-troubleshooting.md)

## 环境搭建

```bash
# 1. 安装依赖
cd scripts && sudo ./setup-environment.sh

# 2. 配置内核
cd <kernel-source>
./scripts/kconfig/merge_config.sh \
    arch/arm64/configs/qcs6490_defconfig \
    path/to/usb_audio_offload.config
make -j$(nproc) && make modules_install && make install

# 3. 更新设备树
# 将 kernel/dts/qcs6490-radxa-q6a-usb-audio.dtsi 包含到主设备树

# 4. 运行测试
cd scripts && sudo ./test-usb-offload.sh --all
```

## 相关上游项目

- [audioreach-engine](https://github.com/AudIoReach/audioreach-engine) - AudioReach DSP 引擎
- [audioreach-graphservices](https://github.com/AudIoReach/audioreach-graphservices) - Graph 服务和 ACDB
- [audioreach-topology](https://github.com/AudIoReach/audioreach-topology) - 拓扑定义
- [Linux 内核 AudioReach 驱动](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/sound/soc/qcom/qdsp6) - 上游内核驱动

## 免责声明

本项目为独立技术研究，基于公开的开源代码和文档。AudioReach 中的部分 DSP 模块（如 USB AFE）为 Qualcomm 闭源固件，本文档仅描述其公开接口和行为。

## 许可证

MIT License - 详见 [LICENSE](LICENSE)
