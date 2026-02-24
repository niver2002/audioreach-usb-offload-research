# MFC 模块详解

## 概述

MFC (Media Format Converter) 是 Qualcomm AudioReach 框架中的一个多功能格式转换模块，能够同时执行采样率转换、位深转换和通道混音等操作。

### 基本信息

- **MODULE_ID**: `0x07001015`
- **模块类型**: 格式转换器
- **功能**: 采样率转换 + 位深转换 + 通道混音
- **位置**: 通常位于 Graph 的中间处理阶段

### 核心特性

MFC 模块是一个"瑞士军刀"式的音频处理模块，相比专用的重采样器（如 Dynamic Resampler），它提供了更全面的格式转换能力：

1. **采样率转换**: 支持任意采样率之间的转换（8kHz - 384kHz）
2. **位深转换**: 支持 16-bit、24-bit、32-bit 之间的转换
3. **通道混音**: 支持任意通道数转换（1-8 通道）
4. **灵活的重采样算法**: 支持 IIR 和 FIR 两种算法

## 核心参数详解

### PARAM_ID_MFC_OUTPUT_MEDIA_FORMAT (0x08001024)

这是 MFC 模块最重要的参数，用于配置输出音频格式。

#### 参数结构

```c
struct param_id_mfc_output_media_fmt_t {
    uint32_t sampling_rate;        // 输出采样率 (Hz)
    uint16_t bits_per_sample;      // 输出位深 (16/24/32)
    uint16_t num_channels;         // 输出通道数 (1-8)
    uint8_t  channel_mapping[8];   // 通道映射数组
} __packed;
```

#### 字段说明

**sampling_rate (采样率)**
- 范围: 8000 - 384000 Hz
- 常用值:
  - 8000: 窄带语音
  - 16000: 宽带语音
  - 44100: CD 音质
  - 48000: 专业音频标准
  - 96000/192000: 高解析度音频
  - 384000: 超高解析度音频

**bits_per_sample (位深)**
- 支持值: 16, 24, 32
- 16-bit: 标准音质，低功耗
- 24-bit: 高保真音质
- 32-bit: 专业级音质，浮点处理

**num_channels (通道数)**
- 范围: 1 - 8
- 常见配置:
  - 1: 单声道
  - 2: 立体声
  - 4: 四声道环绕
  - 6: 5.1 环绕声
  - 8: 7.1 环绕声

**channel_mapping (通道映射)**

通道映射数组定义了输出通道的布局，使用标准的 PCM 通道 ID：

```c
// 标准通道 ID 定义
#define PCM_CHANNEL_L    1   // 左声道
#define PCM_CHANNEL_R    2   // 右声道
#define PCM_CHANNEL_C    3   // 中置
#define PCM_CHANNEL_LS   4   // 左环绕
#define PCM_CHANNEL_RS   5   // 右环绕
#define PCM_CHANNEL_LFE  6   // 低音炮
#define PCM_CHANNEL_CS   7   // 中置环绕
#define PCM_CHANNEL_LB   8   // 左后
#define PCM_CHANNEL_RB   9   // 右后
```

示例配置：

```c
// 立体声配置
uint8_t stereo_map[8] = {
    PCM_CHANNEL_L,    // 通道 0: 左
    PCM_CHANNEL_R,    // 通道 1: 右
    0, 0, 0, 0, 0, 0  // 未使用
};

// 5.1 环绕声配置
uint8_t surround_51_map[8] = {
    PCM_CHANNEL_L,    // 通道 0: 左前
    PCM_CHANNEL_R,    // 通道 1: 右前
    PCM_CHANNEL_C,    // 通道 2: 中置
    PCM_CHANNEL_LFE,  // 通道 3: 低音炮
    PCM_CHANNEL_LS,   // 通道 4: 左环绕
    PCM_CHANNEL_RS,   // 通道 5: 右环绕
    0, 0              // 未使用
};
```

### PARAM_ID_MFC_RESAMPLER_CFG (0x08001025)

此参数配置 MFC 的重采样算法类型。

#### 参数结构

```c
struct param_id_mfc_resampler_cfg_t {
    uint32_t resampler_type;  // 重采样器类型
} __packed;

// 重采样器类型定义
#define MFC_RESAMPLER_TYPE_IIR  0  // IIR 滤波器
#define MFC_RESAMPLER_TYPE_FIR  1  // FIR 滤波器
```

#### 算法对比

**IIR (Infinite Impulse Response) 滤波器**

特点：
- 低延迟: 通常 < 5ms
- 低计算复杂度: CPU 占用少
- 适中的音质: 适合语音应用
- 相位非线性: 可能引入相位失真

适用场景：
- 语音通话
- 实时通信
- 低延迟要求的应用
- 功耗敏感的场景

**FIR (Finite Impulse Response) 滤波器**

特点：
- 高音质: 更好的频率响应
- 线性相位: 无相位失真
- 高计算复杂度: CPU 占用较高
- 较高延迟: 通常 10-20ms

适用场景：
- 音乐播放
- 高保真音频
- 专业音频处理
- 对音质要求高的应用

## MFC vs Dynamic Resampler 详细对比

| 特性 | MFC | Dynamic Resampler |
|------|-----|-------------------|
| **MODULE_ID** | 0x07001015 | 0x0700101F |
| **采样率转换** | ✓ (IIR/FIR) | ✓ (HW/SW) |
| **位深转换** | ✓ | ✗ |
| **通道混音** | ✓ | ✗ |
| **硬件加速** | ✗ (纯软件) | ✓ (可用 HW) |
| **动态切换** | ✗ (静态配置) | ✓ (运行时切换) |
| **ASRC 支持** | ✗ | ✓ |
| **延迟** | 低(IIR 3-5ms) / 中(FIR 10-20ms) | 可配置 (1-10ms) |
| **功耗** | 中等 | 低(HW模式) / 高(SW模式) |
| **音质** | 中(IIR) / 高(FIR) | 极高(HW) / 高(SW) |
| **灵活性** | 高 (多功能) | 低 (专用) |
| **配置复杂度** | 中等 | 高 |

### 选择建议

**选择 MFC 的场景：**

1. **需要多种格式转换**
   ```
   输入: 44.1kHz, 16-bit, 5.1 声道
   输出: 48kHz, 24-bit, 立体声
   → 使用 MFC 一次完成所有转换
   ```

2. **语音通话路径**
   ```
   使用 IIR 模式，低延迟 + 低功耗
   ```

3. **通道下混**
   ```
   5.1 环绕声 → 立体声
   7.1 环绕声 → 5.1 环绕声
   ```

4. **位深转换**
   ```
   USB 输入 24-bit → DSP 处理 16-bit
   ```

**选择 Dynamic Resampler 的场景：**

1. **仅需采样率转换**
   ```
   输入: 44.1kHz, 16-bit, 立体声
   输出: 48kHz, 16-bit, 立体声
   → 使用 Dynamic Resampler 获得最佳性能
   ```

2. **需要硬件加速**
   ```
   使用 HW 模式，最低功耗
   ```

3. **需要 ASRC (异步采样率转换)**
   ```
   处理时钟漂移问题
   ```

4. **需要运行时动态切换采样率**
   ```
   根据 USB 设备动态调整
   ```

## 使用场景详解

### 场景 1: 通用格式转换

当需要同时转换采样率、位深和通道数时，MFC 是最佳选择。

```c
// 示例: USB 音频输入格式转换
// 输入: 96kHz, 24-bit, 立体声 (USB DAC)
// 输出: 48kHz, 16-bit, 立体声 (DSP 处理)

struct param_id_mfc_output_media_fmt_t mfc_cfg = {
    .sampling_rate = 48000,
    .bits_per_sample = 16,
    .num_channels = 2,
    .channel_mapping = {
        PCM_CHANNEL_L,
        PCM_CHANNEL_R,
        0, 0, 0, 0, 0, 0
    }
};

// 使用 FIR 模式保证音质
struct param_id_mfc_resampler_cfg_t resampler_cfg = {
    .resampler_type = MFC_RESAMPLER_TYPE_FIR
};
```

### 场景 2: 语音通话路径

语音通话需要低延迟，使用 IIR 模式。

```c
// 语音通话: 宽带语音
// 输入: 48kHz, 16-bit, 单声道
// 输出: 16kHz, 16-bit, 单声道

struct param_id_mfc_output_media_fmt_t voice_cfg = {
    .sampling_rate = 16000,
    .bits_per_sample = 16,
    .num_channels = 1,
    .channel_mapping = {
        PCM_CHANNEL_C,  // 使用中置通道
        0, 0, 0, 0, 0, 0, 0
    }
};

// 使用 IIR 模式降低延迟
struct param_id_mfc_resampler_cfg_t voice_resampler = {
    .resampler_type = MFC_RESAMPLER_TYPE_IIR
};
```

### 场景 3: 多声道下混

将多声道音频下混到立体声。

```c
// 5.1 环绕声下混到立体声
// 输入: 48kHz, 24-bit, 5.1 声道
// 输出: 48kHz, 24-bit, 立体声

struct param_id_mfc_output_media_fmt_t downmix_cfg = {
    .sampling_rate = 48000,
    .bits_per_sample = 24,
    .num_channels = 2,
    .channel_mapping = {
        PCM_CHANNEL_L,
        PCM_CHANNEL_R,
        0, 0, 0, 0, 0, 0
    }
};

// MFC 会自动执行下混算法:
// L_out = L + 0.707*C + 0.707*LS
// R_out = R + 0.707*C + 0.707*RS
// (LFE 通常被过滤或混入主声道)
```

## 在 AudioReach Graph 中的位置

MFC 模块通常位于 Graph 的中间处理阶段，连接方式如下：

```
[USB AFE Module] → [MFC Module] → [Volume Module] → [I2S AFE Module]
     (输入)          (格式转换)        (音量控制)         (输出)
```

### 完整的 Graph 配置示例

```c
// 定义 Sub-Graph
#define USB_PLAYBACK_SUBGRAPH_ID  0x00001001

// 定义 Module Instance ID
#define MODULE_INSTANCE_USB_RX    0x00002001
#define MODULE_INSTANCE_MFC       0x00002002
#define MODULE_INSTANCE_VOLUME    0x00002003
#define MODULE_INSTANCE_I2S_TX    0x00002004

// Graph 拓扑定义
struct apm_sub_graph_cfg_t usb_playback_sg = {
    .sub_graph_id = USB_PLAYBACK_SUBGRAPH_ID,
    .num_modules = 4,
    .modules = {
        // USB 输入模块
        {
            .module_id = MODULE_ID_USB_RX,
            .instance_id = MODULE_INSTANCE_USB_RX,
            .max_ip_ports = 0,
            .max_op_ports = 1
        },
        // MFC 格式转换模块
        {
            .module_id = MODULE_ID_MFC,  // 0x07001015
            .instance_id = MODULE_INSTANCE_MFC,
            .max_ip_ports = 1,
            .max_op_ports = 1
        },
        // 音量控制模块
        {
            .module_id = MODULE_ID_VOLUME,
            .instance_id = MODULE_INSTANCE_VOLUME,
            .max_ip_ports = 1,
            .max_op_ports = 1
        },
        // I2S 输出模块
        {
            .module_id = MODULE_ID_I2S_TX,
            .instance_id = MODULE_INSTANCE_I2S_TX,
            .max_ip_ports = 1,
            .max_op_ports = 0
        }
    }
};

// 模块连接定义
struct apm_module_conn_cfg_t connections[] = {
    // USB RX → MFC
    {
        .src_mod_inst_id = MODULE_INSTANCE_USB_RX,
        .src_mod_op_port_id = 0,
        .dst_mod_inst_id = MODULE_INSTANCE_MFC,
        .dst_mod_ip_port_id = 0
    },
    // MFC → Volume
    {
        .src_mod_inst_id = MODULE_INSTANCE_MFC,
        .src_mod_op_port_id = 0,
        .dst_mod_inst_id = MODULE_INSTANCE_VOLUME,
        .dst_mod_ip_port_id = 0
    },
    // Volume → I2S TX
    {
        .src_mod_inst_id = MODULE_INSTANCE_VOLUME,
        .src_mod_op_port_id = 0,
        .dst_mod_inst_id = MODULE_INSTANCE_I2S_TX,
        .dst_mod_ip_port_id = 0
    }
};
```

## 配置示例

### 示例 1: 基本配置（C 代码）

```c
#include <linux/soc/qcom/apr.h>
#include <sound/q6apm.h>

int configure_mfc_module(struct q6apm_graph *graph, 
                         uint32_t module_iid,
                         uint32_t out_rate,
                         uint16_t out_bits,
                         uint16_t out_channels)
{
    struct param_id_mfc_output_media_fmt_t *mfc_fmt;
    struct apm_module_param_data_t *param_data;
    int ret;
    
    // 分配参数内存
    param_data = kzalloc(sizeof(*param_data) + sizeof(*mfc_fmt), 
                         GFP_KERNEL);
    if (!param_data)
        return -ENOMEM;
    
    // 填充参数头
    param_data->module_instance_id = module_iid;
    param_data->param_id = PARAM_ID_MFC_OUTPUT_MEDIA_FORMAT;
    param_data->param_size = sizeof(*mfc_fmt);
    
    // 填充 MFC 配置
    mfc_fmt = (void *)(param_data + 1);
    mfc_fmt->sampling_rate = out_rate;
    mfc_fmt->bits_per_sample = out_bits;
    mfc_fmt->num_channels = out_channels;
    
    // 配置立体声通道映射
    if (out_channels == 2) {
        mfc_fmt->channel_mapping[0] = PCM_CHANNEL_L;
        mfc_fmt->channel_mapping[1] = PCM_CHANNEL_R;
    }
    
    // 发送配置到 DSP
    ret = q6apm_send_param(graph, param_data);
    
    kfree(param_data);
    return ret;
}

int configure_mfc_resampler(struct q6apm_graph *graph,
                            uint32_t module_iid,
                            uint32_t resampler_type)
{
    struct param_id_mfc_resampler_cfg_t *resampler_cfg;
    struct apm_module_param_data_t *param_data;
    int ret;
    
    param_data = kzalloc(sizeof(*param_data) + sizeof(*resampler_cfg),
                         GFP_KERNEL);
    if (!param_data)
        return -ENOMEM;
    
    param_data->module_instance_id = module_iid;
    param_data->param_id = PARAM_ID_MFC_RESAMPLER_CFG;
    param_data->param_size = sizeof(*resampler_cfg);
    
    resampler_cfg = (void *)(param_data + 1);
    resampler_cfg->resampler_type = resampler_type;
    
    ret = q6apm_send_param(graph, param_data);
    
    kfree(param_data);
    return ret;
}
```

### 示例 2: 用户空间配置（伪代码）

```c
// 使用 ALSA 控制接口配置 MFC

#include <alsa/asoundlib.h>

int setup_mfc_for_usb_playback(snd_ctl_t *ctl_handle)
{
    snd_ctl_elem_value_t *control;
    int ret;
    
    snd_ctl_elem_value_alloca(&control);
    
    // 设置输出采样率为 48kHz
    snd_ctl_elem_value_set_interface(control, SND_CTL_ELEM_IFACE_MIXER);
    snd_ctl_elem_value_set_name(control, "MFC Output Sample Rate");
    snd_ctl_elem_value_set_integer(control, 0, 48000);
    ret = snd_ctl_elem_write(ctl_handle, control);
    if (ret < 0) {
        fprintf(stderr, "Failed to set sample rate: %s\n", 
                snd_strerror(ret));
        return ret;
    }
    
    // 设置输出位深为 16-bit
    snd_ctl_elem_value_set_name(control, "MFC Output Bit Depth");
    snd_ctl_elem_value_set_integer(control, 0, 16);
    ret = snd_ctl_elem_write(ctl_handle, control);
    
    // 设置输出通道数为 2 (立体声)
    snd_ctl_elem_value_set_name(control, "MFC Output Channels");
    snd_ctl_elem_value_set_integer(control, 0, 2);
    ret = snd_ctl_elem_write(ctl_handle, control);
    
    // 设置重采样器类型为 FIR
    snd_ctl_elem_value_set_name(control, "MFC Resampler Type");
    snd_ctl_elem_value_set_enumerated(control, 0, 1); // 1 = FIR
    ret = snd_ctl_elem_write(ctl_handle, control);
    
    return 0;
}
```

### 示例 3: 拓扑文件配置（M4 宏）

```m4
# USB 播放 Graph 中的 MFC 模块配置

# 定义 MFC 模块
DEFINE_MODULE(MFC_MODULE,
    MODULE_ID, 0x07001015,
    INSTANCE_ID, 0x00002002,
    MAX_INPUT_PORTS, 1,
    MAX_OUTPUT_PORTS, 1
)

# 配置 MFC 输出格式
DEFINE_PARAM(MFC_OUTPUT_FORMAT,
    MODULE_INSTANCE, 0x00002002,
    PARAM_ID, 0x08001024,
    SAMPLING_RATE, 48000,
    BITS_PER_SAMPLE, 16,
    NUM_CHANNELS, 2,
    CHANNEL_MAP, [PCM_CHANNEL_L, PCM_CHANNEL_R]
)

# 配置 MFC 重采样器
DEFINE_PARAM(MFC_RESAMPLER,
    MODULE_INSTANCE, 0x00002002,
    PARAM_ID, 0x08001025,
    RESAMPLER_TYPE, MFC_RESAMPLER_TYPE_FIR
)

# 连接 USB RX → MFC
CONNECT_MODULES(
    SRC_MODULE, USB_RX_MODULE,
    SRC_PORT, 0,
    DST_MODULE, MFC_MODULE,
    DST_PORT, 0
)

# 连接 MFC → Volume
CONNECT_MODULES(
    SRC_MODULE, MFC_MODULE,
    SRC_PORT, 0,
    DST_MODULE, VOLUME_MODULE,
    DST_PORT, 0
)
```

## 最佳实践

### 1. 选择合适的重采样算法

```c
// 根据应用场景选择算法
uint32_t select_resampler_type(enum audio_use_case use_case)
{
    switch (use_case) {
    case USE_CASE_VOICE_CALL:
    case USE_CASE_VOIP:
    case USE_CASE_VOICE_REC:
        // 语音场景: 使用 IIR 降低延迟
        return MFC_RESAMPLER_TYPE_IIR;
        
    case USE_CASE_MUSIC:
    case USE_CASE_MOVIE:
    case USE_CASE_HIFI:
        // 音乐场景: 使用 FIR 提高音质
        return MFC_RESAMPLER_TYPE_FIR;
        
    default:
        // 默认使用 FIR
        return MFC_RESAMPLER_TYPE_FIR;
    }
}
```

### 2. 优化通道映射

```c
// 根据输入通道数智能配置输出映射
void setup_channel_mapping(uint16_t in_channels, 
                          uint16_t out_channels,
                          uint8_t *channel_map)
{
    memset(channel_map, 0, 8);
    
    if (in_channels == 6 && out_channels == 2) {
        // 5.1 → 立体声下混
        channel_map[0] = PCM_CHANNEL_L;
        channel_map[1] = PCM_CHANNEL_R;
        // MFC 会自动混入中置和环绕声道
    } else if (in_channels == 2 && out_channels == 2) {
        // 立体声 → 立体声
        channel_map[0] = PCM_CHANNEL_L;
        channel_map[1] = PCM_CHANNEL_R;
    } else if (in_channels == 1 && out_channels == 2) {
        // 单声道 → 立体声上混
        channel_map[0] = PCM_CHANNEL_L;
        channel_map[1] = PCM_CHANNEL_R;
        // MFC 会将单声道复制到两个通道
    }
}
```

### 3. 避免不必要的转换

```c
// 检查是否需要 MFC
bool need_mfc_conversion(struct audio_format *in_fmt,
                        struct audio_format *out_fmt)
{
    // 如果格式完全相同，不需要 MFC
    if (in_fmt->sample_rate == out_fmt->sample_rate &&
        in_fmt->bit_depth == out_fmt->bit_depth &&
        in_fmt->channels == out_fmt->channels) {
        return false;
    }
    
    // 如果只需要采样率转换，考虑使用 Dynamic Resampler
    if (in_fmt->bit_depth == out_fmt->bit_depth &&
        in_fmt->channels == out_fmt->channels) {
        // 建议使用 Dynamic Resampler
        pr_info("Consider using Dynamic Resampler instead\n");
    }
    
    return true;
}
```

### 4. 性能监控

```c
// 监控 MFC 模块性能
struct mfc_perf_stats {
    uint64_t total_samples_processed;
    uint32_t avg_processing_time_us;
    uint32_t max_processing_time_us;
    uint32_t cpu_usage_percent;
};

int get_mfc_performance(struct q6apm_graph *graph,
                       uint32_t module_iid,
                       struct mfc_perf_stats *stats)
{
    // 通过 APM 查询模块性能统计
    return q6apm_get_module_stats(graph, module_iid, stats);
}
```

## 调试和故障排查

### 常见问题

**问题 1: MFC 模块初始化失败**

```bash
# 检查 ADSP 日志
dmesg | grep -i "mfc\|0x07001015"

# 可能的错误信息:
# "MFC: Unsupported output format"
# "MFC: Invalid channel mapping"
# "MFC: Resampler initialization failed"
```

解决方案：
- 检查输出格式参数是否在支持范围内
- 验证通道映射配置是否正确
- 确认 ADSP 固件版本支持 MFC 模块

**问题 2: 音质下降**

如果使用 IIR 模式音质不佳：
```c
// 切换到 FIR 模式
configure_mfc_resampler(graph, module_iid, MFC_RESAMPLER_TYPE_FIR);
```

**问题 3: 延迟过高**

如果使用 FIR 模式延迟过高：
```c
// 切换到 IIR 模式
configure_mfc_resampler(graph, module_iid, MFC_RESAMPLER_TYPE_IIR);
```

### 调试命令

```bash
# 查看 MFC 模块状态
cat /sys/kernel/debug/audioreach/module_info | grep -A 10 "0x07001015"

# 查看当前配置
amixer -c 0 contents | grep -i "mfc"

# 启用详细日志
echo 8 > /proc/sys/kernel/printk
echo "module q6apm +p" > /sys/kernel/debug/dynamic_debug/control
echo "module q6apm-dai +p" > /sys/kernel/debug/dynamic_debug/control
```

## 性能特征

### CPU 使用率

不同配置下的 CPU 使用率（基于 QCS6490）：

| 配置 | CPU 使用率 | 延迟 | 音质 |
|------|-----------|------|------|
| IIR, 48kHz→48kHz | 2-3% | 3ms | 中 |
| FIR, 48kHz→48kHz | 5-7% | 15ms | 高 |
| IIR, 44.1kHz→48kHz | 4-5% | 4ms | 中 |
| FIR, 44.1kHz→48kHz | 8-10% | 18ms | 高 |
| IIR, 96kHz→48kHz | 6-8% | 5ms | 中 |
| FIR, 96kHz→48kHz | 12-15% | 20ms | 高 |

### 内存占用

```c
// MFC 模块内存占用估算
size_t estimate_mfc_memory(uint32_t sample_rate, 
                          uint16_t channels,
                          uint32_t resampler_type)
{
    size_t base_memory = 64 * 1024;  // 64KB 基础内存
    size_t buffer_memory = 0;
    
    if (resampler_type == MFC_RESAMPLER_TYPE_FIR) {
        // FIR 需要更大的缓冲区
        buffer_memory = (sample_rate / 1000) * channels * 4 * 2;
    } else {
        // IIR 缓冲区较小
        buffer_memory = (sample_rate / 1000) * channels * 4;
    }
    
    return base_memory + buffer_memory;
}
```

## 高级用法

### 动态调整输出格式

```c
// 运行时动态调整 MFC 输出格式
int update_mfc_output_format(struct q6apm_graph *graph,
                             uint32_t module_iid,
                             uint32_t new_rate)
{
    struct param_id_mfc_output_media_fmt_t mfc_fmt;
    int ret;
    
    // 先暂停 Graph
    ret = q6apm_graph_stop(graph);
    if (ret < 0)
        return ret;
    
    // 更新 MFC 配置
    mfc_fmt.sampling_rate = new_rate;
    mfc_fmt.bits_per_sample = 16;
    mfc_fmt.num_channels = 2;
    mfc_fmt.channel_mapping[0] = PCM_CHANNEL_L;
    mfc_fmt.channel_mapping[1] = PCM_CHANNEL_R;
    
    ret = configure_mfc_module(graph, module_iid, 
                              new_rate, 16, 2);
    if (ret < 0)
        return ret;
    
    // 重新启动 Graph
    return q6apm_graph_start(graph);
}
```

### 级联多个 MFC 模块

在某些复杂场景下，可能需要级联多个 MFC 模块：

```c
// 场景: 96kHz 5.1 → 48kHz 立体声
// 方案 1: 单个 MFC (推荐)
// [USB RX] → [MFC: 96k 5.1 → 48k 2.0] → [Volume]

// 方案 2: 级联 MFC (不推荐，仅用于特殊需求)
// [USB RX] → [MFC1: 96k → 48k] → [MFC2: 5.1 → 2.0] → [Volume]

struct apm_module_conn_cfg_t cascaded_mfc[] = {
    // USB RX → MFC1 (采样率转换)
    {
        .src_mod_inst_id = MODULE_INSTANCE_USB_RX,
        .src_mod_op_port_id = 0,
        .dst_mod_inst_id = MODULE_INSTANCE_MFC1,
        .dst_mod_ip_port_id = 0
    },
    // MFC1 → MFC2 (通道下混)
    {
        .src_mod_inst_id = MODULE_INSTANCE_MFC1,
        .src_mod_op_port_id = 0,
        .dst_mod_inst_id = MODULE_INSTANCE_MFC2,
        .dst_mod_ip_port_id = 0
    },
    // MFC2 → Volume
    {
        .src_mod_inst_id = MODULE_INSTANCE_MFC2,
        .src_mod_op_port_id = 0,
        .dst_mod_inst_id = MODULE_INSTANCE_VOLUME,
        .dst_mod_ip_port_id = 0
    }
};

// 注意: 级联会增加延迟和 CPU 占用，通常不推荐
```

## 总结

MFC 模块是 AudioReach 中的多功能格式转换工具，适合需要同时进行多种格式转换的场景。选择 MFC 还是 Dynamic Resampler 取决于具体需求：

- **使用 MFC**: 需要位深转换、通道混音，或多种转换同时进行
- **使用 Dynamic Resampler**: 仅需采样率转换，追求最佳性能和音质

合理配置 MFC 的重采样算法（IIR/FIR）可以在延迟和音质之间取得最佳平衡。

### 快速决策树

```
需要格式转换？
├─ 仅采样率转换
│  └─ 使用 Dynamic Resampler
└─ 多种转换（采样率+位深+通道）
   └─ 使用 MFC
      ├─ 低延迟需求（语音）→ IIR 模式
      └─ 高音质需求（音乐）→ FIR 模式
```
