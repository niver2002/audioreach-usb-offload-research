# 故障排查指南

## 概述

本文档提供 AudioReach USB Offload 系统的全面故障排查指南，涵盖从内核驱动到用户空间应用的各个层面。

## 问题分类

AudioReach USB Offload 问题可以分为以下几类：

1. **内核/驱动问题**: 驱动加载失败、设备初始化错误
2. **固件/DSP 问题**: ADSP 固件加载失败、模块不可用
3. **USB 设备问题**: USB 设备识别失败、格式不支持
4. **拓扑/配置问题**: Graph 配置错误、参数设置错误
5. **用户空间问题**: ALSA 配置错误、音频服务器问题

## 内核/驱动问题

### 问题 1: USB Offload 驱动未加载

**症状**
```bash
lsmod | grep q6usb
# 无输出
```

**原因分析**
- 内核未编译 USB offload 支持
- 模块依赖未满足
- 设备树配置缺失

**解决方案**

步骤 1: 检查内核配置
```bash
# 检查内核配置
zcat /proc/config.gz | grep -E "SND_SOC_QDSP6_Q6USB|SND_USB_AUDIO_QMI|SND_SOC_USB"

# 应该看到:
# CONFIG_SND_SOC_QDSP6_Q6USB=y 或 =m
# CONFIG_SND_USB_AUDIO_QMI=y 或 =m
# CONFIG_SND_SOC_USB=y 或 =m
```

步骤 2: 手动加载模块
```bash
# 按依赖顺序加载模块
sudo modprobe snd_soc_core
sudo modprobe snd_soc_qdsp6_common
sudo modprobe snd_soc_qdsp6_core
sudo modprobe snd_soc_qdsp6_afe
sudo modprobe snd_soc_usb
sudo modprobe snd_usb_audio_qmi
sudo modprobe snd_soc_qdsp6_q6usb

# 检查加载状态
lsmod | grep -E "q6usb|snd_soc_usb|qmi"
```

步骤 3: 检查模块加载错误
```bash
# 查看详细错误信息
dmesg | grep -i "q6usb\|snd_soc_usb" | tail -20

# 常见错误信息:
# "q6usb: Unknown symbol" -> 依赖模块未加载
# "q6usb: disagrees about version of symbol" -> 内核版本不匹配
# "q6usb: probe failed" -> 设备树配置问题
```

**验证命令**
```bash
# 验证模块已加载
lsmod | grep q6usb
# 输出: snd_soc_qdsp6_q6usb    16384  0

# 检查模块信息
modinfo snd_soc_qdsp6_q6usb

# 查看模块参数
cat /sys/module/snd_soc_qdsp6_q6usb/parameters/*
```

### 问题 2: XHCI Sideband 初始化失败

**症状**
```bash
dmesg | grep -i sideband
# xhci-hcd: sideband initialization failed
```

**原因分析**
- XHCI 控制器版本不支持 sideband
- Interrupter 配置错误
- DMA 映射失败

**解决方案**

步骤 1: 检查 XHCI 版本
```bash
# 查看 XHCI 版本
lspci -vv | grep -A 20 "USB controller"

# 或通过 sysfs
cat /sys/bus/pci/devices/*/class | grep 0c0330
# 找到 XHCI 设备后
cat /sys/bus/pci/devices/0000:00:14.0/revision

# Sideband 需要 XHCI 1.1 或更高版本
```

步骤 2: 检查 Interrupter 配置
```bash
# 查看 XHCI 调试信息
cat /sys/kernel/debug/usb/xhci/*/registers

# 检查 interrupter 数量
cat /sys/kernel/debug/usb/xhci/*/interrupters

# 应该至少有 2 个 interrupter（一个用于主机，一个用于 offload）
```

步骤 3: 检查设备树配置
```bash
# 查看 USB 控制器设备树
dtc -I fs /sys/firmware/devicetree/base/soc/usb* | grep -A 10 sideband

# 应该包含:
# sideband-manager;
```

步骤 4: 启用详细日志
```bash
# 启用 XHCI 调试日志
echo 'module xhci_hcd +p' > /sys/kernel/debug/dynamic_debug/control
echo 'module xhci_plat +p' > /sys/kernel/debug/dynamic_debug/control

# 重新加载驱动
sudo rmmod xhci_plat_hcd
sudo modprobe xhci_plat_hcd

# 查看日志
dmesg | grep -i xhci | tail -50
```

**验证命令**
```bash
# 检查 sideband 状态
cat /sys/kernel/debug/usb/xhci/*/sideband_status

# 应该输出:
# Sideband: enabled
# Interrupter: 1
# Transfer rings: allocated
```

### 问题 3: IOMMU 映射失败

**症状**
```bash
dmesg | grep -i iommu
# arm-smmu: Unhandled context fault
# q6apm: DMA mapping failed
```

**原因分析**
- IOMMU 域配置错误
- SID (Stream ID) 不匹配
- SMMU 页表损坏

**解决方案**

步骤 1: 检查 IOMMU 配置
```bash
# 查看 IOMMU 组
ls -l /sys/kernel/iommu_groups/

# 查看设备的 IOMMU 组
find /sys/kernel/iommu_groups/ -name "*usb*"
find /sys/kernel/iommu_groups/ -name "*audio*"
```

步骤 2: 检查设备树 IOMMU 配置
```bash
# 查看 USB 控制器的 IOMMU 配置
dtc -I fs /sys/firmware/devicetree/base/soc/usb* | grep -A 5 iommus

# 查看 APM 的 IOMMU 配置
dtc -I fs /sys/firmware/devicetree/base | grep -B 5 -A 10 "q6apm"

# 应该包含正确的 SMMU 引用和 SID
# iommus = <&apps_smmu 0x1801 0x0>;
```

步骤 3: 检查 SMMU 状态
```bash
# 查看 SMMU 寄存器
cat /sys/kernel/debug/iommu/arm-smmu/*/regs

# 检查 SMMU 错误
dmesg | grep -i "smmu\|iommu" | grep -i "fault\|error"
```

步骤 4: 禁用 IOMMU（仅用于调试）
```bash
# 在内核命令行添加（不推荐用于生产环境）
# iommu=off 或 iommu.passthrough=1

# 或在设备树中禁用特定设备的 IOMMU
# 删除或注释掉 iommus 属性
```

**验证命令**
```bash
# 检查 DMA 映射
cat /sys/kernel/debug/dma-buf/bufinfo

# 检查 IOMMU 域
cat /sys/kernel/debug/iommu/domains
```

### 问题 4: QMI 服务连接失败

**症状**
```bash
dmesg | grep -i qmi
# qmi: connection to service failed
# snd_usb_audio_qmi: QMI handshake timeout
```

**原因分析**
- ADSP 未运行
- GLINK 通信失败
- QMI 服务未注册

**解决方案**

步骤 1: 检查 ADSP 状态
```bash
# 查看 ADSP 运行状态
cat /sys/class/remoteproc/remoteproc*/state
# 应该输出: running

# 如果不是 running，启动 ADSP
echo start | sudo tee /sys/class/remoteproc/remoteproc0/state

# 查看 ADSP 启动日志
dmesg | grep -i "remoteproc\|adsp" | tail -30
```

步骤 2: 检查 GLINK 通信
```bash
# 查看 GLINK 状态
dmesg | grep -i glink

# 应该看到:
# qcom_glink_ssr: GLINK SSR driver probed
# qcom_glink_native: channel 'adsp_apps' opened

# 检查 GLINK 通道
cat /sys/kernel/debug/rpmsg/endpoints
```

步骤 3: 检查 QMI 服务
```bash
# 查看 QMI 服务列表
cat /sys/kernel/debug/qmi/services

# 应该看到 USB Audio QMI 服务
# Service: 0x41 (USB_AUDIO_STREAM)

# 检查 QMI 连接
dmesg | grep -i "qmi.*usb"
```

步骤 4: 重启 QMI 服务
```bash
# 卸载并重新加载 QMI 模块
sudo rmmod snd_usb_audio_qmi
sleep 1
sudo modprobe snd_usb_audio_qmi

# 查看加载日志
dmesg | grep -i qmi | tail -20
```

**验证命令**
```bash
# 验证 QMI 连接
cat /sys/kernel/debug/qmi/connections

# 应该看到活动的 QMI 连接
# Connection: USB_AUDIO_STREAM -> ADSP
```

## 固件/DSP 问题

### 问题 5: ADSP 固件加载失败

**症状**
```bash
cat /sys/class/remoteproc/remoteproc0/state
# offline

dmesg | grep -i adsp
# remoteproc: failed to load adsp.mbn
```

**原因分析**
- 固件文件不存在或路径错误
- 固件文件损坏
- 固件签名验证失败
- 内存区域配置错误

**解决方案**

步骤 1: 检查固件文件
```bash
# 查看固件路径
cat /sys/class/remoteproc/remoteproc0/firmware
# 输出: qcom/qcs6490/adsp/adsp.mbn

# 检查固件文件是否存在
ls -lh /lib/firmware/qcom/qcs6490/adsp/
# 应该看到:
# adsp.mbn
# adsp_dtb.mbn

# 检查文件权限
stat /lib/firmware/qcom/qcs6490/adsp/adsp.mbn
# 应该是 644 权限
```

步骤 2: 验证固件完整性
```bash
# 计算固件 MD5
md5sum /lib/firmware/qcom/qcs6490/adsp/adsp.mbn

# 与官方固件对比（如果有参考值）
# 或检查文件大小是否合理（通常 5-20MB）
ls -lh /lib/firmware/qcom/qcs6490/adsp/adsp.mbn
```

步骤 3: 检查内存区域
```bash
# 查看设备树中的 ADSP 内存区域
dtc -I fs /sys/firmware/devicetree/base/reserved-memory | grep -A 10 adsp

# 应该包含:
# adsp_mem: adsp@86700000 {
#     reg = <0x0 0x86700000 0x0 0x2800000>;
#     no-map;
# };

# 检查内存是否被占用
cat /proc/iomem | grep adsp
```

步骤 4: 启用固件加载日志
```bash
# 启用 remoteproc 调试日志
echo 'module remoteproc +p' > /sys/kernel/debug/dynamic_debug/control
echo 'module qcom_q6v5_adsp +p' > /sys/kernel/debug/dynamic_debug/control

# 尝试加载固件
echo start | sudo tee /sys/class/remoteproc/remoteproc0/state

# 查看详细日志
dmesg | grep -i "remoteproc\|adsp" | tail -50
```

步骤 5: 尝试手动加载
```bash
# 停止自动加载
echo stop | sudo tee /sys/class/remoteproc/remoteproc0/state

# 等待几秒
sleep 2

# 手动启动
echo start | sudo tee /sys/class/remoteproc/remoteproc0/state

# 监控启动过程
dmesg -w | grep -i adsp
```

**验证命令**
```bash
# 验证 ADSP 运行状态
cat /sys/class/remoteproc/remoteproc0/state
# 应该输出: running

# 查看 ADSP 资源使用
cat /sys/class/remoteproc/remoteproc0/recovery
cat /sys/class/remoteproc/remoteproc0/name
```

### 问题 6: USB AFE 模块不可用

**症状**
```bash
dmesg | grep -i "module.*usb"
# AudioReach: USB RX module not found
# AMDB: module 0x0700101E not loaded
```

**原因分析**
- AudioReach 固件版本过旧
- AMDB (Audio Module Database) 未加载 USB 模块
- 模块库文件缺失

**解决方案**

步骤 1: 检查 AudioReach 模块库
```bash
# 查看模块库目录
ls -lh /lib/firmware/qcom/qcs6490/adsp/audioreach/

# 应该包含:
# amdb_loader.bin
# module_usb_rx.bin
# module_usb_tx.bin
```

步骤 2: 重新加载 ADSP
```bash
# 完全重启 ADSP 以重新加载模块
echo stop | sudo tee /sys/class/remoteproc/remoteproc0/state
sleep 2
echo start | sudo tee /sys/class/remoteproc/remoteproc0/state
```

### 问题 7: Graph 打开失败

**症状**
```bash
dmesg | grep -i graph
# q6apm: Failed to open graph
# audioreach: Graph 0x1001 open failed: -22
```

**原因分析**
- 拓扑配置错误
- Module ID 不匹配
- 连接配置错误

**解决方案**

步骤 1: 检查拓扑文件
```bash
# 查看拓扑文件
ls -lh /lib/firmware/audioreach/

# 验证拓扑文件格式
file /lib/firmware/audioreach/*.tplg
```

步骤 2: 启用调试日志
```bash
# 启用 APM 调试日志
echo 'module q6apm +p' > /sys/kernel/debug/dynamic_debug/control

# 尝试打开音频流
aplay -D hw:0,0 /usr/share/sounds/alsa/Front_Center.wav

# 查看详细错误
dmesg | grep -i "q6apm\|graph" | tail -30
```

## USB 设备问题

### 问题 8: USB 设备未被 Offload 识别

**症状**
```bash
lsusb  # USB 设备存在
aplay -l  # 但 offload 声卡不显示 USB 设备
```

**解决方案**

步骤 1: 检查 USB 设备信息
```bash
# 查看 USB 设备详细信息
lsusb -v | grep -A 50 "Audio"

# 检查 Audio Class 版本
lsusb -v | grep "bcdADC"
```

步骤 2: 检查 kcontrol
```bash
# 查看 USB 相关的 ALSA 控制
amixer -c 0 controls | grep -i usb

# 检查控制值
amixer -c 0 cget name='USB Offload Playback Switch'
amixer -c 0 cget name='USB Offload Enable'
```

### 问题 9: 采样率不支持

**症状**
```bash
aplay -D hw:0,0 -r 192000 test.wav
# aplay: set_params: Sample rate 192000 not supported
```

**解决方案**

步骤 1: 检查 USB 设备支持的采样率
```bash
# 查看设备描述符
lsusb -v | grep -A 20 "AudioStreaming Interface" | grep "tSamFreq"

# 或通过 ALSA
cat /proc/asound/card*/stream0 | grep "Rates:"
```

步骤 2: 使用软件重采样
```bash
# 使用 ALSA 插件重采样
aplay -D plughw:0,0 -r 192000 test.wav
```

### 问题 10: 播放无声音

**症状**
```bash
aplay -D hw:0,0 test.wav
# 命令执行成功，但没有声音输出
```

**解决方案**

步骤 1: 检查音频路由
```bash
# 查看当前音频路由
amixer -c 0 contents | grep -A 2 "Playback"

# 启用路由
amixer -c 0 cset name='USB Playback Switch' on
```

步骤 2: 检查音量设置
```bash
# 设置主音量
amixer -c 0 cset name='Master Playback Volume' 80%

# 设置 USB 音量
amixer -c 0 cset name='USB Playback Volume' 80%

# 取消静音
amixer -c 0 cset name='Master Playback Switch' on
```

步骤 3: 测试音频数据流
```bash
# 使用 speaker-test 生成测试音
speaker-test -D hw:0,0 -c 2 -t sine -f 440

# 检查 PCM 状态
cat /proc/asound/card0/pcm0p/sub0/status
# 应该看到 state: RUNNING
```

## 调试工具和命令

### 系统级调试

```bash
# 启用所有 AudioReach 相关的调试日志
echo 8 > /proc/sys/kernel/printk
echo 'module q6apm +p' > /sys/kernel/debug/dynamic_debug/control
echo 'module q6apm_dai +p' > /sys/kernel/debug/dynamic_debug/control
echo 'module q6afe +p' > /sys/kernel/debug/dynamic_debug/control
echo 'module snd_soc_qdsp6_q6usb +p' > /sys/kernel/debug/dynamic_debug/control
echo 'module snd_usb_audio_qmi +p' > /sys/kernel/debug/dynamic_debug/control
```

### ALSA 调试命令

```bash
# 列出所有声卡
aplay -l
arecord -l

# 列出所有 PCM 设备
aplay -L

# 查看声卡信息
cat /proc/asound/cards
cat /proc/asound/devices

# 查看 PCM 信息
cat /proc/asound/card0/pcm0p/info
cat /proc/asound/card0/pcm0p/sub0/hw_params
cat /proc/asound/card0/pcm0p/sub0/status

# 查看 USB 音频信息
cat /proc/asound/card*/usbid
cat /proc/asound/card*/stream0

# Mixer 控制
amixer -c 0 contents
amixer -c 0 controls
```

### RemoteProc 调试

```bash
# 查看 ADSP 状态
cat /sys/class/remoteproc/remoteproc*/state
cat /sys/class/remoteproc/remoteproc*/name

# 查看固件信息
cat /sys/class/remoteproc/remoteproc*/firmware

# 查看崩溃日志
cat /sys/class/remoteproc/remoteproc*/recovery

# 手动控制 ADSP
echo stop > /sys/class/remoteproc/remoteproc0/state
echo start > /sys/class/remoteproc/remoteproc0/state
```

### USB 调试

```bash
# 查看 USB 设备树
cat /sys/kernel/debug/usb/devices

# 查看 XHCI 寄存器
cat /sys/kernel/debug/usb/xhci/*/registers

# 查看 USB 音频设备信息
lsusb -v -d <vendor>:<product>

# 监控 USB 事件
udevadm monitor --environment --udev | grep -i audio
```

## 日志分析方法

### 内核日志关键字

搜索以下关键字定位问题：

```bash
# AudioReach 相关
dmesg | grep -i "audioreach"
dmesg | grep -i "q6apm"
dmesg | grep -i "q6afe"

# USB Offload 相关
dmesg | grep -i "q6usb"
dmesg | grep -i "snd_usb_audio_qmi"
dmesg | grep -i "soc.usb"

# ADSP 相关
dmesg | grep -i "adsp"
dmesg | grep -i "remoteproc"
dmesg | grep -i "glink"
dmesg | grep -i "qmi"

# USB 相关
dmesg | grep -i "usb.*audio"
dmesg | grep -i "xhci"
dmesg | grep -i "sideband"

# 错误信息
dmesg | grep -i "error\|fail\|timeout" | grep -i "audio\|usb"
```

### 常见错误模式

**错误 1: 模块加载失败**
```
q6usb: Unknown symbol snd_soc_usb_connect
```
解决：检查模块依赖，确保 snd_soc_usb 先加载

**错误 2: QMI 超时**
```
snd_usb_audio_qmi: QMI handshake timeout
```
解决：检查 ADSP 状态，重启 ADSP

**错误 3: DMA 映射失败**
```
q6apm: DMA mapping failed: -12
```
解决：检查 IOMMU 配置，增加内存

**错误 4: Graph 启动失败**
```
audioreach: Graph start failed: -22
```
解决：检查拓扑配置，验证模块 ID

**错误 5: Sideband 不支持**
```
xhci-hcd: sideband not supported
```
解决：检查 XHCI 版本，更新设备树

### ADSP 日志获取

如果支持 ADSP 日志输出：

```bash
# 通过 debugfs 获取
cat /sys/kernel/debug/remoteproc/remoteproc0/trace0

# 或使用 Qualcomm diag 工具
# diag_mdlog -f /tmp/adsp.cfg -o /tmp/adsp_logs/

# 解析 ADSP 日志
# 需要 Qualcomm 提供的日志解析工具
```

### QMI 消息跟踪

```bash
# 启用 QMI 跟踪
echo 1 > /sys/kernel/debug/qmi/trace

# 查看 QMI 消息
cat /sys/kernel/debug/qmi/messages

# 过滤 USB Audio QMI 消息
cat /sys/kernel/debug/qmi/messages | grep "USB_AUDIO"
```

## 性能调优

### 缓冲区大小调整

```bash
# 调整 ALSA 缓冲区大小
# 编辑 /etc/asound.conf 或 ~/.asoundrc

pcm.usb_optimized {
    type plug
    slave {
        pcm "hw:0,0"
        period_time 0
        period_size 1024
        buffer_size 4096
    }
}

# 使用优化的配置
aplay -D usb_optimized test.wav
```

### 中断频率优化

```bash
# 查看当前中断频率
cat /proc/interrupts | grep -i "adsp\|usb"

# 调整 USB 轮询间隔（需要内核支持）
# 编辑设备树或模块参数
```

### DVFS 配置

```bash
# 查看 ADSP 频率
cat /sys/class/devfreq/*/cur_freq

# 设置性能模式
echo performance > /sys/class/devfreq/*/governor

# 或设置固定频率
echo 1000000000 > /sys/class/devfreq/*/userspace/set_freq
```

### 延迟优化技巧

1. **使用 IIR 重采样器**（如果音质可接受）
```bash
# 在拓扑中配置 MFC 使用 IIR 模式
# resampler_type = 0
```

2. **减小缓冲区大小**
```bash
# 使用更小的 period size
aplay -D hw:0,0 --period-size=512 --buffer-size=2048 test.wav
```

3. **启用硬件加速**
```bash
# 使用 Dynamic Resampler 的 HW 模式
# 在拓扑中配置 resampler_mode = HW
```

4. **优化 USB 传输**
```bash
# 使用 USB 3.0 端口
# 减少 USB 总线上的其他设备
# 使用高质量 USB 线缆
```

## 快速诊断脚本

```bash
#!/bin/bash
# audioreach-diagnose.sh - 快速诊断脚本

echo "=== AudioReach USB Offload Diagnostics ==="
echo ""

# 1. 内核版本
echo "1. Kernel Version:"
uname -r
echo ""

# 2. 模块状态
echo "2. Module Status:"
lsmod | grep -E "q6|usb.*audio|snd_soc" | awk '{print $1}'
echo ""

# 3. ADSP 状态
echo "3. ADSP Status:"
cat /sys/class/remoteproc/remoteproc*/state 2>/dev/null || echo "N/A"
echo ""

# 4. USB 设备
echo "4. USB Audio Devices:"
lsusb | grep -i audio || echo "None"
echo ""

# 5. ALSA 声卡
echo "5. ALSA Cards:"
cat /proc/asound/cards 2>/dev/null || echo "N/A"
echo ""

# 6. Offload 状态
echo "6. Offload Status:"
amixer -c 0 cget name='USB Offload Enable' 2>/dev/null || echo "N/A"
echo ""

# 7. 最近错误
echo "7. Recent Errors:"
dmesg | grep -i "error\|fail" | grep -i "audio\|usb\|adsp" | tail -5
echo ""

echo "=== Diagnostics Complete ==="
```

## 总结

AudioReach USB Offload 故障排查的关键步骤：

1. **自下而上排查**: 从硬件 → 驱动 → 固件 → 用户空间
2. **启用详细日志**: 使用 dynamic_debug 获取详细信息
3. **逐层验证**: 确认每一层都正常工作
4. **使用调试工具**: dmesg, amixer, lsusb, cat /proc/asound/*
5. **参考日志模式**: 识别常见错误模式

常见问题优先级：
- 高优先级: ADSP 固件加载、QMI 连接、USB 设备识别
- 中优先级: Graph 配置、模块加载、路由设置
- 低优先级: 性能优化、延迟调整、音质微调

遇到问题时，先运行快速诊断脚本，然后根据输出定位具体问题层面，再使用相应的调试命令深入分析。
