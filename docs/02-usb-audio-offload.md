# USB Audio Offload 技术详解

## 概述

USB Audio Offload 是一种将 USB 音频处理从主处理器（AP）卸载到专用音频 DSP 的技术。传统的 USB 音频处理完全在 AP 上进行，导致高功耗和高延迟。通过 Offload 技术，音频数据可以直接在 DSP 和 USB 控制器之间传输，绕过 AP，从而实现低功耗、低延迟的音频播放和录音。

在 Qualcomm 平台上，USB Audio Offload 结合了 AudioReach 框架和 USB Audio Class 2.0 协议，提供了完整的硬件加速音频解决方案。

## 传统 USB 音频 vs Offload 模式

### 传统模式（Non-Offload）

**特点：**
- AP 处理所有 USB 音频数据传输
- 高 CPU 占用率（5-15%）
- 高功耗（额外 50-100mW）
- 延迟较高（50-100ms）
- AP 无法进入深度睡眠

### Offload 模式

**特点：**
- ADSP 直接控制 USB 数据传输
- 低 CPU 占用率（<1%）
- 低功耗（节省 50-100mW）
- 低延迟（10-30ms）
- AP 可以进入深度睡眠
- 支持长时间音频播放

## 系统架构

### 硬件架构

**关键组件：**

1. **USB Controller (DWC3)**
   - 支持 USB 3.0/2.0
   - 支持 Isochronous 传输
   - 支持 DMA 到 ADSP 内存
   - 支持 Audio Class 2.0

2. **Audio DSP (ADSP/CDSP)**
   - 运行 AudioReach 框架
   - 管理 USB 音频 Graph
   - 处理音频格式转换
   - 控制 USB 传输

3. **Application Processor**
   - 初始化 USB 连接
   - 配置 Offload 参数
   - 监控连接状态
   - 处理控制命令

### 软件架构层次

**软件层次：**

1. **用户空间**
   - AudioFlinger/AudioTrack
   - Audio HAL (audio.usb.default.so)
   - TinyALSA/ALSA-lib

2. **内核空间**
   - ALSA USB Audio Driver (snd-usb-audio)
   - Q6 USB Offload Driver (q6usb)
   - USB Core (usb-core)
   - USB Controller Driver (dwc3)

3. **DSP 空间**
   - AudioReach APM
   - USB Audio Module
   - SPF Framework

## AudioReach USB Offload Graph

### Graph 结构

USB Offload 使用专门的 AudioReach Graph，包含 USB 特定的模块。

**Playback Graph 配置：**

```c
struct usb_offload_playback_graph {
    // Subgraph 1: Stream Processing
    struct subgraph stream_sg = {
        .id = USB_STREAM_SUBGRAPH_ID,
        .containers = {
            {
                .id = USB_STREAM_CONTAINER_ID,
                .modules = {
                    {.id = MODULE_ID_WR_SHARED_MEM_EP, .iid = 0x1001},
                    {.id = MODULE_ID_PCM_DEC, .iid = 0x1002},
                    {.id = MODULE_ID_RATE_ADAPTER, .iid = 0x1003},
                },
            },
        },
    };
    
    // Subgraph 2: USB Device
    struct subgraph usb_sg = {
        .id = USB_DEVICE_SUBGRAPH_ID,
        .containers = {
            {
                .id = USB_DEVICE_CONTAINER_ID,
                .modules = {
                    {.id = MODULE_ID_USB_AUDIO_TX, .iid = 0x2001},
                },
            },
        },
    };
    
    // Connections
    struct connections = {
        {0x1001, 1, 0x1002, 2},  // Shared Mem -> Decoder
        {0x1002, 1, 0x1003, 2},  // Decoder -> Rate Adapter
        {0x1003, 1, 0x2001, 2},  // Rate Adapter -> USB TX
    };
};
```

**Capture Graph 配置：**

```c
struct usb_offload_capture_graph {
    // Subgraph 1: USB Device
    struct subgraph usb_sg = {
        .id = USB_DEVICE_SUBGRAPH_ID,
        .containers = {
            {
                .id = USB_DEVICE_CONTAINER_ID,
                .modules = {
                    {.id = MODULE_ID_USB_AUDIO_RX, .iid = 0x1001},
                },
            },
        },
    };
    
    // Subgraph 2: Stream Processing
    struct subgraph stream_sg = {
        .id = USB_STREAM_SUBGRAPH_ID,
        .containers = {
            {
                .id = USB_STREAM_CONTAINER_ID,
                .modules = {
                    {.id = MODULE_ID_RATE_ADAPTER, .iid = 0x2001},
                    {.id = MODULE_ID_PCM_ENC, .iid = 0x2002},
                    {.id = MODULE_ID_RD_SHARED_MEM_EP, .iid = 0x2003},
                },
            },
        },
    };
    
    // Connections
    struct connections = {
        {0x1001, 1, 0x2001, 2},  // USB RX -> Rate Adapter
        {0x2001, 1, 0x2002, 2},  // Rate Adapter -> Encoder
        {0x2002, 1, 0x2003, 2},  // Encoder -> Shared Mem
    };
};
```

### USB Audio Module

USB Audio Module 是 AudioReach 中专门处理 USB 音频的模块，运行在 ADSP 上。

**Module ID：**
- `MODULE_ID_USB_AUDIO_TX`: 0x0700104A (Playback)
- `MODULE_ID_USB_AUDIO_RX`: 0x0700104B (Capture)

**配置参数：**

```c
struct usb_audio_cfg {
    uint32_t usb_token;           // USB 设备标识
    uint32_t svc_interval;        // 服务间隔（微帧）
    uint32_t sample_rate;         // 采样率
    uint16_t num_channels;        // 通道数
    uint16_t bit_width;           // 位宽
    uint8_t  data_path_id;        // 数据路径 ID
    uint8_t  usb_audio_fmt;       // USB 音频格式
    uint8_t  usb_audio_subslot_size; // 子槽大小
};

// 配置 USB Audio Module
struct apm_module_param_data param = {
    .module_instance_id = USB_AUDIO_MODULE_IID,
    .param_id = PARAM_ID_USB_AUDIO_DEV_PARAMS,
    .param_size = sizeof(struct usb_audio_cfg),
};
memcpy(param.param_data, &usb_cfg, sizeof(usb_cfg));
audioreach_send_module_param(graph, &param);
```

### Rate Adapter Module

Rate Adapter 用于处理 USB 音频的时钟域转换，因为 USB 时钟和系统时钟可能不同步。

**功能：**
- 时钟域转换（CDC - Clock Domain Conversion）
- 采样率微调
- 缓冲区管理
- 防止 underrun/overrun

**配置：**

```c
struct rate_adapter_cfg {
    uint32_t sample_rate;
    uint32_t num_channels;
    uint32_t bit_width;
    uint32_t buffer_size;      // 缓冲区大小（样本数）
    uint32_t drift_threshold;  // 漂移阈值
};
```

## 内核驱动实现

### Q6 USB Offload Driver

Q6 USB Offload Driver (q6usb) 是连接 ALSA 和 AudioReach 的桥梁。

**主要功能：**
1. 注册 ALSA PCM 设备
2. 管理 USB 设备连接/断开
3. 配置 AudioReach Graph
4. 处理数据传输

**关键数据结构：**

```c
struct q6usb_offload {
    struct snd_soc_component *component;
    struct q6apm_graph *graph;
    struct usb_device *udev;
    struct usb_interface *intf;
    
    int card_num;
    int pcm_dev_num;
    
    bool offload_enabled;
    bool graph_opened;
    
    struct usb_audio_stream_info stream_info;
};

struct usb_audio_stream_info {
    u32 usb_token;
    u8  direction;  // SNDRV_PCM_STREAM_PLAYBACK/CAPTURE
    u8  pcm_format;
    u32 sample_rate;
    u16 num_channels;
    u16 period_size;
    u16 num_periods;
};
```

**PCM 操作实现：**

```c
static struct snd_pcm_ops q6usb_pcm_ops = {
    .open = q6usb_pcm_open,
    .close = q6usb_pcm_close,
    .hw_params = q6usb_pcm_hw_params,
    .hw_free = q6usb_pcm_hw_free,
    .prepare = q6usb_pcm_prepare,
    .trigger = q6usb_pcm_trigger,
    .pointer = q6usb_pcm_pointer,
};

static int q6usb_pcm_open(struct snd_pcm_substream *substream)
{
    struct q6usb_offload *priv = snd_soc_component_get_drvdata(component);
    struct q6apm_graph *graph;
    int ret;
    
    // 创建 AudioReach Graph
    graph = q6apm_graph_open(priv->dev, NULL, priv->dev, substream);
    if (IS_ERR(graph))
        return PTR_ERR(graph);
    
    priv->graph = graph;
    priv->graph_opened = true;
    
    return 0;
}

static int q6usb_pcm_hw_params(struct snd_pcm_substream *substream,
                               struct snd_pcm_hw_params *params)
{
    struct q6usb_offload *priv = snd_soc_component_get_drvdata(component);
    struct usb_audio_cfg usb_cfg;
    int ret;
    
    // 配置 USB Audio Module
    usb_cfg.usb_token = priv->stream_info.usb_token;
    usb_cfg.sample_rate = params_rate(params);
    usb_cfg.num_channels = params_channels(params);
    usb_cfg.bit_width = params_width(params);
    
    ret = audioreach_set_usb_audio_cfg(priv->graph, &usb_cfg);
    if (ret)
        return ret;
    
    // 准备 Graph
    ret = q6apm_graph_prepare(priv->graph);
    if (ret)
        return ret;
    
    return 0;
}

static int q6usb_pcm_trigger(struct snd_pcm_substream *substream, int cmd)
{
    struct q6usb_offload *priv = snd_soc_component_get_drvdata(component);
    int ret = 0;
    
    switch (cmd) {
    case SNDRV_PCM_TRIGGER_START:
    case SNDRV_PCM_TRIGGER_RESUME:
        ret = q6apm_graph_start(priv->graph);
        break;
    case SNDRV_PCM_TRIGGER_STOP:
    case SNDRV_PCM_TRIGGER_SUSPEND:
        ret = q6apm_graph_stop(priv->graph);
        break;
    default:
        ret = -EINVAL;
        break;
    }
    
    return ret;
}
```

### USB 设备管理

**USB 设备连接处理：**

```c
static int q6usb_alsa_connection_cb(struct usb_interface *intf,
                                    enum usb_audio_device_speed speed)
{
    struct q6usb_offload *priv = usb_get_intfdata(intf);
    struct usb_device *udev = interface_to_usbdev(intf);
    u32 usb_token;
    int ret;
    
    // 生成 USB token
    usb_token = (udev->bus->busnum << 16) | udev->devnum;
    
    // 通知 ADSP USB 设备连接
    ret = q6usb_notify_connection(priv, usb_token, true);
    if (ret) {
        dev_err(&intf->dev, "Failed to notify USB connection\n");
        return ret;
    }
    
    priv->usb_token = usb_token;
    priv->offload_enabled = true;
    
    return 0;
}

static int q6usb_alsa_disconnection_cb(struct usb_interface *intf)
{
    struct q6usb_offload *priv = usb_get_intfdata(intf);
    
    // 通知 ADSP USB 设备断开
    q6usb_notify_connection(priv, priv->usb_token, false);
    
    priv->offload_enabled = false;
    priv->usb_token = 0;
    
    return 0;
}
```

## USB Audio Class 2.0 支持

### 音频格式支持

USB Audio Offload 支持 USB Audio Class 2.0 定义的多种音频格式：

**PCM 格式：**
- PCM 16-bit
- PCM 24-bit
- PCM 32-bit

**采样率：**
- 8 kHz
- 16 kHz
- 44.1 kHz
- 48 kHz
- 96 kHz
- 192 kHz

**通道配置：**
- Mono (1 channel)
- Stereo (2 channels)
- Multi-channel (up to 8 channels)

### USB 描述符解析

```c
struct usb_audio_format_type_i_descriptor {
    __u8  bLength;
    __u8  bDescriptorType;
    __u8  bDescriptorSubtype;
    __u8  bFormatType;
    __u8  bNrChannels;
    __u8  bSubframeSize;
    __u8  bBitResolution;
    __u8  bSamFreqType;
    __u8  tSamFreq[][3];
} __packed;

static int parse_usb_audio_format(struct usb_interface *intf,
                                  struct usb_audio_stream_info *info)
{
    struct usb_host_interface *alts = intf->cur_altsetting;
    struct usb_audio_format_type_i_descriptor *fmt;
    int i;
    
    fmt = find_format_descriptor(alts);
    if (!fmt)
        return -EINVAL;
    
    info->num_channels = fmt->bNrChannels;
    info->bit_width = fmt->bBitResolution;
    
    // 解析支持的采样率
    if (fmt->bSamFreqType == 0) {
        // 连续采样率范围
        info->min_rate = (fmt->tSamFreq[0][2] << 16) |
                         (fmt->tSamFreq[0][1] << 8) |
                         fmt->tSamFreq[0][0];
        info->max_rate = (fmt->tSamFreq[1][2] << 16) |
                         (fmt->tSamFreq[1][1] << 8) |
                         fmt->tSamFreq[1][0];
    } else {
        // 离散采样率
        for (i = 0; i < fmt->bSamFreqType; i++) {
            u32 rate = (fmt->tSamFreq[i][2] << 16) |
                       (fmt->tSamFreq[i][1] << 8) |
                       fmt->tSamFreq[i][0];
            info->supported_rates[i] = rate;
        }
    }
    
    return 0;
}
```

## GPR 通信协议

### GPR Packet 结构

GPR (Generic Packet Router) 是 AP 和 ADSP 之间的通信协议。

```c
struct gpr_pkt {
    struct gpr_hdr hdr;
    uint8_t payload[];
};

struct gpr_hdr {
    uint32_t version:4;
    uint32_t hdr_size:4;
    uint32_t pkt_size:24;
    uint32_t src_domain:8;
    uint32_t dst_domain:8;
    uint32_t src_port:16;
    uint32_t dst_port:16;
    uint32_t token;
    uint32_t opcode;
};
```

### USB Offload 相关命令

**打开 Graph：**

```c
#define APM_CMD_GRAPH_OPEN  0x01001000

struct apm_cmd_graph_open {
    struct apm_module_param_data param_data;
    uint32_t num_sub_graphs;
    struct apm_sub_graph_cfg sub_graphs[];
};

// 发送命令
struct gpr_pkt *pkt;
pkt = audioreach_alloc_cmd_pkt(sizeof(struct apm_cmd_graph_open) + 
                               graph_size, APM_CMD_GRAPH_OPEN, 
                               src_port, dst_port);
// 填充 Graph 配置
ret = gpr_send_pkt(gpr, pkt);
```

**配置 USB Module：**

```c
#define APM_CMD_SET_CFG  0x01001001
#define PARAM_ID_USB_AUDIO_DEV_PARAMS  0x08001154

struct apm_cmd_set_cfg {
    struct apm_module_param_data param_data;
    struct usb_audio_cfg usb_cfg;
};

// 发送配置
ret = audioreach_send_module_param(graph, 
                                   MODULE_ID_USB_AUDIO_TX,
                                   PARAM_ID_USB_AUDIO_DEV_PARAMS,
                                   &usb_cfg, sizeof(usb_cfg));
```

**启动/停止 Graph：**

```c
#define APM_CMD_GRAPH_START  0x01001002
#define APM_CMD_GRAPH_STOP   0x01001003

struct apm_cmd_graph_start {
    uint32_t graph_id;
};

// 启动
ret = q6apm_send_cmd_sync(graph, APM_CMD_GRAPH_START);

// 停止
ret = q6apm_send_cmd_sync(graph, APM_CMD_GRAPH_STOP);
```

### 数据传输

**写入共享内存：**

```c
#define DATA_CMD_WR_SH_MEM_EP_DATA_BUFFER  0x04001000

struct data_cmd_wr_sh_mem_ep {
    uint32_t buf_addr_lsw;
    uint32_t buf_addr_msw;
    uint32_t mem_map_handle;
    uint32_t buf_size;
    uint32_t timestamp_lsw;
    uint32_t timestamp_msw;
    uint32_t flags;
};

// 发送音频数据
ret = q6apm_write(graph, buf_addr, buf_size);
```

**读取共享内存：**

```c
#define DATA_CMD_RD_SH_MEM_EP_DATA_BUFFER  0x04001001

struct data_cmd_rd_sh_mem_ep {
    uint32_t buf_addr_lsw;
    uint32_t buf_addr_msw;
    uint32_t mem_map_handle;
    uint32_t buf_size;
};

// 读取音频数据
ret = q6apm_read(graph, buf_addr, buf_size);
```

## 性能优化

### 延迟优化

**降低延迟的方法：**

1. **减小 Period Size**
```c
// 设置较小的 period size
snd_pcm_hw_params_set_period_size(pcm, params, 240, 0);  // 5ms @ 48kHz
```

2. **使用低延迟 Container**
```c
struct apm_container_cfg {
    .container_id = LOW_LATENCY_CONTAINER_ID,
    .capability_id = APM_CONTAINER_CAP_ID_PP,
    .stack_size = 8192,
    .proc_domain = APM_PROC_DOMAIN_ID_ADSP,
};
```

3. **优化 USB Service Interval**
```c
// USB 2.0: 1ms (8 microframes)
// USB 3.0: 125us (1 microframe)
usb_cfg.svc_interval = 1;  // 最小服务间隔
```

### 功耗优化

**降低功耗的策略：**

1. **使用 Offload 模式**
   - AP 可以进入深度睡眠
   - 节省 50-100mW 功耗

2. **动态调整 ADSP 频率**
```c
// 根据音频负载调整 ADSP 时钟
if (sample_rate <= 48000 && channels <= 2)
    adsp_clk = ADSP_CLK_LOW;
else if (sample_rate <= 96000)
    adsp_clk = ADSP_CLK_MED;
else
    adsp_clk = ADSP_CLK_HIGH;
```

3. **优化缓冲区大小**
```c
// 较大的缓冲区可以减少唤醒频率
snd_pcm_hw_params_set_buffer_size(pcm, params, 4800);  // 100ms @ 48kHz
```

### 内存优化

**共享内存管理：**

```c
struct q6apm_shared_mem {
    dma_addr_t phys_addr;
    void *virt_addr;
    size_t size;
    uint32_t mem_map_handle;
};

static int q6apm_map_memory(struct q6apm_graph *graph,
                            struct q6apm_shared_mem *mem)
{
    struct apm_cmd_shared_mem_map_regions cmd;
    int ret;
    
    // 分配 DMA 内存
    mem->virt_addr = dma_alloc_coherent(graph->dev, mem->size,
                                        &mem->phys_addr, GFP_KERNEL);
    if (!mem->virt_addr)
        return -ENOMEM;
    
    // 映射到 ADSP
    cmd.mem_pool_id = APM_MEMORY_MAP_SHMEM8_4K_POOL;
    cmd.num_regions = 1;
    cmd.regions[0].shm_addr_lsw = lower_32_bits(mem->phys_addr);
    cmd.regions[0].shm_addr_msw = upper_32_bits(mem->phys_addr);
    cmd.regions[0].mem_size_bytes = mem->size;
    
    ret = audioreach_send_cmd_sync(graph, APM_CMD_SHARED_MEM_MAP_REGIONS,
                                   &cmd, sizeof(cmd));
    if (ret)
        goto err_free;
    
    mem->mem_map_handle = cmd.mem_map_handle;
    return 0;

err_free:
    dma_free_coherent(graph->dev, mem->size, mem->virt_addr, mem->phys_addr);
    return ret;
}
```

## 调试和故障排除

### 常见问题

**1. USB 设备无法识别**

```bash
# 检查 USB 设备
lsusb -v | grep -A 20 "Audio"

# 检查内核日志
dmesg | grep -i usb

# 检查 ALSA 设备
cat /proc/asound/cards
```

**2. Offload 未启用**

```bash
# 检查 q6usb 驱动是否加载
lsmod | grep q6usb

# 检查 AudioReach 服务
ps -ef | grep audioserver

# 启用调试日志
echo 'module q6usb +p' > /sys/kernel/debug/dynamic_debug/control
```

**3. 音频断续或爆音**

可能原因：
- Buffer underrun/overrun
- USB 带宽不足
- 时钟同步问题

解决方法：
```c
// 增大缓冲区
snd_pcm_hw_params_set_buffer_size(pcm, params, 9600);  // 200ms

// 调整 period size
snd_pcm_hw_params_set_period_size(pcm, params, 480, 0);  // 10ms
```

**4. 高延迟**

```bash
# 测量实际延迟
adb shell "tinycap /dev/null -D 0 -d 0 -c 2 -r 48000 -b 16 -p 240 -n 4"

# 优化配置
# 减小 period size 和 buffer size
```

### 调试工具

**1. GPR Tracer**

```bash
# 启用 GPR 跟踪
echo 1 > /sys/kernel/debug/gpr/trace_enable

# 查看 GPR 消息
cat /sys/kernel/debug/gpr/trace

# 过滤 USB 相关消息
cat /sys/kernel/debug/gpr/trace | grep USB
```

**2. AudioReach Graph Dump**

```bash
# Dump Graph 配置
cat /sys/kernel/debug/audioreach/graph_info

# Dump Module 状态
cat /sys/kernel/debug/audioreach/module_info
```

**3. USB Audio 统计**

```bash
# 查看 USB 音频统计
cat /proc/asound/card0/stream0

# 查看 USB 带宽使用
cat /sys/kernel/debug/usb/devices | grep -A 10 "Audio"
```

## 实际应用场景

### 场景 1：USB DAC 音乐播放

**需求：**
- 高保真音乐播放
- 低功耗长时间播放
- 支持高采样率（96kHz/192kHz）

**配置：**

```c
struct snd_pcm_hw_params params = {
    .sample_rate = 192000,
    .channels = 2,
    .format = SND_PCM_FORMAT_S24_LE,
    .period_size = 960,      // 5ms @ 192kHz
    .buffer_size = 19200,    // 100ms
};

// 启用 Offload
snd_pcm_hw_params_set_offload(pcm, params, true);
```

**预期效果：**
- CPU 占用率 < 1%
- 功耗节省 ~80mW
- 延迟 < 20ms
- AP 可进入深度睡眠

### 场景 2：USB 麦克风录音

**需求：**
- 实时语音录音
- 低延迟
- 低功耗

**配置：**

```c
struct snd_pcm_hw_params params = {
    .sample_rate = 48000,
    .channels = 1,
    .format = SND_PCM_FORMAT_S16_LE,
    .period_size = 240,      // 5ms @ 48kHz
    .buffer_size = 2400,     // 50ms
};

// 启用 Offload
snd_pcm_hw_params_set_offload(pcm, params, true);
```

**预期效果：**
- 延迟 < 15ms
- CPU 占用率 < 1%
- 功耗节省 ~50mW

### 场景 3：USB 耳机通话

**需求：**
- 双向音频（播放 + 录音）
- 超低延迟
- 回声消除

**配置：**

```c
// Playback
struct snd_pcm_hw_params playback_params = {
    .sample_rate = 48000,
    .channels = 2,
    .format = SND_PCM_FORMAT_S16_LE,
    .period_size = 240,      // 5ms
    .buffer_size = 960,      // 20ms
};

// Capture
struct snd_pcm_hw_params capture_params = {
    .sample_rate = 48000,
    .channels = 1,
    .format = SND_PCM_FORMAT_S16_LE,
    .period_size = 240,      // 5ms
    .buffer_size = 960,      // 20ms
};

// 启用回声消除
audioreach_enable_module(graph, MODULE_ID_ECHO_CANCELLER);
```

**预期效果：**
- 端到端延迟 < 30ms
- 回声消除效果良好
- 功耗优化

## 未来发展方向

### 1. 支持更多 USB Audio 特性

- USB Audio Class 3.0
- 高分辨率音频（DSD、MQA）
- 多设备同时 Offload
- USB MIDI Offload

### 2. 性能优化

- 进一步降低延迟（< 5ms）
- 更低功耗（< 10mW）
- 支持更高采样率（384kHz、768kHz）
- 硬件加速音频处理

### 3. 功能增强

- 动态 Graph 重配置
- 热插拔优化
- 更好的错误恢复
- 多路音频混音

### 4. 生态系统

- 标准化 HAL 接口
- 更好的开发者工具
- 性能分析工具
- 自动化测试框架

## 总结

USB Audio Offload 技术通过将 USB 音频处理从 AP 卸载到 ADSP，实现了：

1. **低功耗**：AP 可以进入深度睡眠，节省 50-100mW 功耗
2. **低延迟**：直接 DMA 传输，延迟降低到 10-30ms
3. **低 CPU 占用**：CPU 占用率从 5-15% 降低到 < 1%
4. **高音质**：支持高采样率和多通道音频

在 Qualcomm 平台上，USB Audio Offload 与 AudioReach 框架深度集成，提供了完整的硬件加速音频解决方案。通过合理的配置和优化，可以在各种应用场景中获得出色的音频体验。

## 参考资料

1. USB Audio Class 2.0 Specification
2. Qualcomm AudioReach Documentation
3. Linux ALSA USB Audio Driver
4. Android Audio HAL Documentation
5. GPR Protocol Specification
