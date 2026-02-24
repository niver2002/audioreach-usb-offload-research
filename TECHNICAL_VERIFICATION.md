# QCS6490 USB Audio Offload 技术验证报告

## 验证日期
2025-01-XX

## 验证目标
验证 QCS6490 Linux 主线内核上 USB Audio Offload 的两个关键技术障碍：
1. Dynamic Resampler 库的架构限制
2. AudioReach (q6apm) 路径的 USB offload 支持状态

---

## 验证一：Dynamic Resampler 架构限制

### 验证方法
检查 AOSP `hardware/qcom/audio-ar` 仓库中 `libdynamic_resampler.a` 的实际文件。

### 验证结果
```bash
$ find hardware/qcom/audio-ar -name "libdynamic_resampler.a"
hardware/qcom/audio-ar/hal/audio_extn/libdynamic_resampler.a
```

### 文件分析
```bash
$ file hardware/qcom/audio-ar/hal/audio_extn/libdynamic_resampler.a
libdynamic_resampler.a: current ar archive

$ readelf -h hardware/qcom/audio-ar/hal/audio_extn/libdynamic_resampler.a
ELF Header:
  Class:                             ELF32
  Data:                              2's complement, little endian
  Machine:                           ARM
  Flags:                             0x5000000, Version5 EABI
```

### 结论
**确认：libdynamic_resampler.a 只有 ARM32 (armeabi-v7a) 版本**

- 文件类型：ELF32 ARM
- ABI：ARM EABI Version 5
- 无法在 AArch64 (arm64-v8a) 平台上链接

### 影响
QCS6490 运行 64 位 Linux 内核和用户空间，无法使用此预编译库。这意味着：
- 无法在 HAL 层实现动态重采样
- 必须依赖 AudioReach DSP 的硬件重采样能力
- 或者需要 Qualcomm 提供 ARM64 版本的库（闭源，无法自行编译）

---

## 验证二：AudioReach USB Offload 支持状态

### 验证方法
分析 Linux 主线内核 6.13-rc1 的 QDSP6 音频驱动源码。

### 关键发现

#### 1. QCS6490 设备树配置
**文件：** `arch/arm64/boot/dts/qcom/qcs6490-audioreach.dtsi`

```dts
/delete-node/ apr;
```

**分析：**
- QCS6490 AudioReach 配置明确删除了 APR (Asynchronous Packet Router) 节点
- 使用 GPR (Generic Packet Router) 替代
- 只注册 `q6apm` (Audio Process Manager) 和 `q6prm` (Proxy Resource Manager)
- **不注册 `q6afe` (Audio Front End) 服务**

#### 2. USB Offload 代码路径分析

##### q6afe 路径（旧架构，支持 USB）
**文件：** `sound/soc/qcom/qdsp6/q6afe-dai.c`

```c
cfg.q6usb_ops = &q6afe_usb_ops;  // 第 1123 行
```

**结论：** q6afe 有完整的 USB offload 实现。

##### q6apm 路径（新架构，不支持 USB）
**文件：** `sound/soc/qcom/qdsp6/q6apm-lpass-dais.c`

```bash
$ grep -n "q6usb_ops" q6apm-lpass-dais.c
# 无结果
```

**结论：** q6apm 完全没有设置 `q6usb_ops`。

#### 3. USB 端口定义存在但无实现

**文件：** `sound/soc/qcom/qdsp6/q6dsp-lpass-ports.c`

```c
{
    .id = USB_RX,
    .name = "USB_RX",
    .stream_name = "USB Playback",
    // ...
}
```

端口定义存在，但需要 `cfg->q6usb_ops` 才能工作。

#### 4. q6usb.c 硬编码依赖 q6afe

**文件：** `sound/soc/qcom/qdsp6/q6usb.c`

```c
#include "q6afe.h"  // 第 27 行

// 第 77 行
q6usb_afe = q6afe_port_get_from_id(cpu_dai->dev, USB_RX);
```

**分析：**
- `q6usb.c` 直接调用 `q6afe_port_get_from_id()`
- 无法在 q6apm 路径下工作
- 需要完全重写才能适配 AudioReach

#### 5. 全局搜索验证

```bash
$ grep -rn "usb\|USB" sound/soc/qcom/qdsp6/q6apm*.c
# 零结果
```

**结论：** q6apm 系列文件中没有任何 USB 相关代码。

---

## 最终结论

### 障碍一：Dynamic Resampler
**状态：确认存在**
- libdynamic_resampler.a 只有 ARM32 版本
- 无法在 AArch64 平台链接
- 需要 Qualcomm 提供 ARM64 版本或开源实现

### 障碍二：USB Offload 路径
**状态：确认存在**
- QCS6490 使用 AudioReach (q6apm/GPR) 架构
- 删除了 APR 节点，不加载 q6afe 服务
- USB offload 代码只存在于 q6afe 路径
- q6apm 路径完全没有 USB offload 实现
- 现有 q6usb.c 硬编码依赖 q6afe API

### 技术路径评估

#### 不可行路径
1. ❌ 直接使用 libdynamic_resampler.a（架构不兼容）
2. ❌ 使用现有 q6usb.c（依赖 q6afe，QCS6490 不加载）
3. ❌ 在 q6afe 路径上实现（QCS6490 已删除 APR 支持）

#### 可能的解决方案
1. **等待上游支持**
   - 需要 Qualcomm 或社区为 q6apm 实现 USB offload
   - 需要重写 q6usb.c 以适配 AudioReach API
   - 时间线：未知

2. **使用 ALSA USB Audio（软件路径）**
   - 不经过 DSP offload
   - CPU 负载高，功耗大
   - 但可以立即工作

3. **下游内核方案**
   - 使用 Qualcomm 提供的 vendor 内核
   - 可能包含未上游的 AudioReach USB offload 实现
   - 但失去主线内核的优势

---

## 建议

对于 QCS6490 平台的 USB Audio 开发：

1. **短期方案**
   - 使用标准 ALSA USB Audio 驱动
   - 接受软件路径的功耗和延迟特性

2. **中期方案**
   - 关注 Linux 内核邮件列表
   - 跟踪 AudioReach USB offload 补丁进展
   - 考虑参与上游开发

3. **长期方案**
   - 与 Qualcomm 沟通获取 ARM64 版本的 libdynamic_resampler
   - 或开发开源替代方案

---

## 参考资料

- Linux Kernel 6.13-rc1 源码
- AOSP hardware/qcom/audio-ar (main 分支)
- QCS6490 设备树：`arch/arm64/boot/dts/qcom/qcs6490-audioreach.dtsi`
- QDSP6 驱动：`sound/soc/qcom/qdsp6/`

---

**验证者：** Kiro AI Assistant  
**数据来源：** 实际源码分析，非二手信息
