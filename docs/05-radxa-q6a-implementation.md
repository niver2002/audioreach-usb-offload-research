# Radxa Q6A 实现方案

## 硬件概述

Radxa Q6A 是一款基于 Qualcomm QCS6490 SoC 的单板计算机，具备完整的 AudioReach USB Offload 硬件支持。

### 核心硬件规格

**SoC: Qualcomm QCS6490**
- CPU: Kryo 670 (4x Cortex-A78 @ 2.7GHz + 4x Cortex-A55 @ 1.9GHz)
- GPU: Adreno 643
- DSP: Hexagon 698 (用于音频处理)
- 制程: 6nm
- 内存: LPDDR5 (最高 16GB)

**ADSP (Audio DSP) 子系统**
- 架构: Hexagon DSP v69
- 频率: 最高 1.0GHz
- 专用音频处理单元
- 支持 AudioReach 框架
- 低功耗音频处理能力

**USB 子系统**
- USB 3.0 Type-C 接口
- 控制器: Synopsys DWC3 XHCI
- 支持 USB Audio Class 2.0
- 支持 XHCI Sideband 接口
- 硬件 DMA 支持

**音频接口**
- I2S/TDM: 多路数字音频接口
- USB Audio: 通过 Type-C
- DisplayPort Audio: 通过 USB-C Alt Mode
- 内置 Codec: WCD9385

### 系统架构图

```
┌─────────────────────────────────────────────────────────────┐
│                      Radxa Q6A 硬件架构                       │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌──────────────┐         ┌──────────────┐                  │
│  │  Application │         │   Linux      │                  │
│  │  Processor   │◄───────►│   Kernel     │                  │
│  │  (Kryo 670)  │  GLINK  │              │                  │
│  └──────────────┘         └──────────────┘                  │
│         │                        │                           │
│         │ QMI/GPR               │ ALSA                      │
│         ▼                        ▼                           │
│  ┌──────────────────────────────────────┐                   │
│  │         ADSP (Hexagon DSP)           │                   │
│  │  ┌────────────────────────────────┐  │                   │
│  │  │    AudioReach Framework        │  │                   │
│  │  │  ┌──────┐  ┌──────┐  ┌──────┐ │  │                   │
│  │  │  │ USB  │  │ MFC  │  │ I2S  │ │  │                   │
│  │  │  │ AFE  │→ │Module│→ │ AFE  │ │  │                   │
│  │  │  └──────┘  └──────┘  └──────┘ │  │                   │
│  │  └────────────────────────────────┘  │                   │
│  └──────────────┬───────────────────────┘                   │
│                 │                                            │
│                 │ IOMMU/SMMU                                │
│                 ▼                                            │
│  ┌──────────────────────────────────────┐                   │
│  │      USB 3.0 XHCI Controller         │                   │
│  │  ┌────────────────────────────────┐  │                   │
│  │  │   Sideband Interface           │  │                   │
│  │  │   - Transfer Ring Access       │  │                   │
│  │  │   - Interrupter Management     │  │                   │
│  │  │   - DMA Buffer Sharing         │  │                   │
│  │  └────────────────────────────────┘  │                   │
│  └──────────────┬───────────────────────┘                   │
│                 │                                            │
│                 ▼                                            │
│         USB Type-C Port                                      │
│                 │                                            │
└─────────────────┼────────────────────────────────────────────┘
                  │
                  ▼
          USB Audio Device
       (DAC, Headset, Speaker)
```

## 前置条件

### 软件要求

**Linux 内核版本**
- 最低要求: Linux 6.8+
- 推荐版本: Linux 6.10+ 或更新
- 必须包含以下补丁集:
  - AudioReach USB offload 支持
  - XHCI sideband 接口
  - QCS6490 设备树支持

**固件文件**
```bash
# ADSP 固件位置
/lib/firmware/qcom/qcs6490/adsp/
├── adsp.mbn          # ADSP 主固件
├── adsp_dtb.mbn      # ADSP 设备树
└── audioreach/       # AudioReach 模块库
    ├── amdb_loader.bin
    ├── module_usb_rx.bin
    ├── module_usb_tx.bin
    ├── module_mfc.bin
    └── module_resampler.bin
```

**工具链**
```bash
# 必需工具
- alsa-utils (>= 1.2.8)
- alsa-topology-conf
- audioreach-topology (Qualcomm 提供)
- m4 (用于拓扑宏处理)
- alsatplg (ALSA 拓扑编译器)
```

### 硬件要求

- Radxa Q6A 开发板
- USB Type-C 线缆（支持 USB 3.0）
- USB Audio 设备（DAC、声卡、耳机等）
- 电源适配器（12V/2A 或更高）

## 内核配置

### 必需的内核选项

创建或修改内核配置文件 `.config`:

```bash
# AudioReach 核心支持
CONFIG_SND_SOC_QCOM_QDSP6=y
CONFIG_SND_SOC_QDSP6_CORE=y
CONFIG_SND_SOC_QDSP6_AFE=y
CONFIG_SND_SOC_QDSP6_AFE_DAI=y
CONFIG_SND_SOC_QDSP6_APM=y
CONFIG_SND_SOC_QDSP6_APM_DAI=y
CONFIG_SND_SOC_QDSP6_APM_LPASS_DAI=y

# USB Offload 支持
CONFIG_SND_SOC_QDSP6_Q6USB=y
CONFIG_SND_USB_AUDIO_QMI=y
CONFIG_SND_SOC_USB=y

# XHCI Sideband 支持
CONFIG_USB_XHCI_HCD=y
CONFIG_USB_XHCI_PLATFORM=y
CONFIG_USB_XHCI_SIDEBAND=y

# Qualcomm 通信框架
CONFIG_QCOM_GLINK=y
CONFIG_QCOM_GLINK_RPM=y
CONFIG_RPMSG=y
CONFIG_RPMSG_QCOM_GLINK_RPM=y
CONFIG_QCOM_APR=y
CONFIG_QCOM_GPR=y

# Remoteproc (用于加载 ADSP 固件)
CONFIG_REMOTEPROC=y
CONFIG_QCOM_Q6V5_ADSP=y
CONFIG_QCOM_Q6V5_COMMON=y
CONFIG_QCOM_RPROC_COMMON=y
CONFIG_QCOM_SYSMON=y

# IOMMU 支持
CONFIG_IOMMU_SUPPORT=y
CONFIG_ARM_SMMU=y
CONFIG_QCOM_IOMMU=y

# USB Audio 基础支持
CONFIG_SND_USB=y
CONFIG_SND_USB_AUDIO=y
CONFIG_SND_USB_AUDIO_USE_MEDIA_CONTROLLER=y

# 调试选项 (可选)
CONFIG_SND_DEBUG=y
CONFIG_SND_VERBOSE_PRINTK=y
CONFIG_DYNAMIC_DEBUG=y
```

### 编译内核

```bash
# 配置内核
cd linux-6.10
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- qcs6490_defconfig

# 应用 USB offload 配置
cat >> .config << EOF
CONFIG_SND_SOC_QDSP6_Q6USB=y
CONFIG_SND_USB_AUDIO_QMI=y
CONFIG_SND_SOC_USB=y
CONFIG_USB_XHCI_SIDEBAND=y
EOF

# 编译内核和模块
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- modules -j$(nproc)

# 编译设备树
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- dtbs

# 安装
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- modules_install INSTALL_MOD_PATH=/mnt/rootfs
cp arch/arm64/boot/Image /mnt/boot/
cp arch/arm64/boot/dts/qcom/qcs6490-radxa-q6a.dtb /mnt/boot/
```

## 设备树配置

### 完整的设备树配置

创建或修改 `qcs6490-radxa-q6a.dts`:

```dts
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Radxa Q6A USB Audio Offload 设备树配置
 */

/dts-v1/;

#include <dt-bindings/interrupt-controller/arm-gic.h>
#include <dt-bindings/clock/qcom,gcc-qcs6490.h>
#include <dt-bindings/clock/qcom,rpmh.h>
#include <dt-bindings/power/qcom-rpmpd.h>
#include <dt-bindings/soc/qcom,apr.h>
#include <dt-bindings/soc/qcom,gpr.h>
#include <dt-bindings/sound/qcom,q6afe.h>

/ {
    model = "Radxa Q6A";
    compatible = "radxa,q6a", "qcom,qcs6490";

    #address-cells = <2>;
    #size-cells = <2>;

    aliases {
        serial0 = &uart5;
    };

    chosen {
        stdout-path = "serial0:115200n8";
    };

    memory@80000000 {
        device_type = "memory";
        reg = <0x0 0x80000000 0x0 0x200000000>; // 8GB
    };

    reserved-memory {
        #address-cells = <2>;
        #size-cells = <2>;
        ranges;

        // ADSP 内存区域
        adsp_mem: adsp@86700000 {
            reg = <0x0 0x86700000 0x0 0x2800000>;
            no-map;
        };

        // 音频缓冲区
        audio_heap: audio-heap@8a000000 {
            reg = <0x0 0x8a000000 0x0 0x400000>;
            no-map;
        };
    };
};

&soc {
    // ADSP Remoteproc 节点
    remoteproc_adsp: remoteproc@3000000 {
        compatible = "qcom,qcs6490-adsp-pas";
        reg = <0x0 0x03000000 0x0 0x100>;

        interrupts-extended = <&intc GIC_SPI 162 IRQ_TYPE_EDGE_RISING>,
                             <&adsp_smp2p_in 0 IRQ_TYPE_EDGE_RISING>,
                             <&adsp_smp2p_in 1 IRQ_TYPE_EDGE_RISING>,
                             <&adsp_smp2p_in 2 IRQ_TYPE_EDGE_RISING>,
                             <&adsp_smp2p_in 3 IRQ_TYPE_EDGE_RISING>;
        interrupt-names = "wdog", "fatal", "ready",
                         "handover", "stop-ack";

        clocks = <&rpmhcc RPMH_CXO_CLK>;
        clock-names = "xo";

        power-domains = <&rpmhpd QCS6490_LCX>,
                       <&rpmhpd QCS6490_LMX>;
        power-domain-names = "lcx", "lmx";

        memory-region = <&adsp_mem>;

        qcom,smem-states = <&adsp_smp2p_out 0>;
        qcom,smem-state-names = "stop";

        status = "okay";

        glink-edge {
            interrupts-extended = <&ipcc IPCC_CLIENT_LPASS
                                        IPCC_MPROC_SIGNAL_GLINK_QMP
                                        IRQ_TYPE_EDGE_RISING>;
            mboxes = <&ipcc IPCC_CLIENT_LPASS
                           IPCC_MPROC_SIGNAL_GLINK_QMP>;

            label = "lpass";
            qcom,remote-pid = <2>;

            // GPR 服务节点
            gpr {
                compatible = "qcom,gpr";
                qcom,glink-channels = "adsp_apps";
                qcom,domain = <GPR_DOMAIN_ID_ADSP>;
                qcom,intents = <512 20>;
                #address-cells = <1>;
                #size-cells = <0>;

                // APM 服务
                q6apm: service@1 {
                    compatible = "qcom,q6apm";
                    reg = <GPR_APM_MODULE_IID>;
                    #sound-dai-cells = <0>;

                    q6apmdai: dais {
                        compatible = "qcom,q6apm-dais";
                        iommus = <&apps_smmu 0x1801 0x0>;
                    };

                    q6apmbedai: bedais {
                        compatible = "qcom,q6apm-lpass-dais";
                        #sound-dai-cells = <1>;
                    };
                };

                // AFE 服务
                q6afe: service@2 {
                    compatible = "qcom,q6afe";
                    reg = <GPR_AFE_MODULE_IID>;

                    q6afeusb: usb {
                        compatible = "qcom,q6afe-usb";
                        #sound-dai-cells = <1>;
                    };
                };
            };
        };
    };
};
```

## 拓扑配置

### 编译和安装拓扑

```bash
# 处理 M4 宏
m4 usb-offload-playback.m4 > usb-offload-playback.conf

# 使用 alsatplg 编译拓扑
alsatplg -c usb-offload-playback.conf -o usb-offload-playback.tplg

# 安装到固件目录
sudo mkdir -p /lib/firmware/audioreach
sudo cp usb-offload-playback.tplg /lib/firmware/audioreach/

# 验证拓扑文件
alsatplg -d usb-offload-playback.tplg
```

### 简化的拓扑配置

如果不使用 M4 宏，可以直接编写 ALSA 拓扑配置：

```conf
# usb-offload-simple.conf

SectionVendorTuples."usb_rx_tokens" {
    tokens "qcom,audioreach"
    
    tuples."word" {
        QCOM_TPLG_FE_BE_GRAPH_CTL_MIX = "1"
    }
}

SectionGraph."USB Playback Graph" {
    index "1"
    
    lines [
        "USB_RX, , , , MFC"
        "MFC, , , , VOLUME"
        "VOLUME, , , , I2S_TX"
    ]
}

SectionPCM."USB Playback" {
    index "1"
    id "0"
    
    pcm {
        playback "2"
        capture "0"
    }
    
    capabilities {
        formats "S16_LE,S24_LE"
        rate_min "8000"
        rate_max "192000"
        channels_min "1"
        channels_max "2"
    }
}
```

## 用户空间配置

### ALSA UCM 配置

创建 UCM 配置文件 `/usr/share/alsa/ucm2/qcs6490-radxa-q6a/qcs6490-radxa-q6a.conf`:

```conf
Syntax 4

Comment "Radxa Q6A USB Audio Offload"

SectionUseCase."HiFi" {
    File "HiFi.conf"
    Comment "Default audio profile"
}
```

创建 HiFi 配置 `/usr/share/alsa/ucm2/qcs6490-radxa-q6a/HiFi.conf`:

```conf
SectionVerb {
    EnableSequence [
        cset "name='USB Offload Playback Switch' on"
    ]
    
    DisableSequence [
        cset "name='USB Offload Playback Switch' off"
    ]
    
    Value {
        TQ "HiFi"
    }
}

SectionDevice."USB" {
    Comment "USB Audio Device"
    
    EnableSequence [
        cset "name='USB Playback Volume' 80%"
        cset "name='USB Offload Enable' 1"
    ]
    
    DisableSequence [
        cset "name='USB Offload Enable' 0"
    ]
    
    Value {
        PlaybackPriority 200
        PlaybackPCM "hw:0,0"
        PlaybackMixerElem "USB Playback"
        PlaybackVolume "USB Playback Volume"
    }
}
```

### PulseAudio 配置

编辑 `/etc/pulse/default.pa`:

```bash
# 加载 ALSA 模块
load-module module-alsa-sink device=hw:0,0 sink_name=usb_offload
load-module module-alsa-source device=hw:0,1 source_name=usb_offload_source

# 设置默认设备
set-default-sink usb_offload
set-default-source usb_offload_source

# USB 设备自动切换
load-module module-switch-on-connect
```

### PipeWire 配置

创建 `/etc/pipewire/pipewire.conf.d/50-usb-offload.conf`:

```conf
context.modules = [
    {
        name = libpipewire-module-alsa
        args = {
            alsa.card = 0
            alsa.device = 0
            node.name = "usb-offload-playback"
            node.description = "USB Offload Playback"
            audio.position = [ FL FR ]
            api.alsa.period-size = 1024
            api.alsa.headroom = 0
        }
    }
]
```

## 端到端测试流程

### 步骤 1: 检查 ADSP 固件加载

```bash
# 查看 remoteproc 状态
cat /sys/class/remoteproc/remoteproc0/state
# 应该输出: running

# 检查固件加载日志
dmesg | grep -i "adsp\|remoteproc"
# 期望看到:
# remoteproc remoteproc0: powering up 3000000.remoteproc
# remoteproc remoteproc0: Booting fw image qcom/qcs6490/adsp/adsp.mbn
# remoteproc remoteproc0: remote processor 3000000.remoteproc is now up

# 检查 GLINK 通信
dmesg | grep -i glink
# 期望看到:
# qcom_glink_ssr remoteproc0:glink-edge: GLINK SSR driver probed
```

### 步骤 2: 检查 USB 设备识别

```bash
# 插入 USB 音频设备后检查
lsusb
# 应该看到 USB Audio 设备

# 检查 USB 音频驱动加载
lsmod | grep snd_usb_audio
# 应该看到 snd_usb_audio 模块

# 检查 USB offload 驱动
lsmod | grep -E "q6usb|snd_soc_usb"
# 应该看到:
# snd_soc_qdsp6_q6usb
# snd_usb_audio_qmi
# snd_soc_usb

# 查看 USB 设备详细信息
cat /proc/asound/card*/usbid
cat /proc/asound/card*/stream0
```

### 步骤 3: 检查 ALSA 声卡和 PCM 设备

```bash
# 列出所有声卡
aplay -l
# 期望输出:
# card 0: qcs6490radxaq6 [qcs6490-radxa-q6a-snd-card], device 0: MultiMedia1 []
#   Subdevices: 1/1
#   Subdevice #0: subdevice #0

# 列出所有 PCM 设备
aplay -L | grep -A 2 "usb\|offload"

# 查看声卡控制
amixer -c 0 contents | head -20
```

### 步骤 4: 启用 USB offload 路由

```bash
# 查看可用的 kcontrols
amixer -c 0 controls | grep -i usb

# 启用 USB offload
amixer -c 0 cset name='USB Offload Playback Switch' on
amixer -c 0 cset name='USB Offload Enable' 1

# 设置音量
amixer -c 0 cset name='USB Playback Volume' 80%

# 验证设置
amixer -c 0 cget name='USB Offload Playback Switch'
```

### 步骤 5: 播放测试音频

```bash
# 生成测试音频文件
speaker-test -t sine -f 440 -c 2 -r 48000 -F S16_LE -d 5 > /tmp/test.raw

# 使用 aplay 播放
aplay -D hw:0,0 -f S16_LE -r 48000 -c 2 /tmp/test.raw

# 或使用 speaker-test 直接测试
speaker-test -D hw:0,0 -c 2 -r 48000 -F S16_LE -t sine

# 播放 WAV 文件
aplay -D hw:0,0 /usr/share/sounds/alsa/Front_Center.wav
```

### 步骤 6: 验证 DSP offload 状态

```bash
# 检查 DSP Graph 状态
cat /sys/kernel/debug/audioreach/graphs
# 应该看到活动的 Graph

# 检查模块状态
cat /sys/kernel/debug/audioreach/modules | grep -A 5 "USB_RX\|MFC"

# 监控 ADSP 日志
dmesg -w | grep -i "q6apm\|audioreach\|usb"

# 检查 CPU 使用率（应该很低）
top -b -n 1 | grep -E "CPU|aplay"

# 检查中断统计
cat /proc/interrupts | grep -i "adsp\|usb"
```

## 性能验证

### CPU 使用率对比

测试场景：播放 48kHz 16-bit 立体声音频

预期结果：

| 模式 | CPU 使用率 | 说明 |
|------|-----------|------|
| 非 Offload | 15-25% | 主 CPU 处理音频 |
| Offload | 2-5% | DSP 处理音频 |
| 节省 | ~80% | 显著降低功耗 |

### 延迟测量

```bash
# 使用 alsa 工具测试延迟
aplay -D hw:0,0 --test-position /tmp/test.raw
```

预期延迟：

| 配置 | 延迟 |
|------|------|
| MFC IIR 模式 | 5-8ms |
| MFC FIR 模式 | 15-25ms |
| Dynamic Resampler HW | 3-5ms |

### 功耗对比

预期功耗节省：30-50%

## 完整的命令行示例

### 初始化和配置

```bash
#!/bin/bash
# usb-offload-setup.sh

echo "=== Radxa Q6A USB Audio Offload Setup ==="

# 1. 检查内核模块
echo "Checking kernel modules..."
REQUIRED_MODULES="snd_soc_qdsp6_q6usb snd_usb_audio_qmi snd_soc_usb"
for mod in $REQUIRED_MODULES; do
    if ! lsmod | grep -q $mod; then
        echo "Loading module: $mod"
        sudo modprobe $mod
    fi
done

# 2. 检查 ADSP 状态
echo "Checking ADSP status..."
ADSP_STATE=$(cat /sys/class/remoteproc/remoteproc0/state)
if [ "$ADSP_STATE" != "running" ]; then
    echo "Starting ADSP..."
    echo start | sudo tee /sys/class/remoteproc/remoteproc0/state
    sleep 2
fi

# 3. 配置 ALSA
echo "Configuring ALSA..."
amixer -c 0 cset name='USB Offload Playback Switch' on
amixer -c 0 cset name='USB Offload Enable' 1
amixer -c 0 cset name='USB Playback Volume' 80%

echo "=== Setup Complete ==="
```

### 播放测试脚本

```bash
#!/bin/bash
# usb-offload-test.sh

CARD=0
DEVICE=0
RATE=48000
FORMAT=S16_LE
CHANNELS=2

echo "=== USB Audio Offload Test ==="

# 测试 1: 440Hz 正弦波
echo "Test 1: 440Hz sine wave"
speaker-test -D hw:$CARD,$DEVICE -c $CHANNELS -r $RATE -F $FORMAT -t sine -f 440 -d 5

# 测试 2: 不同采样率
for rate in 44100 48000 96000; do
    echo "Test 2: Sample rate $rate Hz"
    speaker-test -D hw:$CARD,$DEVICE -c $CHANNELS -r $rate -F $FORMAT -t sine -d 3
    sleep 1
done

echo "=== Test Complete ==="
```

### 调试脚本

```bash
#!/bin/bash
# usb-offload-debug.sh

OUTPUT_FILE="usb-offload-debug-$(date +%Y%m%d-%H%M%S).log"

echo "=== USB Audio Offload Debug Info ===" | tee $OUTPUT_FILE

# 系统信息
echo "=== System Info ===" | tee -a $OUTPUT_FILE
uname -a | tee -a $OUTPUT_FILE

# 内核模块
echo "=== Kernel Modules ===" | tee -a $OUTPUT_FILE
lsmod | grep -E "snd|usb|q6" | tee -a $OUTPUT_FILE

# ADSP 状态
echo "=== ADSP Status ===" | tee -a $OUTPUT_FILE
cat /sys/class/remoteproc/remoteproc*/state | tee -a $OUTPUT_FILE

# USB 设备
echo "=== USB Devices ===" | tee -a $OUTPUT_FILE
lsusb | tee -a $OUTPUT_FILE

# ALSA 声卡
echo "=== ALSA Cards ===" | tee -a $OUTPUT_FILE
cat /proc/asound/cards | tee -a $OUTPUT_FILE

# ALSA 控制
echo "=== ALSA Controls ===" | tee -a $OUTPUT_FILE
amixer -c 0 contents | grep -A 2 -i "usb" | tee -a $OUTPUT_FILE

# 内核日志
echo "=== Kernel Log ===" | tee -a $OUTPUT_FILE
dmesg | tail -100 | grep -i "usb\|audio\|adsp" | tee -a $OUTPUT_FILE

echo "Debug info saved to: $OUTPUT_FILE"
```

## 故障排查快速参考

### 问题 1: ADSP 固件加载失败

```bash
# 症状
cat /sys/class/remoteproc/remoteproc0/state
# 输出: offline 或 crashed

# 检查固件文件
ls -la /lib/firmware/qcom/qcs6490/adsp/

# 查看错误日志
dmesg | grep -i "remoteproc\|adsp" | tail -20

# 解决方案
# 1. 确认固件文件存在且权限正确
sudo chmod 644 /lib/firmware/qcom/qcs6490/adsp/*

# 2. 手动重启 ADSP
echo stop | sudo tee /sys/class/remoteproc/remoteproc0/state
sleep 1
echo start | sudo tee /sys/class/remoteproc/remoteproc0/state
```

### 问题 2: USB 设备未被识别

```bash
# 症状
lsusb  # 看不到 USB Audio 设备

# 检查 USB 控制器
lspci | grep -i usb
cat /sys/kernel/debug/usb/devices

# 检查 USB 驱动
lsmod | grep usb

# 解决方案
# 1. 重新插拔 USB 设备
# 2. 检查 USB 端口供电
# 3. 尝试不同的 USB 端口
```

### 问题 3: Offload 不工作

```bash
# 症状
# 音频播放正常，但 CPU 使用率高

# 检查 offload 状态
amixer -c 0 cget name='USB Offload Enable'

# 检查 QMI 连接
dmesg | grep -i qmi

# 解决方案
# 1. 确认 offload 已启用
amixer -c 0 cset name='USB Offload Enable' 1

# 2. 检查拓扑文件
ls -la /lib/firmware/audioreach/

# 3. 重启音频服务
sudo systemctl restart pulseaudio
```

## 总结

Radxa Q6A 的 USB Audio Offload 实现需要以下关键组件：

1. **内核支持**: Linux 6.8+ 包含必要的驱动和补丁
2. **设备树配置**: 正确配置 ADSP、USB 和 IOMMU
3. **固件文件**: ADSP 固件和 AudioReach 模块
4. **拓扑配置**: 定义音频处理 Graph
5. **用户空间配置**: ALSA UCM 和音频服务器配置

正确配置后，系统可以实现：
- CPU 使用率降低 80%
- 功耗降低 30-50%
- 延迟保持在 5-25ms（取决于配置）
- 支持多种采样率和格式

通过本文档提供的脚本和配置，可以快速在 Radxa Q6A 上部署和测试 USB Audio Offload 功能。
