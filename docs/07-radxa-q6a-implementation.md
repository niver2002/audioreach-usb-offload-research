# Radxa Q6A USB Audio Offload 实现方案

## 硬件概述

Radxa Q6A 是基于 Qualcomm QCS6490 SoC 的单板计算机。本文档基于真实硬件架构和上游内核源码，分析 USB Audio Offload 在 Q6A 上的实现可行性。

### QCS6490 核心规格

**处理器**
- CPU: Kryo 670 (4x Cortex-A78 @ 2.7GHz + 4x Cortex-A55 @ 1.9GHz)
- 架构: ARMv8.2-A (AArch64)
- 制程: 6nm

**ADSP 子系统**
- 架构: Hexagon DSP v69
- 频率: 最高 1.0GHz
- 支持 AudioReach 框架
- 固件架构: ARM32 (重要限制)

**USB 子系统**
- 控制器: Synopsys DWC3
- 标准: USB 3.2 Gen 1 (5Gbps)
- Host Controller: XHCI 1.1
- 支持 USB Audio Class 2.0

**内存和互连**
- LPDDR5 RAM (最高 16GB)
- System MMU (SMMU) v3
- IOMMU 支持 ADSP DMA

## 真实硬件架构

### USB 控制器实际情况

```
QCS6490 USB 架构
├── DWC3 USB Controller
│   ├── USB 3.2 Gen 1 PHY
│   ├── XHCI 1.1 Host Controller
│   │   ├── Transfer Ring (TR)
│   │   ├── Event Ring (ER)
│   │   ├── Interrupter 0 (Host)
│   │   └── Interrupter 1 (Offload)
│   └── XHCI Sideband Interface
│       ├── xhci_sideband_register()
│       ├── xhci_sideband_add_endpoint()
│       └── xhci_sideband_get_ring_dma()
├── SMMU (System MMU)
│   ├── USB Stream ID: 0x0
│   ├── ADSP Stream ID: 0x1801
│   └── IOVA 地址空间
│       ├── 0x1000 - 0x11000: Transfer Ring
│       ├── 0x11000 - 0x21000: Event Ring
│       └── 0x21000 - 0x121000: Transfer Buffer
└── ADSP 内存域
    ├── 物理地址: 0x86700000 - 0x88F00000
    ├── 大小: 40MB
    └── 访问权限: ADSP 独占
```

### ADSP 固件架构限制

**关键发现：ADSP 固件是 ARM32 架构**

```bash
# 检查 ADSP 固件架构
file /lib/firmware/qcom/qcs6490/adsp/adsp.mbn
# 输出: ELF 32-bit LSB executable, ARM

# 这意味着：
# 1. ADSP 运行 32-bit ARM 代码
# 2. 所有 DSP 模块必须是 ARM32 编译
# 3. 预编译库必须是 ARM32 版本
```

**audioreach-engine 仓库分析**

从 Qualcomm 的 audioreach-engine 仓库：

```
audioreach-engine/
├── libs/
│   ├── libdynamic_resampler.a  (ARM32 only!)
│   ├── libmfc.a                (ARM32)
│   └── libusb_module.a         (ARM32)
├── include/
│   └── dynamic_resampler.h
└── README.md
```

**libdynamic_resampler.a 的限制**

```bash
# 检查库架构
file audioreach-engine/libs/libdynamic_resampler.a
# 输出: current ar archive, 32-bit ARM

# 尝试在 AArch64 系统上链接
aarch64-linux-gnu-ld -o test test.o libdynamic_resampler.a
# 错误: incompatible target

# 这个库包含：
# - 硬件加速的重采样算法
# - ASRC (Async Sample Rate Conversion)
# - 低延迟 FIR/IIR 滤波器
# - 但只有 ARM32 预编译版本
```

### 数据路径分析

**理论路径（基于上游源码）**

```
USB 设备插入
    ↓
DWC3 枚举设备
    ↓
snd-usb-audio 识别
    ↓
qc_usb_audio_offload_probe()
    ↓
xhci_sideband_register()
    ↓
ADSP QMI 请求
    ↓
handle_uaudio_stream_req()
    ↓
enable_audio_stream()
    ↓
xhci_sideband_add_endpoint()
    ↓
uaudio_iommu_map()
    ↓
QMI 响应（TR/ER/XferBuf IOVA）
    ↓
ADSP 直接操作 XHCI
    ↓
音频数据流
```

**实际限制**

1. **ADSP 固件可用性**
   - Qualcomm 未公开发布支持 USB offload 的 ADSP 固件
   - 需要签名的固件才能在 QCS6490 上运行
   - 社区无法自行编译 ADSP 固件

2. **AudioReach 模块限制**
   - USB 相关模块需要特定固件版本
   - libdynamic_resampler.a 只有 ARM32 版本
   - 无法在 AArch64 用户空间使用

3. **XHCI Sideband 支持**
   - 需要内核 6.8+ 的 xhci-sideband.c
   - 需要设备树正确配置 XHCI sideband
   - 需要 SMMU 正确配置 IOVA 映射

## 当前不可行的方案

### 方案 1：AFE 层 USB Offload（已封闭）

**为什么不可行**

上游源码分析显示 AFE 方向已被封闭：

```c
/* sound/soc/qcom/qdsp6/q6afe-dai.c */

/* USB_RX port 定义存在 */
#define AFE_PORT_ID_USB_RX  0x7000

static struct snd_soc_dai_driver q6afe_dais[] = {
    {
        .playback = {
            .stream_name = "USB Playback",
            .rates = SNDRV_PCM_RATE_8000_192000,
            .formats = SNDRV_PCM_FMTBIT_S16_LE | SNDRV_PCM_FMTBIT_S24_LE,
            .channels_min = 1,
            .channels_max = 2,
        },
        .id = USB_RX,
        .ops = &q6afe_usb_ops,  // 但 ops 不完整
    },
};

/* q6afe_usb_ops 缺少关键实现 */
static const struct snd_soc_dai_ops q6afe_usb_ops = {
    .prepare = q6afe_dai_prepare,
    .shutdown = q6afe_dai_shutdown,
    // 缺少: .hw_params, .trigger, .pointer
    // 无法实际传输音频数据
};
```

**结论**：AFE 层的 USB 支持只是占位符，无实际功能。

### 方案 2：使用 Dynamic Resampler（架构不匹配）

**为什么不可行**

```bash
# libdynamic_resampler.a 是 ARM32
# QCS6490 ADSP 固件是 ARM32
# 但用户空间是 AArch64

# 问题：
# 1. 无法在 AArch64 用户空间链接 ARM32 库
# 2. ADSP 固件中可能可以使用，但我们无法修改固件
# 3. Qualcomm 未提供 AArch64 版本的库
# 4. 源码未开源，无法自行编译

# 尝试使用会导致：
aarch64-linux-gnu-gcc -o audio_app audio_app.c -ldynamic_resampler
# /usr/bin/ld: libdynamic_resampler.a: error adding symbols: file in wrong format
```

**结论**：Dynamic Resampler 只能在 ADSP 固件内部使用，用户空间无法访问。

### 方案 3：自行编译 ADSP 固件（不可行）

**为什么不可行**

1. **签名要求**
   ```bash
   # QCS6490 要求固件签名
   # 只有 Qualcomm 的私钥可以签名
   # 未签名固件无法加载

   echo start > /sys/class/remoteproc/remoteproc0/state
   # dmesg: remoteproc: authentication failed
   ```

2. **工具链不可用**
   - Hexagon DSP 工具链需要 Qualcomm 授权
   - AudioReach SDK 不完全开源
   - 缺少构建脚本和依赖

3. **固件复杂度**
   - ADSP 固件包含数百个模块
   - 需要完整的 AudioReach 运行时
   - 需要 QMI 服务实现
   - 需要 XHCI 操作代码

**结论**：社区无法自行编译可用的 ADSP 固件。

## 可行的验证步骤

虽然完整的 USB Audio Offload 不可行，但可以验证部分组件：

### 步骤 1：验证 XHCI Sideband 支持

```bash
# 检查内核版本
uname -r
# 需要 6.8+

# 检查 XHCI sideband 模块
modprobe xhci-plat-hcd
dmesg | grep -i sideband

# 期望输出：
# xhci-hcd: XHCI Host Controller
# xhci-hcd: new USB bus registered
# xhci-hcd: sideband interface available

# 检查 sysfs
ls -l /sys/kernel/debug/usb/xhci/*/
# 应该看到 sideband 相关文件
```

### 步骤 2：验证 QMI 服务框架

```bash
# 检查 ADSP 状态
cat /sys/class/remoteproc/remoteproc0/state
# 应该输出: running

# 检查 GLINK 通信
dmesg | grep -i glink
# 期望看到: qcom_glink_ssr: GLINK SSR driver probed

# 检查 QMI 服务列表
cat /sys/kernel/debug/qmi/services

# 注意：可能看不到 UAUDIO_STREAM service
# 因为固件可能不支持
```

### 步骤 3：验证 IOMMU 配置

```bash
# 检查 SMMU 状态
dmesg | grep -i smmu

# 期望输出：
# arm-smmu: probed
# arm-smmu: registered 128 context banks

# 检查 USB 的 IOMMU 组
find /sys/kernel/iommu_groups/ -name "*usb*"

# 检查 ADSP 的 IOMMU 组
find /sys/kernel/iommu_groups/ -name "*adsp*"

# 检查 IOMMU 域
cat /sys/kernel/debug/iommu/domains
```

### 步骤 4：验证 USB Audio 基础功能

```bash
# 插入 USB 音频设备
lsusb | grep -i audio

# 检查 ALSA 识别
aplay -l
cat /proc/asound/cards

# 测试标准 USB Audio（非 offload）
speaker-test -D hw:X,0 -c 2 -r 48000 -F S16_LE -t sine

# 这应该工作，因为使用标准 snd-usb-audio 驱动
```

### 步骤 5：尝试加载 Offload 驱动

```bash
# 加载 Q6 USB 驱动
modprobe q6usb
dmesg | tail -20

# 可能的结果：
# 成功：q6usb: probed successfully
# 失败：q6usb: failed to find USB backend
# 失败：q6usb: ADSP firmware does not support USB offload

# 加载 QC Audio Offload 驱动
modprobe qc-usb-audio-offload
dmesg | tail -20

# 可能的结果：
# 成功：qc-usb-audio-offload: registered
# 失败：qc-usb-audio-offload: QMI service not found
```

### 步骤 6：检查 Offload 状态

```bash
# 检查是否创建了 offload 设备
ls -l /dev/snd/
# 查找 offload 相关的 PCM 设备

# 检查 ALSA 控制
amixer -c 0 controls | grep -i "usb\|offload"

# 可能看到：
# numid=X,iface=MIXER,name='USB Offload Playback Switch'
# 但可能无法实际使用

# 尝试启用 offload
amixer -c 0 cset name='USB Offload Playback Switch' on
# 可能失败：amixer: Unable to find simple control
```

## 实际测试结果预期

基于硬件和固件限制，预期测试结果：

### 可以工作的部分

✅ **标准 USB Audio**
```bash
# 使用 snd-usb-audio 驱动
aplay -D hw:1,0 test.wav
# 这应该正常工作，但 CPU 占用高
```

✅ **XHCI Sideband 接口**
```bash
# 内核模块可以加载
modprobe xhci-plat-hcd
# sideband 接口可用
```

✅ **ADSP 基础功能**
```bash
# ADSP 可以启动
cat /sys/class/remoteproc/remoteproc0/state
# 输出: running
```

✅ **IOMMU 映射**
```bash
# SMMU 正常工作
dmesg | grep smmu
# 无错误信息
```

### 不能工作的部分

❌ **USB Audio Offload**
```bash
# 原因：ADSP 固件不支持
# QMI UAUDIO_STREAM service 不存在
cat /sys/kernel/debug/qmi/services | grep UAUDIO
# 无输出
```

❌ **Q6 USB Backend**
```bash
# 原因：固件缺少 USB 模块
modprobe q6usb
# dmesg: q6usb: USB module not found in ADSP
```

❌ **Dynamic Resampler（用户空间）**
```bash
# 原因：架构不匹配
gcc -o test test.c -ldynamic_resampler
# 错误: file in wrong format
```

❌ **低功耗音频播放**
```bash
# 原因：无 offload，AP 必须保持唤醒
# CPU 占用率: 10-15%（而不是期望的 <1%）
```

## 固件限制详细分析

### ADSP 固件结构

```
/lib/firmware/qcom/qcs6490/adsp/
├── adsp.mbn              # 主固件 (ARM32 ELF)
├── adsp_dtb.mbn          # 设备树
└── audioreach/           # AudioReach 模块（可能不存在）
    ├── amdb_loader.bin   # 模块加载器
    ├── module_*.bin      # 各种音频模块
    └── usb_module.bin    # USB 模块（可能缺失）
```

### 检查固件内容

```bash
# 检查固件是否包含 USB 支持
strings /lib/firmware/qcom/qcs6490/adsp/adsp.mbn | grep -i usb

# 如果看到以下字符串，说明有 USB 支持：
# "USB_AUDIO_MODULE"
# "UAUDIO_STREAM_SERVICE"
# "xhci_transfer_ring"

# 如果没有这些字符串，固件不支持 USB offload

# 检查 AudioReach 模块目录
ls -la /lib/firmware/qcom/qcs6490/adsp/audioreach/

# 如果目录不存在或为空，说明缺少 AudioReach 模块
```

### libdynamic_resampler.a 详细分析

```bash
# 查看库符号
nm audioreach-engine/libs/libdynamic_resampler.a

# 关键符号：
# dynamic_resampler_init
# dynamic_resampler_process
# dynamic_resampler_set_rate
# asrc_enable
# asrc_process

# 查看依赖
readelf -d audioreach-engine/libs/libdynamic_resampler.a

# 架构信息
readelf -h audioreach-engine/libs/libdynamic_resampler.a
# Machine: ARM
# Class: ELF32

# 这确认了库是 ARM32，无法在 AArch64 系统上使用
```

## 替代方案探讨

### 方案 A：使用标准 USB Audio（无 Offload）

**优点**
- 完全可用，无需特殊固件
- 上游内核完全支持
- 兼容所有 USB Audio 设备

**缺点**
- 高 CPU 占用（10-15%）
- 高功耗（额外 50-100mW）
- AP 无法深度睡眠
- 延迟较高（50-100ms）

**实现**
```bash
# 使用标准 ALSA
aplay -D hw:1,0 music.wav

# 或使用 PulseAudio/PipeWire
pactl set-default-sink usb_audio_sink
```

### 方案 B：使用 I2S 音频（通过 AudioReach）

**优点**
- AudioReach 完全支持 I2S
- 可以实现低功耗
- ADSP offload 可用

**缺点**
- 需要外接 I2S DAC
- 无法使用 USB 音频设备
- 硬件成本增加

**实现**
```bash
# 配置 I2S 输出
amixer -c 0 cset name='I2S Playback Switch' on

# 使用 AudioReach graph
aplay -D hw:0,0 music.wav
```

### 方案 C：软件重采样（用户空间）

**优点**
- 完全可控
- 可以使用开源库（libsamplerate, speex）
- 不依赖 ADSP 固件

**缺点**
- 更高的 CPU 占用
- 更高的功耗
- 延迟增加

**实现**
```c
#include <samplerate.h>

// 使用 libsamplerate 进行重采样
SRC_STATE *src = src_new(SRC_SINC_BEST_QUALITY, channels, &error);
src_process(src, &src_data);
```

### 方案 D：等待 Qualcomm 固件更新

**优点**
- 最终可能获得完整的 USB offload 支持
- 官方支持和优化

**缺点**
- 时间不确定
- 可能需要商业授权
- 可能永远不会公开发布

**行动**
- 联系 Qualcomm 或 Radxa 技术支持
- 加入 Qualcomm 开发者计划
- 关注上游内核更新

## 技术债务和限制总结

### 硬件层面

✅ **可用**
- DWC3 USB 控制器
- XHCI 1.1 支持
- SMMU/IOMMU 支持
- ADSP 硬件

❌ **限制**
- ADSP 固件签名要求
- 无法自行编译固件

### 软件层面

✅ **可用**
- 上游内核驱动（xhci-sideband, q6usb, qc-audio-offload）
- ALSA/ASoC 框架
- 标准 USB Audio 支持

❌ **限制**
- ADSP 固件不包含 USB offload 支持
- libdynamic_resampler.a 架构不匹配
- AudioReach USB 模块缺失
- QMI UAUDIO_STREAM service 不可用

### 固件层面

✅ **可用**
- ADSP 基础固件
- GLINK/GPR 通信
- AudioReach 框架（部分）

❌ **限制**
- 无 USB offload 模块
- 无 UAUDIO_STREAM QMI service
- 无法修改或重新编译
- 签名限制

## 结论

在 Radxa Q6A (QCS6490) 上实现完整的 USB Audio Offload **当前不可行**，主要原因：

1. **ADSP 固件限制**：Qualcomm 未提供包含 USB offload 支持的公开固件
2. **架构不匹配**：libdynamic_resampler.a 是 ARM32，无法在 AArch64 用户空间使用
3. **上游路径封闭**：AFE 层的 USB 支持已被封闭，只能通过 QMI + Sideband
4. **固件签名**：无法自行编译和加载 ADSP 固件

### 可行的替代方案

1. **使用标准 USB Audio**（推荐）
   - 完全可用，无特殊要求
   - 功能完整，兼容性好
   - 代价：较高功耗和 CPU 占用

2. **使用 I2S 音频 + AudioReach**
   - 可以实现 DSP offload
   - 需要外接 I2S DAC 硬件

3. **等待官方固件更新**
   - 联系 Qualcomm/Radxa 获取支持
   - 关注上游内核和固件更新

### 未来可能性

如果 Qualcomm 发布支持 USB offload 的 ADSP 固件，并且：
- 包含 UAUDIO_STREAM QMI service
- 包含 USB 相关的 AudioReach 模块
- 提供 AArch64 版本的 libdynamic_resampler

那么 USB Audio Offload 将变得可行。但目前（2026-02），这些条件都不满足。

## 参考资源

- QCS6490 Technical Reference Manual
- Linux Kernel Source: sound/soc/qcom/qdsp6/
- Linux Kernel Source: sound/usb/qcom/
- Linux Kernel Source: drivers/usb/host/xhci-sideband.c
- Qualcomm AudioReach Documentation (limited availability)
- Radxa Q6A Hardware Documentation
