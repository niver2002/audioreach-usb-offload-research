# AudioReach USB Audio Offload 实现指南

## 概述

本文档基于上游 Linux 内核真实源码，提供 AudioReach USB Audio Offload 的实现指南。需要特别注意的是，上游实现与早期文档描述存在重大差异，本指南将基于真实的驱动架构和数据路径进行说明。

## 上游架构概览

### 真实的驱动模块

上游内核中 USB Audio Offload 由以下模块组成：

1. **q6usb.c** - ASoC component driver
   - 路径：`sound/soc/qcom/qdsp6/q6usb.c`
   - 功能：注册 USB_RX_BE DAPM widget，创建 auxiliary device
   - 不直接处理音频数据流

2. **qc_audio_offload.c** - Auxiliary driver
   - 路径：`sound/usb/qcom/qc_audio_offload.c`
   - 功能：处理 QMI 通信，管理 XHCI sideband 接口
   - 核心：enable_audio_stream() 和 handle_uaudio_stream_req()

3. **xhci-sideband.c** - XHCI sideband API
   - 路径：`drivers/usb/host/xhci-sideband.c`
   - 功能：提供 XHCI transfer ring 和 event ring 的直接访问
   - 由 Intel 贡献到上游

4. **q6afe-dai.c / q6afe.c** - AFE 层
   - 路径：`sound/soc/qcom/qdsp6/q6afe-dai.c`
   - 功能：定义 USB_RX port，但这是 AFE 配置层
   - 注意：上游已封闭 AFE 方向的 USB offload 路径

### 真实数据路径

```
USB 设备插入
    ↓
qc_usb_audio_offload_probe()
    ↓
xhci_sideband_register()
    ↓
snd_soc_usb_connect()
    ↓
ADSP QMI request
    ↓
handle_uaudio_stream_req()
    ↓
enable_audio_stream()
    ↓
xhci_sideband_add_endpoint()
    ↓
获取 TR/ER/XferBuf IOVA
    ↓
prepare_qmi_response()
    ↓
QMI response 返回给 ADSP
    ↓
ADSP 直接操作 XHCI transfer ring
```

### 关键概念

**XHCI Sideband Interface**
- 允许 ADSP 直接访问 XHCI 控制器的 transfer ring 和 event ring
- 绕过 USB 核心驱动栈
- 通过 IOMMU 映射实现 ADSP 可访问的地址空间

**QMI (Qualcomm MSM Interface)**
- ADSP 与 AP 之间的通信协议
- Service ID: UAUDIO_STREAM_SERVICE_ID_V01
- 传递 USB 设备信息和 XHCI 内存地址

**IOVA (IO Virtual Address)**
- Transfer Ring IOVA
- Event Ring IOVA
- Transfer Buffer IOVA
- 通过 uaudio_iommu_map() 映射到 ADSP 可访问空间

## 内核配置

### 必需的 CONFIG 选项

```bash
# USB 基础支持
CONFIG_USB=y
CONFIG_USB_XHCI_HCD=y
CONFIG_USB_XHCI_PLATFORM=y

# XHCI Sideband 支持（关键）
CONFIG_USB_XHCI_SIDEBAND=y

# USB Audio 基础
CONFIG_SND_USB_AUDIO=y

# Qualcomm ASoC 支持
CONFIG_SND_SOC_QCOM=y
CONFIG_SND_SOC_QDSP6=y
CONFIG_SND_SOC_QDSP6_CORE=y
CONFIG_SND_SOC_QDSP6_AFE=y
CONFIG_SND_SOC_QDSP6_AFE_DAI=y

# Q6 USB 驱动
CONFIG_QCOM_Q6USB=y

# QC USB Audio Offload 驱动
CONFIG_QC_USB_AUDIO_OFFLOAD=y

# IOMMU 支持
CONFIG_IOMMU_SUPPORT=y
CONFIG_ARM_SMMU=y
CONFIG_QCOM_IOMMU=y

# Remoteproc（ADSP 固件加载）
CONFIG_REMOTEPROC=y
CONFIG_QCOM_Q6V5_ADSP=y

# GLINK/GPR 通信
CONFIG_QCOM_GLINK=y
CONFIG_QCOM_GLINK_SMEM=y
CONFIG_QCOM_GPR=y
```

### 内核编译

```bash
# 克隆上游内核
git clone https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git
cd linux
git checkout v6.10  # 或更新版本

# 配置内核
make ARCH=arm64 defconfig
make ARCH=arm64 menuconfig

# 启用上述 CONFIG 选项

# 编译
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- modules
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- dtbs
```

## 设备树配置

### USB 控制器节点

```dts
&usb_0 {
    status = "okay";

    dwc3@a600000 {
        compatible = "snps,dwc3";
        reg = <0 0x0a600000 0 0xcd00>;
        interrupts = <GIC_SPI 133 IRQ_TYPE_LEVEL_HIGH>;

        /* XHCI sideband 支持 */
        usb-role-switch;

        /* IOMMU 映射 */
        iommus = <&apps_smmu 0x0 0x0>;

        /* 音频 offload 支持 */
        #sound-dai-cells = <1>;
    };
};
```

### Q6 USB 节点

```dts
&q6apm {
    q6usb: usb {
        compatible = "qcom,q6usb";
        #sound-dai-cells = <1>;

        /* 连接到 USB 控制器 */
        usb-controller = <&usb_0_dwc3>;
    };
};
```

### 声卡节点

```dts
sound {
    compatible = "qcom,sm8550-sndcard";
    model = "SM8550-USB-Offload";

    /* USB Offload Backend DAI */
    dai-link-usb-be {
        link-name = "USB Playback";
        cpu {
            sound-dai = <&q6usb USB_RX>;
        };
        platform {
            sound-dai = <&q6apm>;
        };
        codec {
            sound-dai = <&usb_0_dwc3 0>;
        };
    };
};
```

## 驱动加载顺序

正确的驱动加载顺序至关重要：

```bash
# 1. XHCI 和 sideband 支持
modprobe xhci-hcd
modprobe xhci-plat-hcd

# 2. USB Audio 基础驱动
modprobe snd-usb-audio

# 3. Q6 核心驱动
modprobe q6apm
modprobe q6afe

# 4. Q6 USB 驱动
modprobe q6usb

# 5. QC Audio Offload 驱动
modprobe qc-usb-audio-offload

# 验证加载
lsmod | grep -E "xhci|usb.*audio|q6"
```

## 源码分析

### qc_audio_offload.c 关键函数

```c
/* QMI 请求处理 */
static void handle_uaudio_stream_req(struct qmi_handle *handle,
                                     struct sockaddr_qrtr *sq,
                                     struct qmi_txn *txn,
                                     const void *decoded)
{
    struct uaudio_qmi_svc *svc = container_of(handle, struct uaudio_qmi_svc, handle);
    struct qmi_uaudio_stream_req_msg_v01 *req_msg;
    struct qmi_uaudio_stream_resp_msg_v01 resp = {0};

    req_msg = (struct qmi_uaudio_stream_req_msg_v01 *)decoded;

    /* 启用音频流 */
    if (req_msg->enable) {
        ret = enable_audio_stream(svc, req_msg, &resp);
    } else {
        ret = disable_audio_stream(svc, req_msg);
    }

    /* 发送 QMI 响应 */
    qmi_send_response(handle, sq, txn,
                      QMI_UAUDIO_STREAM_RESP_V01,
                      sizeof(resp), &resp);
}

/* 启用音频流 */
static int enable_audio_stream(struct uaudio_qmi_svc *svc,
                               struct qmi_uaudio_stream_req_msg_v01 *req,
                               struct qmi_uaudio_stream_resp_msg_v01 *resp)
{
    struct snd_usb_substream *subs;
    struct xhci_sideband *sb;
    struct xhci_ring *tr, *er;
    dma_addr_t tr_dma, er_dma, xfer_buf_dma;
    int ret;

    /* 获取 USB substream */
    subs = find_usb_substream(req->usb_token, req->pcm_dev_num);

    /* 注册 sideband */
    sb = xhci_sideband_register(subs->dev);
    if (IS_ERR(sb))
        return PTR_ERR(sb);

    /* 添加 endpoint */
    ret = xhci_sideband_add_endpoint(sb, subs->ep);
    if (ret)
        goto err_unregister;

    /* 获取 transfer ring */
    tr = xhci_sideband_get_transfer_ring(sb, subs->ep);
    tr_dma = xhci_sideband_get_ring_dma(tr);

    /* 获取 event ring */
    er = xhci_sideband_get_event_ring(sb);
    er_dma = xhci_sideband_get_ring_dma(er);

    /* 分配 transfer buffer */
    xfer_buf_dma = uaudio_alloc_xfer_buffer(req->xfer_buff_size);

    /* 映射到 ADSP IOVA 空间 */
    ret = uaudio_iommu_map(svc, tr_dma, er_dma, xfer_buf_dma, resp);
    if (ret)
        goto err_free_buf;

    /* 准备 QMI 响应 */
    prepare_qmi_response(resp, tr_dma, er_dma, xfer_buf_dma,
                        req->xfer_buff_size);

    return 0;

err_free_buf:
    uaudio_free_xfer_buffer(xfer_buf_dma);
err_unregister:
    xhci_sideband_unregister(sb);
    return ret;
}

/* 准备 QMI 响应 */
static void prepare_qmi_response(struct qmi_uaudio_stream_resp_msg_v01 *resp,
                                 dma_addr_t tr_dma, dma_addr_t er_dma,
                                 dma_addr_t xfer_buf_dma, u32 xfer_buf_size)
{
    /* Transfer Ring 信息 */
    resp->xhci_mem_info.tr_data.pa = tr_dma;
    resp->xhci_mem_info.tr_data.size = XHCI_RING_SIZE;

    /* Event Ring 信息 */
    resp->xhci_mem_info.evt_ring.pa = er_dma;
    resp->xhci_mem_info.evt_ring.size = XHCI_RING_SIZE;

    /* Transfer Buffer 信息 */
    resp->xhci_mem_info.xfer_buff.pa = xfer_buf_dma;
    resp->xhci_mem_info.xfer_buff.size = xfer_buf_size;

    /* Interrupter 编号 */
    resp->interrupter_num = XHCI_SIDEBAND_INTERRUPTER;

    /* USB 速度信息 */
    resp->speed_info = USB_SPEED_HIGH;  // 或 USB_SPEED_SUPER

    /* Slot ID */
    resp->slot_id = usb_device_slot_id;

    resp->status = QMI_RESULT_SUCCESS_V01;
}
```

### IOVA 地址空间定义

从源码中的宏定义：

```c
/* IOVA 基地址 */
#define IOVA_BASE                   0x1000

/* Transfer Ring IOVA 范围 */
#define IOVA_XFER_RING_BASE         (IOVA_BASE + 0x1000)
#define IOVA_XFER_RING_MAX          (IOVA_XFER_RING_BASE + 0x10000)

/* Event Ring IOVA 范围 */
#define IOVA_EVT_RING_BASE          (IOVA_XFER_RING_MAX)
#define IOVA_EVT_RING_MAX           (IOVA_EVT_RING_BASE + 0x10000)

/* Transfer Buffer IOVA 范围 */
#define IOVA_XFER_BUF_BASE          (IOVA_EVT_RING_MAX)
#define IOVA_XFER_BUF_MAX           (IOVA_XFER_BUF_BASE + 0x100000)

/* IOMMU 映射函数 */
static int uaudio_iommu_map(struct uaudio_qmi_svc *svc,
                            dma_addr_t tr_dma, dma_addr_t er_dma,
                            dma_addr_t xfer_buf_dma,
                            struct qmi_uaudio_stream_resp_msg_v01 *resp)
{
    struct iommu_domain *domain = svc->domain;
    int ret;

    /* 映射 Transfer Ring */
    ret = iommu_map(domain, IOVA_XFER_RING_BASE, tr_dma,
                    XHCI_RING_SIZE, IOMMU_READ | IOMMU_WRITE);
    if (ret)
        return ret;

    /* 映射 Event Ring */
    ret = iommu_map(domain, IOVA_EVT_RING_BASE, er_dma,
                    XHCI_RING_SIZE, IOMMU_READ | IOMMU_WRITE);
    if (ret)
        goto unmap_tr;

    /* 映射 Transfer Buffer */
    ret = iommu_map(domain, IOVA_XFER_BUF_BASE, xfer_buf_dma,
                    xfer_buf_size, IOMMU_READ | IOMMU_WRITE);
    if (ret)
        goto unmap_er;

    /* 更新响应中的 IOVA 地址 */
    resp->xhci_mem_info.tr_data.va = IOVA_XFER_RING_BASE;
    resp->xhci_mem_info.evt_ring.va = IOVA_EVT_RING_BASE;
    resp->xhci_mem_info.xfer_buff.va = IOVA_XFER_BUF_BASE;

    return 0;

unmap_er:
    iommu_unmap(domain, IOVA_EVT_RING_BASE, XHCI_RING_SIZE);
unmap_tr:
    iommu_unmap(domain, IOVA_XFER_RING_BASE, XHCI_RING_SIZE);
    return ret;
}
```

## 上游限制与变通方案

### 限制 1：AFE 方向被封闭

**问题描述**
- q6afe-dai.c 中虽然定义了 USB_RX port 和 q6afe_usb_ops
- 但上游代码已将 AFE 方向的 USB offload 路径封闭
- 无法通过 AFE 层直接访问 USB 设备

**源码证据**
```c
/* sound/soc/qcom/qdsp6/q6afe-dai.c */
static const struct snd_soc_dai_ops q6afe_usb_ops = {
    .prepare = q6afe_dai_prepare,
    .shutdown = q6afe_dai_shutdown,
    /* 注意：缺少 hw_params 等关键操作 */
};

/* USB_RX port 定义存在，但功能不完整 */
static struct snd_soc_dai_driver q6afe_dais[] = {
    /* ... */
    {
        .playback = {
            .stream_name = "USB Playback",
            .rates = SNDRV_PCM_RATE_8000_192000,
            .formats = SNDRV_PCM_FMTBIT_S16_LE | SNDRV_PCM_FMTBIT_S24_LE,
            .channels_min = 1,
            .channels_max = 2,
            .rate_min = 8000,
            .rate_max = 192000,
        },
        .id = USB_RX,
        .ops = &q6afe_usb_ops,
        /* 但实际功能未实现 */
    },
    /* ... */
};
```

**变通方案**
- 使用 qc_audio_offload.c 提供的 QMI + Sideband 路径
- 不依赖 AFE 层，直接通过 XHCI sideband 访问
- 这是上游推荐的实现方式

### 限制 2：需要 ADSP 固件支持

**问题描述**
- ADSP 固件必须支持 QMI UAUDIO_STREAM service
- 固件必须能够直接操作 XHCI transfer ring
- 需要特定版本的 AudioReach 固件

**检查方法**
```bash
# 检查 ADSP 固件版本
cat /sys/class/remoteproc/remoteproc0/firmware

# 检查 QMI 服务
cat /sys/kernel/debug/qmi/services | grep UAUDIO

# 应该看到：
# Service: 0x41 (UAUDIO_STREAM_SERVICE_ID_V01)
```

**解决方案**
- 使用 Qualcomm 提供的最新 ADSP 固件
- 确保固件包含 USB offload 支持
- 联系 SoC 供应商获取固件更新

### 限制 3：XHCI 控制器要求

**问题描述**
- 需要 XHCI 控制器支持 sideband 接口
- 不是所有 XHCI 控制器都支持此功能
- 需要特定的硬件配置

**检查方法**
```bash
# 检查 XHCI 版本
cat /sys/kernel/debug/usb/xhci/*/registers | grep "Version"

# 检查 sideband 支持
dmesg | grep -i "xhci.*sideband"

# 应该看到：
# xhci-hcd: XHCI sideband interface registered
```

**硬件要求**
- XHCI 1.1 或更高版本
- 支持多个 interrupter（至少 2 个）
- 支持 DMA 到 ADSP 内存域

## 验证步骤

### 步骤 1：检查驱动加载

```bash
# 检查所有相关模块
lsmod | grep -E "xhci|snd_usb|q6usb|qc_audio"

# 应该看到：
# xhci_plat_hcd
# xhci_hcd
# snd_usb_audio
# q6usb
# qc_usb_audio_offload

# 检查设备节点
ls -l /dev/snd/
# 应该看到 USB 音频设备
```

### 步骤 2：检查 Sideband 注册

```bash
# 检查 sideband 状态
dmesg | grep -i sideband

# 期望输出：
# xhci-hcd: sideband interface registered
# qc-usb-audio-offload: sideband registered for device X

# 检查 debugfs
cat /sys/kernel/debug/usb/xhci/*/sideband_status
```

### 步骤 3：检查 QMI 服务

```bash
# 检查 QMI 服务列表
cat /sys/kernel/debug/qmi/services

# 应该看到：
# Service: 0x41 Version: 1.0 Instance: 1
# Name: UAUDIO_STREAM_SERVICE

# 检查 QMI 连接
cat /sys/kernel/debug/qmi/connections | grep UAUDIO
```

### 步骤 4：检查 IOMMU 映射

```bash
# 检查 IOMMU 域
cat /sys/kernel/debug/iommu/domains

# 检查 USB 相关的 IOMMU 映射
cat /sys/kernel/debug/iommu/*/mappings | grep -A 5 "usb\|audio"

# 检查 SMMU 状态
dmesg | grep -i "smmu.*usb\|smmu.*audio"
```

### 步骤 5：测试音频播放

```bash
# 插入 USB 音频设备
# 检查设备识别
lsusb | grep -i audio
aplay -l

# 播放测试音频
speaker-test -D hw:X,0 -c 2 -r 48000 -F S16_LE -t sine -f 440

# 监控日志
dmesg -w | grep -E "usb|audio|q6|qmi"
```

## 调试技巧

### 启用详细日志

```bash
# 启用所有相关模块的调试日志
echo 'module xhci_hcd +p' > /sys/kernel/debug/dynamic_debug/control
echo 'module xhci_plat_hcd +p' > /sys/kernel/debug/dynamic_debug/control
echo 'module snd_usb_audio +p' > /sys/kernel/debug/dynamic_debug/control
echo 'module q6usb +p' > /sys/kernel/debug/dynamic_debug/control
echo 'module qc_usb_audio_offload +p' > /sys/kernel/debug/dynamic_debug/control
echo 'module q6afe +p' > /sys/kernel/debug/dynamic_debug/control

# 提高日志级别
echo 8 > /proc/sys/kernel/printk

# 实时查看日志
dmesg -w
```

### 关键日志关键字

从源码中的 dev_err/dev_dbg 提取的关键字：

```bash
# XHCI Sideband
dmesg | grep -i "sideband register\|sideband add endpoint\|sideband interrupter"

# QMI
dmesg | grep -i "qmi.*uaudio\|qmi.*stream\|qmi service"

# IOMMU
dmesg | grep -i "iommu map\|iommu unmap\|smmu fault"

# USB Offload
dmesg | grep -i "offload probe\|offload enable\|offload stream"

# Transfer Ring
dmesg | grep -i "transfer ring\|event ring\|xfer buf"
```

### 常见错误及解决

**错误 1：sideband register failed**
```
原因：XHCI 控制器不支持 sideband
解决：检查硬件是否支持，更新设备树配置
```

**错误 2：QMI service not found**
```
原因：ADSP 固件未加载或不支持 USB offload
解决：检查 ADSP 状态，更新固件
```

**错误 3：IOMMU mapping failed**
```
原因：IOMMU 配置错误或内存不足
解决：检查设备树 IOMMU 配置，增加 IOVA 空间
```

**错误 4：USB device not recognized**
```
原因：USB 驱动加载顺序错误
解决：按正确顺序重新加载驱动
```

## 上游可用功能

以下功能在上游内核中已经可用：

✅ XHCI sideband 接口
✅ QMI 通信框架
✅ IOMMU 映射管理
✅ USB Audio Class 2.0 基础支持
✅ Q6 USB ASoC component
✅ QC Audio Offload auxiliary driver

## 需要额外工作的部分

以下功能需要额外开发或配置：

❌ ADSP 固件（需要 Qualcomm 提供）
❌ AudioReach topology 配置
❌ 完整的 HAL 层实现
❌ 用户空间音频服务集成
❌ 设备树完整配置
❌ 平台特定的 IOMMU 配置

## 总结

上游 Linux 内核的 USB Audio Offload 实现与早期文档描述存在显著差异：

1. **不使用 AFE 层**：上游实现通过 QMI + XHCI Sideband 直接访问，绕过 AFE
2. **依赖 XHCI Sideband**：这是 Intel 贡献的关键接口，允许 ADSP 直接操作 XHCI
3. **IOMMU 映射关键**：通过 IOMMU 将 XHCI 内存映射到 ADSP 可访问空间
4. **QMI 协议核心**：ADSP 通过 QMI 请求获取 XHCI 内存地址和配置信息

实现时必须基于真实的上游源码架构，而不是假设的 AFE 路径。

## 参考资源

- Linux Kernel Source: `sound/soc/qcom/qdsp6/q6usb.c`
- Linux Kernel Source: `sound/usb/qcom/qc_audio_offload.c`
- Linux Kernel Source: `drivers/usb/host/xhci-sideband.c`
- USB Audio Class 2.0 Specification
- XHCI Specification 1.1+
