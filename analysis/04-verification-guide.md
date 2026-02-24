# QCS6490 USB Audio Offload 实机验证指南

> 在 Radxa Q6A (QCS6490) 上验证 USB offload 可行性的具体步骤

## 前提条件

- Radxa Q6A 开发板，运行上游 Linux 内核 (≥6.8)
- 一个 USB Audio Class 2.0 设备（USB DAC 或 USB 耳机）
- 串口或 SSH 访问
- 内核源码（用于可能的补丁编译）

## 阶段 1：环境探测

### 1.1 确认内核版本和配置

```bash
uname -r
# 确认 >= 6.8

# 检查关键内核配置
zcat /proc/config.gz | grep -E "SND_SOC_QCOM|SND_USB|XHCI_SIDEBAND|QMI"
# 需要看到：
# CONFIG_SND_SOC_QCOM=m (或 y)
# CONFIG_SND_SOC_QDSP6=m
# CONFIG_SND_SOC_QDSP6_AFE=m        ← 关键
# CONFIG_SND_SOC_QDSP6_USB=m        ← 关键
# CONFIG_SND_USB_AUDIO=m
# CONFIG_SND_USB_AUDIO_QMI=m        ← 关键
# CONFIG_USB_XHCI_SIDEBAND=m        ← 关键
```

如果缺少任何关键配置，需要重新编译内核。

### 1.2 检查 ADSP 固件

```bash
# 固件文件
ls -la /lib/firmware/qcom/qcs6490/
# 应该看到 adsp.mbn 或类似文件

# ADSP remoteproc 状态
cat /sys/class/remoteproc/remoteproc*/name
cat /sys/class/remoteproc/remoteproc*/state
# 应该看到 adsp 处于 "running" 状态

# 固件中搜索 AFE 相关字符串
strings /lib/firmware/qcom/qcs6490/adsp*.mbn 2>/dev/null | grep -i "afe" | head -10
strings /lib/firmware/qcom/qcs6490/adsp*.mbn 2>/dev/null | grep -i "usb" | head -10
```

### 1.3 检查协议栈状态

```bash
# APR 设备（Legacy 路径）
ls -la /sys/bus/apr/devices/ 2>/dev/null
# 如果目录存在且有设备，说明 APR 协议栈活跃

# GPR 设备（AudioReach 路径）
ls -la /sys/bus/gpr/devices/ 2>/dev/null

# 两者可以共存
```

### 1.4 检查已加载的音频模块

```bash
lsmod | grep -E "snd|q6|usb|audio"
# 关注：
# snd_soc_q6_afe       — AFE 核心
# snd_soc_q6_afe_dai   — AFE DAI
# snd_q6usb            — USB offload ASoC
# snd_usb_audio        — USB Audio class driver
# qc_audio_offload     — USB 侧 offload driver
# snd_soc_usb          — SoC-USB 框架
```

## 阶段 2：AFE Service 验证

这是最关键的验证步骤。

### 2.1 尝试加载 AFE 模块

```bash
# 如果 AFE 模块没有自动加载
modprobe snd_soc_q6_afe
dmesg | tail -20

# 检查 AFE 是否成功注册
# 成功标志：没有错误信息，APR 设备出现
ls /sys/bus/apr/devices/

# 失败标志：
# "apr: Unable to find service" — ADSP 没有 AFE service
# "apr: timeout" — APR 通信超时
```

### 2.2 检查 AFE 端口

```bash
# 如果 AFE 加载成功
modprobe snd_soc_q6_afe_dai
dmesg | tail -10

# 检查注册的 DAI
cat /proc/asound/cards
aplay -l
# 看是否有 USB 相关的 PCM 设备
```

## 阶段 3：USB Offload 驱动加载

### 3.1 加载 USB 侧驱动

```bash
# 加载 xHCI sideband 支持
modprobe xhci_sideband 2>/dev/null

# 加载 SoC-USB 框架
modprobe snd_soc_usb

# 加载 USB offload driver
modprobe snd_usb_qcom_offload
dmesg | tail -20

# 检查 QMI service 是否注册
dmesg | grep -i "qmi\|uaudio"
```

### 3.2 插入 USB 音频设备

```bash
# 插入 USB DAC/耳机
dmesg | tail -30
# 关注：
# "usb X-Y: new high-speed USB device" — USB 枚举
# "snd-usb-audio: ..." — USB Audio 识别
# "qc_audio_offload: ..." — offload driver 响应
# "snd_soc_usb: connect" — SoC-USB 连接通知

# 检查 USB 音频设备
cat /proc/asound/cards
aplay -l
```

## 阶段 4：功能测试

### 4.1 基本播放测试（非 offload）

```bash
# 先确认 USB 音频设备正常工作（CPU 路径）
aplay -D hw:X,0 -f S16_LE -r 48000 -c 2 /path/to/test.wav
# X = USB 音频设备的 card number
```

### 4.2 Offload 路径测试

```bash
# 检查是否有 offload PCM 设备
# offload 设备通常是一个额外的 PCM device
aplay -l | grep -i "usb\|offload"

# 如果有 offload PCM 设备，尝试播放
aplay -D hw:Y,0 -f S16_LE -r 48000 -c 2 /path/to/test.wav
# Y = offload PCM 设备的 card number

# 监控 CPU 使用率
# offload 模式下 CPU 使用率应该显著低于 CPU 路径
top -d 1
```

### 4.3 QMI 通信验证

```bash
# 检查 QMI 通信是否发生
dmesg | grep -i "uaudio_stream\|qmi"
# 成功标志：看到 stream enable/disable 消息
# 失败标志：QMI timeout 或 no client
```

## 阶段 5：故障排除

### 问题 1：AFE 模块加载失败

```
可能原因：
1. ADSP 固件不包含 AFE service
2. APR 协议栈未初始化
3. 内核配置缺失

排查：
$ dmesg | grep -E "apr|afe|gpr"
$ cat /sys/bus/apr/devices/  # 空 = APR 不可用
```

**如果 APR 完全不可用**，说明 QCS6490 的 ADSP 固件确实只有 GPR/APM。
此时 USB offload 在当前上游内核中不可用，需要等待 AudioReach USB 支持的上游化。

### 问题 2：USB offload 模块加载但无 offload PCM 设备

```
可能原因：
1. machine driver 没有配置 USB offload DAI link
2. 设备树缺少 AFE USB 端口定义

排查：
$ grep -r "usb" /sys/kernel/debug/asoc/  # 检查 ASoC 拓扑
$ cat /sys/kernel/debug/asoc/components  # 检查注册的组件
```

### 问题 3：QMI 通信超时

```
可能原因：
1. ADSP 侧 QMI client 未启动
2. QRTR 路由问题

排查：
$ cat /sys/bus/qrtr/devices/  # 检查 QRTR 节点
$ dmesg | grep qrtr
```

## 阶段 6：如果需要补丁

### 6.1 Machine Driver 补丁

如果 AFE service 存在但 machine driver 缺少 USB routing：

```c
// 在 QCS6490 machine driver 中添加 USB offload DAI link
static struct snd_soc_dai_link qcs6490_dai_links[] = {
    // ... 现有 DAI links ...
    {
        .name = "USB Audio Offload",
        .stream_name = "USB Offload Playback",
        .dynamic = 1,
        .trigger = {SND_SOC_DPCM_TRIGGER_POST,
                    SND_SOC_DPCM_TRIGGER_POST},
        SND_SOC_DAILINK_REG(usb_offload),
    },
};
```

### 6.2 设备树补丁

```dts
// 在 QCS6490 设备树中添加 AFE USB 端口
&q6afe {
    usb_rx: port@0x7000 {
        reg = <0x7000>;
        qcom,port-type = <AFE_PORT_USB_RX>;
    };
    usb_tx: port@0x7001 {
        reg = <0x7001>;
        qcom,port-type = <AFE_PORT_USB_TX>;
    };
};
```

## 结果记录模板

```
日期：
内核版本：
固件版本：

APR 设备列表：
GPR 设备列表：
AFE 模块加载：成功/失败 (错误信息：)
USB offload 模块加载：成功/失败 (错误信息：)
USB 音频设备识别：是/否
Offload PCM 设备出现：是/否
QMI 通信：成功/失败
音频播放（CPU 路径）：成功/失败
音频播放（offload 路径）：成功/失败

结论：
```
