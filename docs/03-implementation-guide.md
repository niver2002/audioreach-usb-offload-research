# AudioReach USB Audio Offload 实现指南

## 目录

1. [开发环境搭建](#开发环境搭建)
2. [内核驱动开发](#内核驱动开发)
3. [用户空间实现](#用户空间实现)
4. [AudioReach Graph 配置](#audioreach-graph-配置)
5. [测试和验证](#测试和验证)
6. [性能调优](#性能调优)
7. [常见问题解决](#常见问题解决)

## 开发环境搭建

### 硬件要求

**必需硬件：**
- Qualcomm 平台开发板（支持 AudioReach）
  - SM8450 (Snapdragon 8 Gen 1) 或更新
  - SM8550 (Snapdragon 8 Gen 2)
  - SM8650 (Snapdragon 8 Gen 3)
- USB Type-C 接口
- USB Audio 设备（DAC、耳机、麦克风等）

**推荐硬件：**
- 逻辑分析仪（用于 USB 协议分析）
- 示波器（用于音频信号分析）
- USB 协议分析仪

### 软件环境

**操作系统：**
- Linux Kernel 5.15+ 或 6.1+
- Android 13+ (AOSP)

**开发工具：**

```bash
# 安装交叉编译工具链
sudo apt-get install gcc-aarch64-linux-gnu
sudo apt-get install build-essential

# 安装 Android 开发工具
sudo apt-get install adb fastboot

# 安装音频工具
sudo apt-get install alsa-utils
sudo apt-get install pulseaudio-utils

# 安装调试工具
sudo apt-get install gdb-multiarch
sudo apt-get install trace-cmd
```

**内核配置：**

```bash
# 启用必要的内核选项
CONFIG_SND_SOC_QCOM=y
CONFIG_SND_SOC_QDSP6=y
CONFIG_SND_SOC_QDSP6_APM=y
CONFIG_SND_SOC_QDSP6_USB=y
CONFIG_USB_AUDIO=y
CONFIG_USB_AUDIO_USE_XHCI=y
CONFIG_QCOM_GPR=y
CONFIG_QCOM_GLINK=y
```

### 源码获取

```bash
# 克隆 Linux 内核
git clone https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git
cd linux
git checkout v6.1

# 相关驱动路径
# sound/soc/qcom/qdsp6/          - AudioReach 驱动
# sound/usb/                     - USB Audio 驱动
# drivers/soc/qcom/gpr.c         - GPR 驱动

# 克隆 AOSP (可选)
repo init -u https://android.googlesource.com/platform/manifest -b android-14.0.0_r1
repo sync
```

## 内核驱动开发

### Q6 USB Offload 驱动结构

创建新的驱动文件：`sound/soc/qcom/qdsp6/q6usb.c`

```c
// SPDX-License-Identifier: GPL-2.0
// Copyright (c) 2024, Qualcomm Innovation Center, Inc. All rights reserved.

#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/usb.h>
#include <sound/soc.h>
#include <sound/pcm.h>
#include <sound/pcm_params.h>
#include "q6apm.h"

#define Q6USB_DRIVER_NAME "q6usb"

struct q6usb_port_data {
    struct q6apm_graph *graph;
    struct device *dev;
    
    u32 usb_token;
    bool offload_enabled;
    
    struct usb_device *udev;
    struct usb_interface *intf;
    
    /* Stream info */
    u32 sample_rate;
    u16 num_channels;
    u16 bit_width;
    u8 direction;
    
    /* Synchronization */
    struct mutex lock;
    struct completion cmd_done;
};

/* USB device notification */
static int q6usb_notify_connection(struct q6usb_port_data *data,
                                   u32 usb_token, bool connected)
{
    struct apm_module_param_data param;
    struct usb_audio_dev_conn_info conn_info;
    int ret;
    
    conn_info.usb_token = usb_token;
    conn_info.connected = connected;
    
    param.module_instance_id = USB_AUDIO_MODULE_IID;
    param.param_id = PARAM_ID_USB_AUDIO_DEV_CONN;
    param.param_size = sizeof(conn_info);
    
    ret = q6apm_send_param(data->graph, &param, &conn_info);
    if (ret)
        dev_err(data->dev, "Failed to notify USB connection: %d\n", ret);
    
    return ret;
}

/* PCM operations */
static int q6usb_pcm_open(struct snd_soc_component *component,
                          struct snd_pcm_substream *substream)
{
    struct q6usb_port_data *data = snd_soc_component_get_drvdata(component);
    struct q6apm_graph *graph;
    int ret;
    
    mutex_lock(&data->lock);
    
    /* Create AudioReach graph */
    graph = q6apm_graph_open(data->dev, NULL, data->dev, substream);
    if (IS_ERR(graph)) {
        ret = PTR_ERR(graph);
        dev_err(data->dev, "Failed to open graph: %d\n", ret);
        goto unlock;
    }
    
    data->graph = graph;
    data->direction = substream->stream;
    ret = 0;
    
unlock:
    mutex_unlock(&data->lock);
    return ret;
}

static int q6usb_pcm_close(struct snd_soc_component *component,
                           struct snd_pcm_substream *substream)
{
    struct q6usb_port_data *data = snd_soc_component_get_drvdata(component);
    
    mutex_lock(&data->lock);
    
    if (data->graph) {
        q6apm_graph_close(data->graph);
        data->graph = NULL;
    }
    
    mutex_unlock(&data->lock);
    return 0;
}

static int q6usb_pcm_hw_params(struct snd_soc_component *component,
                               struct snd_pcm_substream *substream,
                               struct snd_pcm_hw_params *params)
{
    struct q6usb_port_data *data = snd_soc_component_get_drvdata(component);
    struct usb_audio_cfg usb_cfg;
    int ret;
    
    mutex_lock(&data->lock);
    
    /* Store stream parameters */
    data->sample_rate = params_rate(params);
    data->num_channels = params_channels(params);
    data->bit_width = params_width(params);
    
    /* Configure USB Audio Module */
    memset(&usb_cfg, 0, sizeof(usb_cfg));
    usb_cfg.usb_token = data->usb_token;
    usb_cfg.sample_rate = data->sample_rate;
    usb_cfg.num_channels = data->num_channels;
    usb_cfg.bit_width = data->bit_width;
    usb_cfg.svc_interval = 1;  /* Minimum service interval */
    
    ret = q6apm_set_usb_audio_cfg(data->graph, &usb_cfg);
    if (ret) {
        dev_err(data->dev, "Failed to set USB audio config: %d\n", ret);
        goto unlock;
    }
    
    /* Prepare graph */
    ret = q6apm_graph_prepare(data->graph);
    if (ret)
        dev_err(data->dev, "Failed to prepare graph: %d\n", ret);
    
unlock:
    mutex_unlock(&data->lock);
    return ret;
}

static int q6usb_pcm_trigger(struct snd_soc_component *component,
                             struct snd_pcm_substream *substream, int cmd)
{
    struct q6usb_port_data *data = snd_soc_component_get_drvdata(component);
    int ret = 0;
    
    mutex_lock(&data->lock);
    
    switch (cmd) {
    case SNDRV_PCM_TRIGGER_START:
    case SNDRV_PCM_TRIGGER_RESUME:
        ret = q6apm_graph_start(data->graph);
        break;
    case SNDRV_PCM_TRIGGER_STOP:
    case SNDRV_PCM_TRIGGER_SUSPEND:
        ret = q6apm_graph_stop(data->graph);
        break;
    default:
        ret = -EINVAL;
        break;
    }
    
    mutex_unlock(&data->lock);
    return ret;
}

static snd_pcm_uframes_t q6usb_pcm_pointer(struct snd_soc_component *component,
                                           struct snd_pcm_substream *substream)
{
    struct q6usb_port_data *data = snd_soc_component_get_drvdata(component);
    snd_pcm_uframes_t pos;
    
    mutex_lock(&data->lock);
    pos = q6apm_get_position(data->graph);
    mutex_unlock(&data->lock);
    
    return pos;
}

static const struct snd_soc_component_driver q6usb_component = {
    .name = Q6USB_DRIVER_NAME,
    .open = q6usb_pcm_open,
    .close = q6usb_pcm_close,
    .hw_params = q6usb_pcm_hw_params,
    .trigger = q6usb_pcm_trigger,
    .pointer = q6usb_pcm_pointer,
};

## AudioReach Graph 配置

### Graph 定义文件

创建 USB Offload Graph 配置：


### 测试脚本

创建基本的测试脚本来验证 USB Offload 功能。

### 性能基准测试

使用 TinyALSA 工具进行性能测试：

```bash
# 测试播放延迟
tinycap /dev/null -D 0 -d 0 -c 2 -r 48000 -b 16 -p 240 -n 4

# 测试不同采样率
for rate in 44100 48000 96000 192000; do
    echo "Testing rate: $rate"
    speaker-test -D hw:0,0 -c 2 -r $rate -f S16_LE -t sine -l 1
done
```

## 性能调优

### 延迟优化策略

1. 减小 period size (120-240 frames)
2. 使用低延迟 ADSP container
3. 优化 USB service interval
4. 启用 DMA 直接传输

### 功耗优化策略

1. 增大缓冲区大小
2. 动态调整 ADSP 时钟频率
3. 使用 offload 模式让 AP 休眠
4. 优化唤醒频率

### 内存优化

使用共享内存池减少内存分配开销：

```c
struct q6apm_shared_mem_pool {
    void *base;
    size_t size;
    size_t used;
    struct list_head free_list;
};
```

## 常见问题解决

### 问题 1: 驱动加载失败

**症状：** modprobe q6usb 失败

**解决方法：**
```bash
# 检查依赖
lsmod | grep q6apm
lsmod | grep gpr

# 检查设备树
cat /proc/device-tree/soc/q6apm/q6usb/compatible

# 查看内核日志
dmesg | grep q6usb
```

### 问题 2: USB 设备无法识别

**症状：** lsusb 能看到设备，但无法使用 offload

**解决方法：**
```bash
# 检查 USB 音频类
lsusb -v -d xxxx:xxxx | grep -A 5 "Audio"

# 检查 ALSA 配置
cat /proc/asound/cards

# 重新加载驱动
rmmod q6usb
modprobe q6usb
```

### 问题 3: 音频断续

**症状：** 播放时有爆音或断续

**可能原因：**
- Buffer underrun
- USB 带宽不足
- ADSP 时钟过低

**解决方法：**
```bash
# 增大缓冲区
tinycap /dev/null -D 0 -d 0 -c 2 -r 48000 -b 16 -p 960 -n 8

# 检查 USB 带宽
cat /sys/kernel/debug/usb/devices

# 提高 ADSP 时钟
echo performance > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
```

### 问题 4: 高延迟

**症状：** 延迟超过 50ms

**解决方法：**
```bash
# 减小 period size
tinycap /dev/null -D 0 -d 0 -c 2 -r 48000 -b 16 -p 120 -n 2

# 检查 offload 是否启用
cat /sys/kernel/debug/q6usb/offload_status

# 优化 USB 配置
echo 1 > /sys/module/usbcore/parameters/usbfs_memory_mb
```

## 调试技巧

### 启用调试日志

```bash
# 内核动态调试
echo 'module q6usb +p' > /sys/kernel/debug/dynamic_debug/control
echo 'module q6apm +p' > /sys/kernel/debug/dynamic_debug/control
echo 'module gpr +p' > /sys/kernel/debug/dynamic_debug/control

# 查看日志
dmesg -w | grep -E 'q6usb|q6apm|gpr'
```

### GPR 消息跟踪

```bash
# 启用 GPR 跟踪
echo 1 > /sys/kernel/debug/gpr/trace_enable

# 查看消息
cat /sys/kernel/debug/gpr/trace

# 过滤 USB 相关消息
cat /sys/kernel/debug/gpr/trace | grep -i usb
```

### 性能分析

```bash
# CPU 使用率
top -p $(pidof audioserver)

# 中断统计
cat /proc/interrupts | grep -i usb

# 内存使用
cat /proc/meminfo | grep -i audio

# ADSP 状态
cat /sys/kernel/debug/remoteproc/remoteproc0/state
```

## 最佳实践

### 1. 初始化顺序

```
1. 加载 GPR 驱动
2. 加载 Q6APM 驱动
3. 加载 Q6USB 驱动
4. 连接 USB 设备
5. 配置音频参数
6. 启动播放/录音
```

### 2. 错误处理

```c
static int q6usb_error_handler(struct q6usb_port_data *data, int error)
{
    switch (error) {
    case -ETIMEDOUT:
        // 超时：重试
        return q6usb_retry_operation(data);
    case -ENODEV:
        // 设备断开：清理资源
        return q6usb_cleanup(data);
    case -ENOMEM:
        // 内存不足：释放缓存
        return q6usb_free_cache(data);
    default:
        return error;
    }
}
```

### 3. 资源管理

```c
static void q6usb_cleanup_resources(struct q6usb_port_data *data)
{
    // 停止 graph
    if (data->graph)
        q6apm_graph_stop(data->graph);
    
    // 释放共享内存
    if (data->shared_mem)
        q6apm_unmap_memory(data->shared_mem);
    
    // 关闭 graph
    if (data->graph)
        q6apm_graph_close(data->graph);
    
    // 清理状态
    data->offload_enabled = false;
    data->usb_token = 0;
}
```

## 总结

本实现指南涵盖了 AudioReach USB Audio Offload 的完整开发流程，包括：

1. 开发环境搭建
2. 内核驱动开发
3. 用户空间实现
4. AudioReach Graph 配置
5. 测试和验证
6. 性能调优
7. 问题排查

通过遵循本指南，开发者可以在 Qualcomm 平台上成功实现 USB Audio Offload 功能，获得低功耗、低延迟的音频体验。

## 参考资源

- Linux Kernel Documentation
- Qualcomm AudioReach SDK
- ALSA Project Documentation
- USB Audio Class Specification
- Android Audio HAL Documentation
