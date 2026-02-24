# 项目重写说明

## 重写原因

本项目初版（2026-02-24）在未深入分析上游源码的情况下仓促发布，导致文档存在两个致命技术错误：

1. **AFE 路径假设错误**：初版假设 USB Audio Offload 走传统的 AFE (Audio Front End) 数据路径。
   实际上，上游源码中 USB offload 走的是 **QMI + XHCI Sideband** 路径，
   由 `qc_audio_offload.c` 驱动实现，ADSP 通过 QMI 请求获取 XHCI transfer ring 地址后
   直接操作 USB 硬件，完全绕过 AFE 数据通路。

2. **Dynamic Resampler 固件限制**：`audioreach-engine` 仓库中的 `libdynamic_resampler.a`
   只有 ARM32 预编译版本，在 QCS6490 (AArch64) 平台上无法链接使用。
   初版文档完全忽略了这一限制。

这些问题由 GitHub issue #66 指出。

## 重写范围

本次重写基于以下上游源码的逐行分析：

| 源码文件 | 来源 | 作用 |
|---------|------|------|
| `qc_audio_offload.c` | Linux 内核 `sound/usb/` | QMI + XHCI sideband 桥接驱动 |
| `q6usb.c` | Linux 内核 `sound/soc/qcom/qdsp6/` | ASoC component，创建 auxiliary device |
| `xhci-sideband.c` | Linux 内核 `drivers/usb/host/` | XHCI sideband API (Intel 贡献) |
| `q6afe-dai.c` | Linux 内核 `sound/soc/qcom/qdsp6/` | AFE DAI 定义（含 USB_RX port） |
| `q6afe.c` | Linux 内核 `sound/soc/qcom/qdsp6/` | AFE 底层实现 |
| `snd_usb_audio.h` | Linux 内核 `sound/usb/` | snd_usb_platform_ops 接口 |
| `audioreach-engine/` | GitHub AudIoReach | DSP 固件和预编译库 |

## 真实架构总结

```
USB 设备插入
    │
    ▼
qc_usb_audio_offload_probe()
    │
    ├── xhci_sideband_register()     ← 注册 XHCI sideband
    ├── snd_soc_usb_connect()        ← 通知 ASoC 层
    │
    ▼
ADSP 发送 QMI 请求 (UAUDIO_STREAM_REQ)
    │
    ▼
handle_uaudio_stream_req()
    │
    ├── enable_audio_stream()
    │   ├── xhci_sideband_add_endpoint()
    │   ├── xhci_sideband_get_endpoint_buffer()  ← transfer ring
    │   ├── xhci_sideband_create_interrupter()
    │   ├── xhci_sideband_get_event_buffer()     ← event ring
    │   └── uaudio_iommu_map()                   ← IOVA 映射
    │
    ▼
prepare_qmi_response()
    │
    ├── xhci_mem_info.tr_data      ← transfer ring IOVA
    ├── xhci_mem_info.tr_sync      ← sync transfer ring IOVA
    ├── xhci_mem_info.evt_ring     ← event ring IOVA
    ├── xhci_mem_info.xfer_buff    ← transfer buffer IOVA
    ├── interrupter_num            ← secondary interrupter 编号
    └── speed_info, slot_id        ← USB 设备信息
    │
    ▼
ADSP 直接操作 XHCI transfer ring 进行 isochronous 传输
```

## 已知限制

1. AFE 方向的 USB offload 在上游内核中不可用
2. `libdynamic_resampler.a` 无 AArch64 版本
3. ADSP 端 USB 处理模块为闭源固件
4. XHCI sideband 需要 XHCI 控制器硬件支持

## 文件清单

| 文件 | 说明 |
|------|------|
| `docs/01-audioreach-architecture.md` | AudioReach 架构与 USB offload 路径分析 |
| `docs/02-usb-audio-offload.md` | USB Audio Offload 技术概述 |
| `docs/03-qmi-handling.md` | QMI 处理机制 |
| `docs/04-sideband-interface.md` | Sideband 接口技术 |
| `docs/05-implementation-guide.md` | 基于真实驱动的实现指南 |
| `docs/06-mfc-module.md` | DSP 模块与固件限制分析 |
| `docs/07-radxa-q6a-implementation.md` | Radxa Q6A 平台实现与限制 |
| `docs/08-troubleshooting.md` | 基于真实驱动日志的故障排查 |
| `topology/` | DAPM routing 和拓扑说明 |
| `kernel/` | 内核配置和设备树 |
| `scripts/` | 测试和环境搭建脚本 |
| `examples/` | ALSA/PulseAudio 配置示例 |

## 版本

- 初版：2026-02-24（已废弃，存在致命技术错误）
- 重写版：2026-02-24（基于上游源码逐行分析）
