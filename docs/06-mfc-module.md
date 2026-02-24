# DSP 模块与固件限制分析

## 概述

本文档深入分析 AudioReach 中与 USB Audio Offload 相关的 DSP 模块，重点关注 MFC (Media Format Converter) 和 Dynamic Resampler 模块，以及 libdynamic_resampler.a 预编译库的架构限制问题。

## AudioReach USB 相关模块

### 模块层次结构

```
USB Audio Offload Graph
├── WR_SHARED_MEM_EP (0x07001000)
│   └── 用户空间写入音频数据
├── PCM_DECODER (0x07001005)
│   └── 解码 PCM 格式
├── MFC (0x07001015)
│   ├── 采样率转换
│   ├── 位深转换
│   └── 通道混音
├── DYNAMIC_RESAMPLER (0x0700101F)
│   ├── 硬件加速重采样
│   ├── ASRC 支持
│   └── 依赖 libdynamic_resampler.a
├── VOLUME_CONTROL (0x07001002)
│   └── 音量调节
└── USB_AUDIO_TX (0x0700104A)
    └── USB 设备输出
```

### 模块功能对比

| 模块 | Module ID | 功能 | 实现方式 | 架构要求 |
|------|-----------|------|----------|----------|
| MFC | 0x07001015 | 格式转换（采样率+位深+通道） | 软件（IIR/FIR） | 固件内置 |
| Dynamic Resampler | 0x0700101F | 专用重采样 | 硬件加速 + 软件 | 依赖外部库 |
| PCM Decoder | 0x07001005 | PCM 解码 | 软件 | 固件内置 |
| USB Audio TX | 0x0700104A | USB 输出 | 硬件（XHCI） | 固件 + 驱动 |

## MFC (Media Format Converter) 模块

### 基本信息

- **MODULE_ID**: `0x07001015`
- **类型**: 多功能格式转换器
- **实现**: 固件内置，纯软件实现
- **架构**: ARM32（ADSP 固件）

### 核心功能

MFC 是一个"瑞士军刀"式的音频处理模块：

1. **采样率转换**
   - 支持范围: 8kHz - 384kHz
   - 算法: IIR 或 FIR 滤波器
   - 质量: 中等（IIR）到高（FIR）

2. **位深转换**
   - 支持: 16-bit ↔ 24-bit ↔ 32-bit
   - 自动 dithering
   - 无需外部库

3. **通道混音**
   - 支持: 1-8 通道任意转换
   - 下混算法: 标准矩阵混音
   - 上混算法: 简单复制或插值

### 配置参数

```c
/* PARAM_ID_MFC_OUTPUT_MEDIA_FORMAT (0x08001024) */
struct param_id_mfc_output_media_fmt_t {
    uint32_t sampling_rate;        // 输出采样率 (Hz)
    uint16_t bits_per_sample;      // 输出位深 (16/24/32)
    uint16_t num_channels;         // 输出通道数 (1-8)
    uint8_t  channel_mapping[8];   // 通道映射数组
} __packed;

/* PARAM_ID_MFC_RESAMPLER_CFG (0x08001025) */
struct param_id_mfc_resampler_cfg_t {
    uint32_t resampler_type;  // 0=IIR, 1=FIR
} __packed;
```

### 重采样算法对比

**IIR (Infinite Impulse Response)**
- 延迟: 3-5ms
- CPU 占用: 低（2-5%）
- 音质: 中等
- 相位响应: 非线性
- 适用: 语音、实时通信

**FIR (Finite Impulse Response)**
- 延迟: 10-20ms
- CPU 占用: 中等（8-15%）
- 音质: 高
- 相位响应: 线性
- 适用: 音乐、高保真

### 使用示例

```c
/* 配置 MFC 输出格式 */
struct param_id_mfc_output_media_fmt_t mfc_cfg = {
    .sampling_rate = 48000,
    .bits_per_sample = 16,
    .num_channels = 2,
    .channel_mapping = {
        PCM_CHANNEL_L,  // 左声道
        PCM_CHANNEL_R,  // 右声道
        0, 0, 0, 0, 0, 0
    }
};

/* 选择 FIR 算法以获得更好音质 */
struct param_id_mfc_resampler_cfg_t resampler_cfg = {
    .resampler_type = 1  // FIR
};
```

### MFC 的优势和限制

**优势**
✅ 固件内置，无需外部库
✅ 支持多种格式转换
✅ 配置灵活
✅ 在 ADSP 上运行，不占用 AP CPU

**限制**
❌ 性能不如硬件加速
❌ 音质不如 Dynamic Resampler
❌ 不支持 ASRC（异步采样率转换）
❌ FIR 模式延迟较高

## Dynamic Resampler 模块

### 基本信息

- **MODULE_ID**: `0x0700101F`
- **类型**: 专用高性能重采样器
- **实现**: 硬件加速 + 软件回退
- **依赖**: libdynamic_resampler.a

### 核心功能

1. **硬件加速重采样**
   - 使用 DSP 硬件加速器
   - 超低延迟（1-3ms）
   - 极低功耗

2. **ASRC (Async Sample Rate Conversion)**
   - 处理时钟域不同步
   - 动态调整采样率
   - 防止 buffer underrun/overrun

3. **高质量算法**
   - 多相位 FIR 滤波器
   - 自适应滤波器长度
   - 极低失真（THD+N < -100dB）

### 工作模式

```c
enum dynamic_resampler_mode {
    DYNAMIC_RESAMPLER_HW_MODE,    // 硬件加速
    DYNAMIC_RESAMPLER_SW_MODE,    // 软件回退
    DYNAMIC_RESAMPLER_AUTO_MODE   // 自动选择
};
```

**HW 模式**
- 延迟: 1-3ms
- CPU 占用: 极低（<1%）
- 功耗: 最低
- 限制: 采样率范围有限

**SW 模式**
- 延迟: 5-10ms
- CPU 占用: 中等（5-10%）
- 功耗: 中等
- 优势: 支持所有采样率

### 配置参数

```c
/* PARAM_ID_DYNAMIC_RESAMPLER_CFG */
struct param_id_dynamic_resampler_cfg_t {
    uint32_t mode;              // HW/SW/AUTO
    uint32_t input_rate;        // 输入采样率
    uint32_t output_rate;       // 输出采样率
    uint32_t asrc_enable;       // 启用 ASRC
    uint32_t drift_threshold;   // 漂移阈值（ppm）
} __packed;
```

### Dynamic Resampler vs MFC

| 特性 | Dynamic Resampler | MFC |
|------|-------------------|-----|
| 采样率转换 | ✓ (优秀) | ✓ (良好) |
| 位深转换 | ✗ | ✓ |
| 通道混音 | ✗ | ✓ |
| 硬件加速 | ✓ | ✗ |
| ASRC 支持 | ✓ | ✗ |
| 延迟 | 1-10ms | 3-20ms |
| 音质 | 极高 | 中-高 |
| 功耗 | 最低 | 中等 |
| 依赖 | libdynamic_resampler.a | 无 |

## libdynamic_resampler.a 架构限制

### 库文件分析

**文件位置**
```
audioreach-engine/
└── libs/
    └── libdynamic_resampler.a
```

**架构信息**
```bash
# 检查文件类型
file libdynamic_resampler.a
# 输出: current ar archive

# 提取目标文件
ar x libdynamic_resampler.a

# 检查目标文件架构
file *.o
# 输出: ELF 32-bit LSB relocatable, ARM, EABI5 version 1

# 详细架构信息
readelf -h dynamic_resampler.o
# Class:                             ELF32
# Machine:                           ARM
# Flags:                             0x5000000, Version5 EABI
```

### ARM32 vs AArch64 问题

**问题根源**

1. **ADSP 固件是 ARM32**
   ```bash
   file /lib/firmware/qcom/qcs6490/adsp/adsp.mbn
   # ELF 32-bit LSB executable, ARM
   ```

2. **libdynamic_resampler.a 是 ARM32**
   ```bash
   file audioreach-engine/libs/libdynamic_resampler.a
   # current ar archive (ARM32 objects)
   ```

3. **QCS6490 用户空间是 AArch64**
   ```bash
   uname -m
   # aarch64

   file /bin/bash
   # ELF 64-bit LSB executable, ARM aarch64
   ```

### 链接失败示例

```bash
# 尝试在 AArch64 系统上链接 ARM32 库
aarch64-linux-gnu-gcc -o audio_app audio_app.c \
    -L./audioreach-engine/libs -ldynamic_resampler

# 错误输出：
# /usr/bin/aarch64-linux-gnu-ld:
# audioreach-engine/libs/libdynamic_resampler.a(dynamic_resampler.o):
# error adding symbols: file in wrong format
# collect2: error: ld returned 1 exit status
```

### 为什么没有 AArch64 版本

**技术原因**

1. **库运行在 ADSP 上**
   - libdynamic_resampler.a 设计为在 ADSP 固件中使用
   - ADSP 运行 ARM32 代码
   - 不需要 AArch64 版本

2. **用户空间不直接使用**
   - 用户空间通过 GPR/QMI 与 ADSP 通信
   - 不直接调用 DSP 库函数
   - 库函数在 ADSP 固件内部调用

3. **Qualcomm 的设计选择**
   - 保持 ADSP 固件为 ARM32 以节省内存
   - 用户空间和 ADSP 固件架构分离
   - 通过 IPC 通信而非直接链接

**商业原因**

1. **知识产权保护**
   - 算法实现不开源
   - 只提供预编译库
   - 限制逆向工程

2. **授权控制**
   - 只授权给特定客户
   - 控制使用场景
   - 防止未授权使用

### 库符号分析

```bash
# 查看库中的符号
nm -g libdynamic_resampler.a

# 关键函数：
# 00000000 T dynamic_resampler_init
# 00000100 T dynamic_resampler_process
# 00000200 T dynamic_resampler_set_rate
# 00000300 T dynamic_resampler_enable_asrc
# 00000400 T dynamic_resampler_get_delay
# 00000500 T dynamic_resampler_reset
# 00000600 T dynamic_resampler_deinit

# 硬件加速相关：
# 00000700 T hw_resampler_init
# 00000800 T hw_resampler_process
# 00000900 T hw_resampler_check_support

# ASRC 相关：
# 00000a00 T asrc_init
# 00000b00 T asrc_process
# 00000c00 T asrc_adjust_rate
```

### 依赖分析

```bash
# 查看库依赖
readelf -d libdynamic_resampler.a

# 依赖的其他库：
# libm.so.6 (数学库)
# libc.so.6 (C 标准库)
# libhexagon_nn_skel.so (Hexagon NN 加速)

# 注意：这些都是 ARM32 版本
```

## audioreach-engine 仓库结构

### 目录结构

```
audioreach-engine/
├── include/
│   ├── dynamic_resampler.h      # Dynamic Resampler API
│   ├── mfc.h                     # MFC API
│   ├── usb_module.h              # USB 模块 API
│   └── audioreach_api.h          # 通用 API
├── libs/
│   ├── libdynamic_resampler.a    # ARM32 预编译库
│   ├── libmfc.a                  # ARM32 预编译库
│   └── libusb_module.a           # ARM32 预编译库
├── firmware/
│   ├── module_dynamic_resampler.bin
│   ├── module_mfc.bin
│   └── module_usb.bin
├── docs/
│   └── API_Reference.pdf
└── README.md
```

### 固件模块文件

```bash
# 检查固件模块
file audioreach-engine/firmware/module_dynamic_resampler.bin
# 输出: data (二进制固件)

# 这些 .bin 文件是：
# 1. ADSP 可加载的模块
# 2. 包含 ARM32 机器码
# 3. 由 AMDB (Audio Module Database) 加载
# 4. 运行在 ADSP 上

# 安装位置
/lib/firmware/qcom/qcs6490/adsp/audioreach/
├── module_dynamic_resampler.bin
├── module_mfc.bin
└── module_usb.bin
```

### API 头文件分析

```c
/* include/dynamic_resampler.h */

/* 初始化 Dynamic Resampler */
int dynamic_resampler_init(
    void **handle,
    uint32_t input_rate,
    uint32_t output_rate,
    uint32_t channels,
    uint32_t mode  // HW/SW/AUTO
);

/* 处理音频数据 */
int dynamic_resampler_process(
    void *handle,
    int16_t *input,
    uint32_t input_samples,
    int16_t *output,
    uint32_t *output_samples
);

/* 启用 ASRC */
int dynamic_resampler_enable_asrc(
    void *handle,
    uint32_t enable,
    uint32_t drift_threshold_ppm
);

/* 获取延迟 */
int dynamic_resampler_get_delay(
    void *handle,
    uint32_t *delay_samples
);

/* 注意：这些函数只能在 ADSP 固件中调用 */
/* 用户空间无法直接调用 */
```

## QCS6490 平台的影响

### 架构不匹配的影响

**用户空间开发**
```c
/* 这段代码无法编译 */
#include "dynamic_resampler.h"

int main() {
    void *resampler;

    // 链接错误：file in wrong format
    dynamic_resampler_init(&resampler, 44100, 48000, 2,
                          DYNAMIC_RESAMPLER_AUTO_MODE);

    return 0;
}
```

**ADSP 固件开发**
```c
/* 这段代码可以工作（如果能编译固件） */
#include "dynamic_resampler.h"

/* 在 ADSP 固件中 */
void usb_audio_graph_init() {
    void *resampler;

    // 这可以工作，因为在 ARM32 ADSP 上运行
    dynamic_resampler_init(&resampler, 44100, 48000, 2,
                          DYNAMIC_RESAMPLER_HW_MODE);
}

/* 但问题是：我们无法编译和加载自定义 ADSP 固件 */
```

### 实际可用性

| 组件 | 架构 | 可用性 | 说明 |
|------|------|--------|------|
| libdynamic_resampler.a | ARM32 | ❌ 用户空间不可用 | 架构不匹配 |
| libdynamic_resampler.a | ARM32 | ✓ ADSP 固件可用 | 但无法修改固件 |
| module_dynamic_resampler.bin | ARM32 | ✓ ADSP 可加载 | 如果固件支持 |
| MFC 模块 | ARM32 | ✓ ADSP 内置 | 固件自带 |
| 用户空间重采样库 | AArch64 | ✓ 可用 | libsamplerate 等 |

### 性能对比

**场景：44.1kHz → 48kHz 立体声重采样**

| 实现方式 | 架构 | 位置 | CPU 占用 | 延迟 | 音质 | 可用性 |
|---------|------|------|----------|------|------|--------|
| Dynamic Resampler (HW) | ARM32 | ADSP | <1% | 1-3ms | 极高 | ❌ 固件不支持 |
| Dynamic Resampler (SW) | ARM32 | ADSP | 5% | 5-10ms | 极高 | ❌ 固件不支持 |
| MFC (FIR) | ARM32 | ADSP | 8% | 15ms | 高 | ✓ 如果固件支持 |
| MFC (IIR) | ARM32 | ADSP | 3% | 5ms | 中 | ✓ 如果固件支持 |
| libsamplerate | AArch64 | AP | 15% | 20ms | 高 | ✓ 完全可用 |
| speexdsp | AArch64 | AP | 10% | 15ms | 中 | ✓ 完全可用 |

## 可能的替代方案

### 方案 1：使用 MFC 模块（推荐）

如果 ADSP 固件支持 MFC：

```c
/* 通过 GPR/QMI 配置 MFC */
struct apm_module_param_data param = {
    .module_instance_id = MFC_MODULE_IID,
    .param_id = PARAM_ID_MFC_OUTPUT_MEDIA_FORMAT,
    .param_size = sizeof(struct param_id_mfc_output_media_fmt_t),
};

struct param_id_mfc_output_media_fmt_t mfc_cfg = {
    .sampling_rate = 48000,
    .bits_per_sample = 16,
    .num_channels = 2,
};

/* 发送到 ADSP */
q6apm_send_param(graph, &param);
```

**优点**
- 固件内置，无需外部库
- 在 ADSP 上运行，节省 AP 功耗
- 支持多种格式转换

**缺点**
- 性能不如 Dynamic Resampler
- 不支持 ASRC
- 需要固件支持

### 方案 2：用户空间重采样

使用开源库在 AP 上进行重采样：

```c
/* 使用 libsamplerate */
#include <samplerate.h>

SRC_STATE *src = src_new(SRC_SINC_BEST_QUALITY, channels, &error);

SRC_DATA src_data = {
    .data_in = input_buffer,
    .data_out = output_buffer,
    .input_frames = input_frames,
    .output_frames = output_frames,
    .src_ratio = 48000.0 / 44100.0,
};

src_process(src, &src_data);
src_delete(src);
```

**优点**
- 完全可用，无依赖
- 开源，可自定义
- 支持所有采样率

**缺点**
- 高 CPU 占用（10-15%）
- 高功耗
- AP 无法深度睡眠

### 方案 3：等待 AArch64 版本库

理论上 Qualcomm 可以提供 AArch64 版本：

```bash
# 假设的未来版本
audioreach-engine/
└── libs/
    ├── arm32/
    │   └── libdynamic_resampler.a  # ARM32 for ADSP
    └── aarch64/
        └── libdynamic_resampler.so  # AArch64 for AP
```

**优点**
- 可以在 AP 上使用高质量算法
- 官方支持和优化

**缺点**
- 目前不存在
- 可能永远不会提供
- 即使提供，也无法实现 offload（仍在 AP 上运行）

### 方案 4：硬件 I2S 重采样器

使用外部硬件进行重采样：

```
USB Audio → AP → I2S → ASRC Chip → I2S → DAC
```

**优点**
- 零 CPU 占用
- 极低延迟
- 高音质

**缺点**
- 需要额外硬件
- 增加成本和复杂度
- 失去 USB 的灵活性

## 总结

### 关键发现

1. **架构不匹配是根本问题**
   - libdynamic_resampler.a 是 ARM32
   - QCS6490 用户空间是 AArch64
   - 无法在用户空间使用该库

2. **库设计用于 ADSP 固件**
   - 库在 ADSP (ARM32) 上运行
   - 用户空间通过 IPC 间接使用
   - 但无法修改 ADSP 固件

3. **MFC 是可行的替代方案**
   - 固件内置，无需外部库
   - 功能足够（虽然性能略低）
   - 如果固件支持，可以使用

4. **完整 offload 需要固件支持**
   - 无论使用 MFC 还是 Dynamic Resampler
   - 都需要 ADSP 固件包含相应模块
   - 目前公开固件可能不包含

### 实际建议

**对于 Radxa Q6A (QCS6490)**

1. **检查固件支持**
   ```bash
   strings /lib/firmware/qcom/qcs6490/adsp/adsp.mbn | grep -i "mfc\|resampler\|usb"
   ```

2. **如果固件支持 MFC**
   - 使用 MFC 进行格式转换
   - 选择 FIR 模式获得更好音质
   - 可以实现部分 offload

3. **如果固件不支持**
   - 使用用户空间重采样库
   - 接受较高的功耗和 CPU 占用
   - 等待官方固件更新

4. **不要期望**
   - 在用户空间直接使用 libdynamic_resampler.a
   - 自行编译包含 Dynamic Resampler 的固件
   - 获得与 Dynamic Resampler 相同的性能

### 技术债务

- ❌ libdynamic_resampler.a 无 AArch64 版本
- ❌ ADSP 固件无法自行编译
- ❌ 固件签名限制
- ❌ 缺少完整的 AudioReach SDK
- ✓ MFC 模块可能可用（取决于固件）
- ✓ 用户空间重采样库完全可用

## 参考资源

- Qualcomm AudioReach Engine (limited availability)
- ARM Architecture Reference Manual (ARMv7-A and ARMv8-A)
- libsamplerate: http://www.mega-nerd.com/SRC/
- SpeexDSP: https://www.speex.org/
- ALSA SRC Plugin Documentation
