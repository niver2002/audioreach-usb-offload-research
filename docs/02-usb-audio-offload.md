# USB Audio Offload 技术文档

> **⚠️ 重要声明**
> 本文档中关于 USB Audio Offload 的内容存在技术错误。QCS6490 在 Linux 主线内核中使用 q6apm 架构，
> 该架构不支持 USB offload。详见 [AUDIOREACH_USB_OFFLOAD_FINDINGS.md](../AUDIOREACH_USB_OFFLOAD_FINDINGS.md)。


## 概述

USB Audio Offload 是一种将 USB 音频数据处理从应用处理器（AP）卸载到音频数字信号处理器（ADSP）的技术。该技术通过让 ADSP 直接处理 USB 音频数据流，显著降低了 AP 的功耗和处理负担。

## 架构组件

### 1. 用户空间组件
- **tinyalsa/ALSA 库**：提供音频设备访问接口
- **音频 HAL**：Android 音频硬件抽象层

### 2. 内核驱动组件
- **q6usb.c**：USB 音频卸载的核心驱动
- **q6afe-dai.c**：音频前端 DAI 驱动
- **xhci-sideband.c**：XHCI sideband 接口驱动

### 3. ADSP 组件
- **AudioReach**：ADSP 上的音频处理框架
- **QMI 服务**：处理 USB 音频卸载请求

## 工作流程

### 初始化阶段

1. **驱动加载**
   - q6usb 驱动注册为平台设备
   - 注册 QMI 消息处理器
   - 初始化 sideband 接口

2. **设备枚举**
   - USB 音频设备插入
   - 内核枚举 USB 音频接口
   - 创建 ALSA PCM 设备

### 音频流启动

1. **用户空间请求**
   ```c
   // 打开 PCM 设备
   pcm = pcm_open(card, device, PCM_OUT, &config);
   ```

2. **内核处理**
   - q6afe_dai_prepare() 被调用
   - 准备 AFE 端口配置
   - 分配 DMA 缓冲区

3. **QMI 通信**
   ```c
   // 发送 QMI 请求到 ADSP
   ret = qmi_send_request(svc->uaudio_svc_hdl,
                          &req_desc, &req,
                          &resp_desc, &resp);
   ```

4. **ADSP 配置**
   - ADSP 接收 QMI 请求
   - 配置 AudioReach 图
   - 建立与 USB 控制器的连接

### 数据传输

1. **DMA 配置**
   - ADSP 直接访问 USB 控制器的 DMA 缓冲区
   - 配置传输描述符

2. **数据流**
   ```
   音频源 → ADSP → USB 控制器 → USB 设备
   ```

3. **同步机制**
   - 使用 USB SOF（Start of Frame）进行同步
   - ADSP 管理缓冲区填充

### 音频流停止

1. **用户空间关闭**
   ```c
   pcm_close(pcm);
   ```

2. **内核清理**
   - q6afe_dai_shutdown() 被调用
   - 释放 DMA 资源

3. **ADSP 清理**
   - 通过 QMI 通知 ADSP
   - ADSP 断开 USB 连接
   - 释放 AudioReach 资源

## 关键数据结构

### USB 音频设备信息
```c
struct uaudio_dev {
    u8 card_num;
    u8 pcm_dev_num;
    u32 sample_rate;
    u8 num_channels;
    u32 bit_rate;
};
```

### QMI 请求消息
```c
struct qmi_uaudio_stream_req_msg_v01 {
    u8 enable;
    u32 usb_token;
    u8 audio_format;
    u32 number_of_ch;
    u32 bit_rate;
    struct uaudio_dev dev_info;
};
```

### AFE 端口配置
```c
struct afe_usb_audio_cfg {
    u16 cfg_minor_version;
    u16 sample_rate;
    u16 num_channels;
    u16 bit_width;
    u32 data_path_delay;
};
```

## 性能优化

### 功耗优化
- AP 可以进入更深的睡眠状态
- ADSP 专门优化用于音频处理
- 减少 AP-ADSP 之间的数据传输

### 延迟优化
- 直接 DMA 传输减少数据拷贝
- ADSP 实时处理音频数据
- 硬件同步机制

## 错误处理

### USB 设备断开
1. USB 驱动检测到设备断开
2. 通知 q6usb 驱动
3. q6usb 通过 QMI 通知 ADSP
4. ADSP 清理资源并停止音频流

### QMI 通信失败
1. 检测 QMI 超时或错误
2. 重试机制（最多 3 次）
3. 如果失败，回退到非卸载模式

### DMA 错误
1. ADSP 检测 DMA 传输错误
2. 通过 QMI 通知内核
3. 内核重新配置 DMA
4. 如果持续失败，停止音频流

## 调试支持

### 内核日志
```bash
# 启用 q6usb 调试日志
echo 8 > /proc/sys/kernel/printk
echo "file q6usb.c +p" > /sys/kernel/debug/dynamic_debug/control
```

### QMI 跟踪
```bash
# 启用 QMI 跟踪
echo 1 > /sys/kernel/debug/qmi/trace
```

### ADSP 日志
```bash
# 查看 ADSP 日志
cat /sys/kernel/debug/remoteproc/remoteproc0/trace0
```

## 限制和约束

1. **USB 版本**：仅支持 USB 2.0 和 USB 3.0
2. **音频格式**：支持 PCM，不支持压缩格式
3. **采样率**：8kHz - 384kHz
4. **通道数**：1-8 通道
5. **位深度**：16/24/32 位

## 未来改进方向

1. 支持更多音频格式（如 DSD）
2. 改进功耗管理
3. 增强错误恢复机制
4. 支持多个 USB 音频设备同时卸载
