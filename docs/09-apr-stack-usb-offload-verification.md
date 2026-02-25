# APR 栈 USB Audio Offload 验证指南

## 背景

Radxa Q6A (QCS6490) 与 Fairphone 5 (QCM6490) 使用同一颗 SoC (SC7280/kodiak)。
Fairphone 5 已在 Linux 主线内核实现 USB audio offload，使用 APR/AFE 路径。
本文档记录如何在 Radxa Q6A 上复现这一能力。

## 架构对比

```
Fairphone 5 (USB offload 可用):
  kodiak.dtsi → APR → q6afe → q6usbdai → USB_RX
                     → q6asm → MultiMedia1
                     → q6adm → q6routing

Radxa Q6A (当前，USB offload 不可用):
  kodiak.dtsi → qcs6490-audioreach.dtsi → /delete-node/ apr
             → GPR → q6apm → q6apmbedai → CODEC_DMA only
                   → q6prm → q6prmcc

Radxa Q6A (目标，USB offload):
  kodiak.dtsi → APR → q6afe → q6afedai → RX_CODEC_DMA_RX_0 (WCD938x)
                                        → USB_RX (USB offload)
                     → q6asm → MultiMedia1
                     → q6adm → q6routing
              → q6usbdai (XHCI sideband + IOMMU)
```

## 前置条件

1. Radxa Q6A 开发板 + Linux 主线内核源码 (6.8+)
2. 交叉编译工具链 (aarch64-linux-gnu-)
3. USB 音频设备（USB 耳机或 USB 声卡）
4. 串口或 SSH 访问设备

## 文件清单

| 文件 | 用途 |
|------|------|
| `kernel/dts/qcs6490-radxa-q6a-usb-offload-apr.dts` | APR 栈设备树 |
| `kernel/patches/sc8280xp-usb-offload.patch` | 机器驱动 USB 补丁 |
| `kernel/config/usb_offload_apr.config` | 内核配置片段 |
| `scripts/verify-apr-firmware.sh` | 固件兼容性验证脚本 |

---

## Phase 1: ADSP 固件验证（最关键）

这是整个方案的前提。如果 ADSP 固件不支持 APR 协议，后续步骤全部无效。

### 1.1 在当前系统上运行验证脚本

```bash
sudo bash scripts/verify-apr-firmware.sh
```

### 1.2 关键检查项

| 检查项 | 期望结果 | 说明 |
|--------|----------|------|
| 固件中 APR 字符串 | > 0 | 固件包含 APR 协议支持 |
| 固件中 AFE 字符串 | > 0 | 固件包含 AFE 服务 |
| 固件中 USB 字符串 | > 0 | 固件包含 USB 音频模块 |

### 1.3 如果固件不支持 APR

选项 A: 尝试 Fairphone 5 的 ADSP 固件
```bash
# Fairphone 5 固件路径
# 从 linux-firmware 仓库获取
cp qcom/qcm6490/fairphone5/adsp.mbn \
   /lib/firmware/qcom/qcs6490/radxa/dragon-q6a/adsp.mbn.bak
cp fairphone5/adsp.mbn \
   /lib/firmware/qcom/qcs6490/radxa/dragon-q6a/adsp.mbn
```

选项 B: 联系 Qualcomm/Radxa 获取支持 APR 的固件

选项 C: 放弃 offload，使用标准 snd-usb-audio（零改动，立即可用）

---

## Phase 2: 内核编译

### 2.1 应用补丁

```bash
cd <kernel-source>
git apply kernel/patches/sc8280xp-usb-offload.patch
```

### 2.2 合并配置

```bash
./scripts/kconfig/merge_config.sh \
    arch/arm64/configs/defconfig \
    kernel/config/usb_offload_apr.config
make olddefconfig
```

### 2.3 验证关键配置

```bash
grep -E "QCOM_APR|QDSP6_USB|SND_SOC_USB|XHCI_SIDEBAND|SC8280XP" .config
```

期望输出:
```
CONFIG_QCOM_APR=m
CONFIG_SND_SOC_QDSP6_USB=m
CONFIG_SND_SOC_USB=m
CONFIG_USB_XHCI_SIDEBAND=y
CONFIG_SND_SOC_SC8280XP=m
```

### 2.4 编译

```bash
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- dtbs
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- modules
```

### 2.5 设备树编译

将 `qcs6490-radxa-q6a-usb-offload-apr.dts` 放入内核源码树:
```bash
cp kernel/dts/qcs6490-radxa-q6a-usb-offload-apr.dts \
   arch/arm64/boot/dts/qcom/

# 在 Makefile 中添加（或手动编译）
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
     qcom/qcs6490-radxa-q6a-usb-offload-apr.dtb
```

注意: DTS 文件引用了 kodiak.dtsi 但不引用 qcs6490-audioreach.dtsi。
需要将上游 Radxa Q6A DTS 中的非音频硬件节点合并进来。

---

## Phase 3: 部署与启动

### 3.1 部署文件

```bash
# 内核
scp arch/arm64/boot/Image root@q6a:/boot/

# 设备树
scp arch/arm64/boot/dts/qcom/qcs6490-radxa-q6a-usb-offload-apr.dtb \
    root@q6a:/boot/

# 模块
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
     INSTALL_MOD_PATH=/tmp/modules modules_install
scp -r /tmp/modules/lib/modules/<version> root@q6a:/lib/modules/
```

### 3.2 更新引导配置

根据引导方式（extlinux/U-Boot/UEFI）更新 DTB 路径指向新的 APR 设备树。

### 3.3 重启

```bash
reboot
```

---

## Phase 4: 启动后验证

### 4.1 APR 协议栈

```bash
# APR bus 必须存在
ls /sys/bus/apr/devices/
# 期望: aprsvc:qcom,q6core  aprsvc:qcom,q6afe  aprsvc:qcom,q6asm  aprsvc:qcom,q6adm

# GPR bus 不应存在（已切换到 APR）
ls /sys/bus/gpr/devices/ 2>/dev/null && echo "WARNING: GPR still active"
```

### 4.2 内核模块

```bash
lsmod | grep -E "q6afe|q6asm|q6adm|q6usb|apr"
# 期望: snd_soc_qdsp6_afe, snd_soc_qdsp6_asm, snd_soc_qdsp6_adm,
#        snd_soc_qdsp6_usb, qcom_apr
```

### 4.3 声卡

```bash
cat /proc/asound/cards
# 期望: 0 [QCS6490RadxaDra]: qcs6490 - QCS6490-Radxa-Dragon-Q6A-APR

aplay -l
# 期望: 包含 USB Playback 设备（插入 USB 音频设备后）
```

### 4.4 WCD938x 基本音频

先验证 WCD938x codec 在 APR 栈下正常工作:
```bash
# 播放测试音
speaker-test -D hw:0,0 -c 2 -t sine -f 440

# 或使用 aplay
aplay -D hw:0,0 /usr/share/sounds/alsa/Front_Center.wav
```

### 4.5 USB 音频 Offload

插入 USB 音频设备后:
```bash
# 检查 USB 设备识别
dmesg | grep -i "usb.*audio\|q6usb\|soc-usb"

# 检查 soc-usb 连接事件
dmesg | grep "snd_soc_usb_connect"

# 列出 PCM 设备（应出现 USB 相关设备）
cat /proc/asound/pcm

# 播放到 USB 设备
aplay -D hw:0,<usb-pcm-id> test.wav
```

---

## Phase 5: 故障排查

### 问题: APR bus 不存在

```bash
# 检查设备树是否正确
dtc -I dtb -O dts /boot/*.dtb 2>/dev/null | grep -A5 "apr {"
# 应该看到 apr 节点，不应该看到 /delete-node/ apr

# 检查 ADSP 是否启动
cat /sys/class/remoteproc/remoteproc*/state
# 应该是 "running"

# 检查 glink channel
dmesg | grep "apr_audio_svc\|glink"
```

### 问题: q6usb 模块加载失败

```bash
modprobe snd_soc_qdsp6_usb
dmesg | tail -20
# 检查是否有 IOMMU 或 sideband 错误
```

### 问题: USB 设备插入后无 offload

```bash
# 检查 XHCI sideband
dmesg | grep -i "sideband"

# 检查 QMI 通信
dmesg | grep -i "qmi\|uaudio"

# 检查 IOMMU 映射
dmesg | grep -i "iommu.*usb\|smmu.*180f"
```

### 问题: WCD938x 在 APR 栈下不工作

```bash
# 检查 SoundWire 总线
cat /sys/bus/soundwire/devices/*/status

# 检查 LPASS macro 时钟
dmesg | grep -i "lpass\|macro\|q6afe.*clock"

# 对比: kodiak.dtsi 中 LPASS macro 使用 q6afecc 时钟
# 确认设备树没有被 audioreach dtsi 覆盖
```

---

## 参考资料

| 资源 | 路径/URL |
|------|----------|
| Fairphone 5 DTS (工作参考) | `arch/arm64/boot/dts/qcom/qcm6490-fairphone-fp5.dts` |
| kodiak.dtsi (APR 栈定义) | `arch/arm64/boot/dts/qcom/kodiak.dtsi` |
| sc8280xp.c (机器驱动) | `sound/soc/qcom/sc8280xp.c` |
| sm8250.c (USB offload 参考) | `sound/soc/qcom/sm8250.c` |
| q6usb.c (USB offload 后端) | `sound/soc/qcom/qdsp6/q6usb.c` |
| qc_audio_offload.c (QMI+sideband) | `sound/usb/qcom/qc_audio_offload.c` |
| USB API (SPF 模块定义) | `audioreach-graphservices/spf/api/modules/usb_api.h` |
