# AudioReach 拓扑在 USB Offload 中的作用

## 重要说明

**AudioReach graph 在 USB Audio Offload 场景下的作用非常有限。**

## AudioReach 架构概述

AudioReach 是 Qualcomm 的下一代音频架构，用于替代传统的 QDSP6 ADM/ASM 架构。

### 主要组件

1. **APM (Audio Processing Manager)**
   - 管理音频图 (graph) 的生命周期
   - 负责模块的加载、配置和连接

2. **PRM (Proxy Resource Manager)**
   - 管理硬件资源（时钟、电源、带宽）
   - 协调多个音频流的资源分配

3. **AFE (Audio Front End)**
   - 硬件接口抽象层
   - 支持 I2S、TDM、PCM、HDMI、USB 等接口

4. **Graph Modules**
   - 音频处理模块（编解码器、重采样器、增益、混音器等）
   - 通过 graph 连接形成数据流

## AudioReach 的典型应用场景

AudioReach graph 主要用于以下场景：

### 1. Codec DMA 路径
```
APPS → WR_SHARED_MEM → PCM_DEC → RESAMPLER → GAIN → I2S_TX → Codec
```
用于：
- 板载音频 codec（WCD9380、WCD9385 等）
- I2S/TDM 音频输出
- 需要 DSP 处理的音频流

### 2. HDMI 音频
```
APPS → WR_SHARED_MEM → PCM_DEC → HDMI_TX → HDMI 设备
```
用于：
- HDMI/DisplayPort 音频输出
- 多声道音频（5.1、7.1）

### 3. 蓝牙音频
```
APPS → WR_SHARED_MEM → ENCODER → BT_TX → 蓝牙芯片
```
用于：
- A2DP 音频输出
- SCO/HFP 语音通话

### 4. 音频处理
```
MIC → RD_SHARED_MEM → AEC → NS → AGC → WR_SHARED_MEM → APPS
```
用于：
- 回声消除 (AEC)
- 降噪 (NS)
- 自动增益控制 (AGC)
- 语音识别预处理

## USB Offload 为什么不使用 AudioReach Graph

### 1. 数据路径不同

**传统 AudioReach 路径：**
```
APPS → GLINK → ADSP → AudioReach Graph → AFE → 硬件
```

**USB Offload 路径：**
```
APPS → QMI 控制消息 → ADSP 固件 → XHCI Sideband → USB DMA
```

关键区别：
- USB offload 的数据不经过 AudioReach graph
- 数据通过 XHCI sideband 直接 DMA 到 USB 控制器
- ADSP 固件直接操作 USB transfer ring

### 2. 固件实现

USB offload 的处理逻辑在 ADSP 闭源固件中：
- USB 端点管理
- 采样率转换（如果需要）
- 格式转换
- 缓冲区管理

这些功能不通过 AudioReach 模块实现。

### 3. 控制接口

**AudioReach 控制：**
- 通过 GPR (Generic Packet Router) 协议
- 发送 graph open/close/start/stop 命令
- 配置模块参数

**USB Offload 控制：**
- 通过 QMI (Qualcomm MSM Interface) 协议
- 发送 USB 设备信息、端点配置
- 不涉及 AudioReach graph 命令

## USB Offload 中 AudioReach 的有限作用

虽然 USB offload 不使用 AudioReach graph 的数据路径，但仍然依赖部分 AudioReach 基础设施：

### 1. APM 框架
- 用于设备枚举和管理
- 提供统一的 ASoC 接口

### 2. AFE 抽象
- USB 端口定义（Port 136/137）
- 电源管理和时钟控制

### 3. DAPM 路由
- 在 `q6afe-dai.c` 和 `q6usb.c` 中定义
- 用于 ASoC 设备树构建

## 拓扑配置的实际需求

### 对于 USB Offload

**不需要：**
- 复杂的 M4 拓扑文件
- AudioReach graph 定义
- 模块间连接配置
- 采样率转换配置

**需要：**
- 正确的内核驱动配置
- 正确的设备树配置
- ADSP 固件支持 USB offload
- QMI 服务正常运行

### 对于其他音频路径

如果需要同时支持其他音频路径（codec、HDMI 等），则需要：
- 完整的 AudioReach 拓扑配置
- 定义相应的 graph 和模块
- 配置模块参数和连接

## audioreach-topology 仓库

Qualcomm 的 AudioReach 拓扑配置可能位于：
- https://github.com/linux-audio/audioreach-topology (社区版本)
- Qualcomm 专有的 audioreach-engine 仓库

这些拓扑文件用于：
- 板载 codec 配置
- HDMI 音频配置
- 蓝牙音频配置
- 音频效果处理

**不包含 USB offload 的拓扑配置**，因为 USB offload 不需要。

## 示例：对比不同路径

### Codec 播放（需要 AudioReach Graph）
```c
// 需要拓扑文件定义 graph
Graph: CODEC_PLAYBACK
  Subgraph: STREAM_PROCESSING
    WR_SHARED_MEM_EP (0x0001)
      ↓
    PCM_DECODER (0x0002)
      ↓
    RESAMPLER (0x0003)
      ↓
    GAIN (0x0004)

  Subgraph: DEVICE_OUTPUT
    I2S_TX (0x0100)
      ↓
    Codec 硬件
```

### USB Offload（不需要 AudioReach Graph）
```c
// 不需要拓扑文件，路径在固件中
用户空间
  ↓ (ioctl)
q6usb.c
  ↓ (QMI 消息)
ADSP 固件
  ↓ (sideband API)
XHCI 控制器
  ↓ (DMA)
USB 设备
```

## 调试和验证

### 检查 AudioReach 服务
```bash
# 检查 APM 服务
cat /sys/kernel/debug/gpr/services

# 检查 graph 状态（如果有其他音频路径）
cat /sys/kernel/debug/asoc/*/graphs
```

### 检查 USB Offload（不涉及 graph）
```bash
# 检查 QMI 服务
ls /sys/kernel/debug/qmi/

# 检查 auxiliary device
ls /sys/bus/auxiliary/devices/ | grep usb

# 检查 sideband 状态
cat /sys/kernel/debug/usb/xhci/*/sideband
```

## 总结

1. **AudioReach graph 不用于 USB offload 的数据传输**
2. **USB offload 通过 QMI + XHCI sideband 实现**
3. **不需要编写 M4 拓扑文件用于 USB offload**
4. **AudioReach 拓扑仅用于其他音频路径（codec、HDMI 等）**
5. **USB offload 的配置主要在内核驱动和设备树中**

## 参考资料

- AudioReach 架构: `Documentation/sound/soc/qcom/audioreach.rst`
- GPR 协议: `include/linux/soc/qcom/gpr.h`
- QMI 协议: `include/linux/soc/qcom/qmi.h`
- USB Offload: `sound/usb/qcom/qc_audio_offload.c`
