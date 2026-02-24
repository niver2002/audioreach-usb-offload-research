# AudioReach USB Offload Topology Files

本目录包含 QCS6490 Radxa Q6A 平台的 AudioReach USB Audio Offload 拓扑配置文件。

## 文件结构

```
topology/
├── audioreach/
│   └── module_usb.m4          # USB 模块 M4 宏定义
├── examples/
│   ├── usb-playback-simple.m4      # 简单 USB 播放示例
│   └── usb-playback-resampler.m4   # 带重采样器的 USB 播放示例
├── QCS6490-Radxa-Q6A-USB.m4   # 完整的 USB offload 拓扑
└── README.md                   # 本文件
```

## 文件说明

### 1. audioreach/module_usb.m4

USB 模块的 M4 宏定义库，包含以下宏：

- `AR_MODULE_USB_RX` - USB 播放硬件端点（Port 136）
- `AR_MODULE_USB_TX` - USB 录制硬件端点（Port 137）
- `AR_MODULE_WR_SHARED_MEM_EP` - APPS 写入共享内存端点
- `AR_MODULE_RD_SHARED_MEM_EP` - APPS 读取共享内存端点
- `AR_MODULE_PCM_DECODER` - PCM 解码器
- `AR_MODULE_PCM_ENCODER` - PCM 编码器
- `AR_MODULE_DYNAMIC_RESAMPLER` - 动态重采样器
- `AR_MODULE_GAIN` - 增益控制
- `AR_MODULE_MFC` - 多格式转换器
- `AR_USB_CONNECTION` - 模块间连接

### 2. QCS6490-Radxa-Q6A-USB.m4

完整的 USB Audio Offload 拓扑定义，包含：

#### Graph 1: USB_PLAYBACK_GRAPH (播放图)
- **Subgraph 1.1: STREAM_USB_PB** (流处理子图)
  - WR_SHARED_MEM_EP → PCM_DECODER → DYNAMIC_RESAMPLER → GAIN
  - 优先级: Normal (0)
  
- **Subgraph 1.2: DEVICE_USB_PB** (设备端点子图)
  - MFC → USB_RX_EP (Port 136)
  - 优先级: High (2)

#### Graph 2: USB_CAPTURE_GRAPH (录制图)
- **Subgraph 2.1: DEVICE_USB_CAP** (设备端点子图)
  - USB_TX_EP (Port 137) → MFC
  - 优先级: High (2)
  
- **Subgraph 2.2: STREAM_USB_CAP** (流处理子图)
  - GAIN → DYNAMIC_RESAMPLER → PCM_ENCODER → RD_SHARED_MEM_EP
  - 优先级: Normal (0)

### 3. examples/usb-playback-simple.m4

最简单的 USB 播放拓扑，适用于：
- USB 设备支持固定采样率（48kHz）
- 不需要动态采样率转换
- 最低延迟要求

数据流：`APPS → WR_SHARED_MEM → PCM_DECODER → USB_RX`

### 4. examples/usb-playback-resampler.m4

带动态重采样器的 USB 播放拓扑，适用于：
- USB 设备支持多种采样率
- 需要运行时动态切换采样率
- 需要音量控制和格式转换

数据流：`APPS → WR_SHARED_MEM → PCM_DEC → RESAMPLER → GAIN → MFC → USB_RX`

支持的采样率：8000, 16000, 32000, 44100, 48000, 96000, 192000 Hz

## 使用方法

### 1. 编译拓扑文件

使用 M4 宏处理器编译拓扑文件：

```bash
# 编译完整拓扑
m4 QCS6490-Radxa-Q6A-USB.m4 > QCS6490-Radxa-Q6A-USB.xml

# 编译简单示例
m4 examples/usb-playback-simple.m4 > usb-playback-simple.xml

# 编译重采样器示例
m4 examples/usb-playback-resampler.m4 > usb-playback-resampler.xml
```

### 2. 转换为二进制格式

使用 AudioReach 工具链将 XML 转换为二进制拓扑文件：

```bash
# 假设使用 audioreach-topology-compiler
audioreach-topology-compiler -i QCS6490-Radxa-Q6A-USB.xml -o usb-offload.bin
```

### 3. 部署到设备

将生成的二进制文件部署到设备：

```bash
adb push usb-offload.bin /vendor/etc/audioreach/
adb reboot
```

## 关键概念

### Module IDs

- `0x07001000` - WR_SHARED_MEM_EP (APPS 写入端点)
- `0x07001001` - RD_SHARED_MEM_EP (APPS 读取端点)
- `0x07001005` - PCM_DECODER
- `0x07001006` - PCM_ENCODER
- `0x07001015` - CODEC_DMA/通用硬件端点
- `0x07001016` - DYNAMIC_RESAMPLER
- `0x07001026` - MODULE_GAIN
- `0x0700105A` - HW_EP_POWER_MODE

### Port IDs

- `136` - USB_RX (USB Audio Playback)
- `137` - USB_TX (USB Audio Capture)

### Instance ID 分配

- `0x0001-0x00FF` - 流处理模块
- `0x0100-0x01FF` - USB 播放硬件端点
- `0x0200-0x02FF` - USB 录制硬件端点

### Container Priority

- `0` - Normal (流处理)
- `1` - Medium
- `2` - High (硬件端点)

## 参考资料

- Linux 内核: `include/dt-bindings/sound/qcom,q6dsp-lpass-ports.h`
- AudioReach 文档: Qualcomm AudioReach Architecture Guide
- audioreach-topology 项目: https://github.com/linux-audio/audioreach-topology

## 注意事项

1. **Instance ID 唯一性**: 每个模块的 instance_id 必须在整个拓扑中唯一
2. **端口连接**: 确保源模块的输出端口连接到目标模块的输入端口
3. **采样率匹配**: 如果不使用 resampler，确保所有模块的采样率一致
4. **优先级设置**: 硬件端点容器应使用高优先级（2）以避免音频断续
5. **跨子图连接**: 流处理子图和设备端点子图之间需要显式连接

## 许可证

本文件基于 AudioReach 开源项目，遵循相应的开源许可证。
