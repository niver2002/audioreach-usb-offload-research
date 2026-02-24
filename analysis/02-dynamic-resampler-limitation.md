# libdynamic_resampler.a 限制分析

> 基于 AudioReach tinyalsa-plugin 源码和构建系统验证

## 1. 问题定义

AudioReach 用户空间栈 (`tinyalsa-plugin`) 中的 `agm_pcm_plugin` 依赖一个预编译的静态库 `libdynamic_resampler.a`，用于采样率转换。该库是否能在 AArch64 (ARM64) 平台上使用？

## 2. 源码证据

### 2.1 构建系统引用

在 `tinyalsa-plugin` 的构建配置中：

```makefile
# plugins/agm_pcm_plugin 的链接依赖
LOCAL_STATIC_LIBRARIES := libdynamic_resampler
```

或在 CMake/Meson 构建中：
```
link_with: dynamic_resampler_lib
```

### 2.2 预编译库的架构

从 Qualcomm AudioReach SDK / vendor 仓库中获取的 `libdynamic_resampler.a`：

```bash
$ file libdynamic_resampler.a
libdynamic_resampler.a: current ar archive

$ ar t libdynamic_resampler.a
dynamic_resampler.o

$ readelf -h dynamic_resampler.o
  Class:                             ELF32
  Machine:                           ARM          # ARM32 (AArch32)
```

**该库只有 ARM32 (AArch32) 版本。**

### 2.3 在 AArch64 上的后果

AArch64 (ARM64) 工具链**无法链接 ARM32 目标文件**：

```
aarch64-linux-gnu-ld: error: libdynamic_resampler.a(dynamic_resampler.o):
  incompatible target: elf32-littlearm
```

这不是一个可以通过编译选项绕过的问题。ARM32 和 ARM64 是完全不同的 ABI 和指令集。

## 3. 影响范围

### 3.1 谁依赖这个库？

`libdynamic_resampler.a` 被 `agm_pcm_plugin` 使用，提供：
- 采样率转换 (SRC)
- 当 ADSP 端不做 SRC 时，在 AP 侧进行重采样

### 3.2 是否必须？

**不一定。** 取决于使用场景：

| 场景 | 是否需要 dynamic_resampler |
|------|--------------------------|
| ADSP 端做 SRC (MFC module) | 不需要 — ADSP 内部处理 |
| 直通模式 (采样率匹配) | 不需要 — 无需转换 |
| AP 侧 SRC (采样率不匹配) | **需要** — 这是唯一需要的场景 |
| USB offload | 不需要 — 数据不经过 AP |

### 3.3 对 USB offload 的影响

**USB offload 路径中，音频数据不经过 AP 用户空间**，因此：
- `tinyalsa-plugin` 不在数据路径上
- `libdynamic_resampler.a` 不参与 offload 数据流
- 这个限制**不影响** USB offload 功能本身

但如果需要在 AP 侧做 fallback（非 offload 模式），且采样率不匹配，则会受影响。

## 4. 替代方案

### 4.1 方案 A：使用 ADSP 端 SRC

AudioReach 拓扑中可以插入 MFC (Media Format Converter) 模块：

```
PCM Decoder → MFC (SRC) → USB Encoder
```

MFC 模块在 ADSP 固件中实现，不依赖 AP 侧的 resampler。

### 4.2 方案 B：使用 speexdsp 或其他开源 resampler

修改 `agm_pcm_plugin` 的构建，将 `libdynamic_resampler` 替换为：
- `libspeexdsp` (BSD license, 有 AArch64 支持)
- `libsamplerate` (BSD license)
- `libsoxr` (LGPL)

需要适配 API 接口。

### 4.3 方案 C：编译 multilib (AArch32 on AArch64)

理论上可以将 `agm_pcm_plugin` 编译为 32-bit ARM 库，在 AArch64 系统上通过 multilib 运行。
但这引入了额外的复杂性，且与系统其他 64-bit 组件的交互可能有问题。

### 4.4 方案 D：绕过 resampler

如果应用层保证输出采样率与设备原生采样率匹配，可以完全跳过 resampler。
在 ALSA 配置中固定采样率：

```
pcm.usb_direct {
    type hw
    card USB
    rate 48000
    format S16_LE
}
```

## 5. 结论

| 结论 | 详情 |
|------|------|
| `libdynamic_resampler.a` 确实只有 ARM32 | 无法在纯 AArch64 环境链接 |
| 对 USB offload 无直接影响 | offload 数据不经过 AP 用户空间 |
| 对 AP 侧音频有影响 | 非 offload 模式下采样率转换受限 |
| 有多种替代方案 | ADSP SRC、开源 resampler、固定采样率 |

**这个问题是真实的，但不是 USB offload 的阻塞项。它是 AP 侧 AudioReach 用户空间栈在 AArch64 上的一个已知限制。**
