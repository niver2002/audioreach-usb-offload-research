# USB Audio Offload 拓扑配置说明

## 重要说明：USB Offload 的真实架构

**USB Audio Offload 不走传统的 AudioReach 拓扑数据路径。**

### 真实的数据流

USB Audio Offload 使用 **QMI + XHCI Sideband** 架构：

```
用户空间 (ALSA/PulseAudio)
    ↓
ASoC PCM 设备 (q6usb.c)
    ↓
QMI 消息 (qc_audio_offload.c)
    ↓
ADSP 固件 (闭源)
    ↓
XHCI Sideband API
    ↓
USB Transfer Ring (DMA)
    ↓
USB 音频设备
```

**关键点：**
- 音频数据通过 XHCI sideband 直接从 ADSP 到 USB 控制器
- 不经过传统的 AFE port 数据传输
- 不使用 AudioReach graph 的数据流路径
- ADSP 端的 USB 处理是闭源固件的一部分

### 拓扑配置的实际作用

在 USB offload 场景下，拓扑配置的作用非常有限：

1. **DAPM Routing（主要作用）**
   - 定义 ASoC machine driver 中的音频路由
   - 在 `q6usb.c` 和 `q6afe-dai.c` 中硬编码
   - 用于电源管理和设备枚举

2. **不涉及的部分**
   - 数据处理模块（resampler、gain、MFC 等）
   - 跨模块的数据连接
   - 采样率转换配置

### 源码中的真实 DAPM Routing

从上游内核源码提取的实际 DAPM 路由：

#### sound/soc/qcom/qdsp6/q6afe-dai.c
```c
static const struct snd_soc_dapm_route q6afe_dapm_routes[] = {
    {"USB Playback", NULL, "USB_RX"},
    {"USB_TX", NULL, "USB Capture"},
    // ... 其他路由
};
```

#### sound/soc/qcom/qdsp6/q6usb.c
```c
static const struct snd_soc_dapm_widget q6usb_dapm_widgets[] = {
    SND_SOC_DAPM_HP("USB_RX_BE", NULL),
    SND_SOC_DAPM_MIC("USB_TX_BE", NULL),
};

static const struct snd_soc_dapm_route q6usb_dapm_routes[] = {
    {"USB_RX_BE", NULL, "USB Playback"},
    {"USB Capture", NULL, "USB_TX_BE"},
};
```

### ASoC Machine Driver 配置

USB offload 的实际配置在 ASoC machine driver 中：

```c
// 示例：sound/soc/qcom/sm8250.c 或类似的 machine driver

static struct snd_soc_dai_link usb_offload_dai_link = {
    .name = "USB Offload",
    .stream_name = "USB Offload",
    .cpu_dai_name = "USB_RX",
    .platform_name = "q6usb",
    .codec_name = "snd-soc-dummy",
    .codec_dai_name = "snd-soc-dummy-dai",
    .no_pcm = 1,
    .dpcm_playback = 1,
    .dpcm_capture = 1,
};
```

## AudioReach 拓扑仓库

Qualcomm 的 AudioReach 拓扑配置位于：
- https://github.com/linux-audio/audioreach-topology (如果存在)
- 或 Qualcomm 专有的 audioreach-engine 仓库

**注意：** 这些拓扑主要用于：
- Codec DMA 路径（I2S、TDM 等）
- HDMI 音频
- 蓝牙音频
- 内部音频处理（回声消除、降噪等）

**不用于 USB offload 的数据路径。**

## 为什么之前的拓扑配置是错误的

之前的文档假设 USB offload 走 AFE 路径，并配置了完整的 AudioReach graph：
- WR_SHARED_MEM_EP → PCM_DECODER → RESAMPLER → GAIN → MFC → USB_RX

**这是错误的，因为：**
1. 上游内核已经移除了 AFE 方向的 USB offload 支持
2. USB offload 通过 QMI + sideband，不走 AFE 数据路径
3. Dynamic Resampler 固件只有 ARM32 预编译库，无法在 ARM64 上使用
4. 数据处理在 ADSP 闭源固件中完成，不通过 AudioReach graph

## 实际需要的配置

### 1. 内核配置
见 `/c/Users/Administrator/audioreach-usb-offload-research/kernel/config/usb_audio_offload.config`

关键模块：
- `CONFIG_SND_SOC_QDSP6_Q6USB=m` - Q6 USB ASoC component
- `CONFIG_SND_USB_AUDIO_QMI=m` - USB Audio QMI 服务
- `CONFIG_USB_XHCI_SIDEBAND=y` - XHCI sideband 支持
- `CONFIG_SND_SOC_USB=y` - SoC USB 框架

### 2. 设备树配置
见 `/c/Users/Administrator/audioreach-usb-offload-research/kernel/dts/qcs6490-radxa-q6a-usb-audio.dtsi`

关键节点：
- ADSP remoteproc（加载固件）
- q6usb 节点（在 ADSP 子节点下）
- USB XHCI 控制器（sideband 支持）
- IOMMU 配置（ADSP 访问 USB 内存）

### 3. 固件文件
```
/lib/firmware/qcom/qcs6490/
├── adsp.mbn              # ADSP 固件（包含 USB offload 支持）
└── (可能需要其他固件文件)
```

### 4. ASoC 配置
通过 ALSA UCM 或 PulseAudio 配置，见 `examples/` 目录。

## 调试和验证

### 检查驱动加载
```bash
# 检查内核模块
lsmod | grep q6usb
lsmod | grep qc_usb_audio_offload
lsmod | grep xhci_sideband

# 检查 auxiliary device
ls /sys/bus/auxiliary/devices/ | grep usb

# 检查 QMI 服务
ls /sys/kernel/debug/qmi/
```

### 检查 ASoC 设备
```bash
# 检查 ASoC card
cat /proc/asound/cards

# 检查 PCM 设备
cat /proc/asound/pcm

# 检查 DAPM 路由
cat /sys/kernel/debug/asoc/*/dapm/*
```

### 检查 USB 设备
```bash
# 检查 USB 音频设备
lsusb | grep -i audio

# 检查 USB 设备详情
cat /sys/kernel/debug/usb/devices
```

## 参考资料

### 上游内核源码
- `sound/soc/qcom/qdsp6/q6usb.c` - Q6 USB ASoC component
- `sound/soc/qcom/qdsp6/q6afe-dai.c` - AFE DAI driver
- `sound/usb/qcom/qc_audio_offload.c` - QMI + sideband 桥接
- `drivers/usb/host/xhci-sideband.c` - XHCI sideband API
- `include/linux/usb/xhci-sideband.h` - Sideband API 头文件

### 设备树绑定
- `Documentation/devicetree/bindings/sound/qcom,q6usb.yaml`
- `Documentation/devicetree/bindings/usb/qcom,dwc3.yaml`

### QMI 协议
- `include/linux/soc/qcom/qmi.h`
- `drivers/soc/qcom/qmi_helpers.c`

## 总结

**USB Audio Offload 的拓扑配置非常简单，因为：**
1. 数据路径通过 QMI + XHCI sideband，不走 AudioReach graph
2. DAPM routing 在驱动代码中硬编码
3. 数据处理在 ADSP 闭源固件中完成
4. 不需要复杂的 M4 拓扑文件

**实际需要的是：**
1. 正确的内核配置（启用 q6usb、QMI、sideband）
2. 正确的设备树配置（ADSP、USB、IOMMU）
3. 正确的固件文件（adsp.mbn）
4. 正确的 ASoC machine driver 配置

传统的 AudioReach 拓扑配置（M4 文件、XML、二进制拓扑）在 USB offload 场景下作用有限。
