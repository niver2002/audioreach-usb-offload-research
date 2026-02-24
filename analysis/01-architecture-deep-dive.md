# QCS6490 USB Audio Offload 架构深度分析

> 基于 Linux 上游内核源码 (v6.15+) 逐行验证，非推测性文档

## 1. 架构总览：两套并行的音频子系统

Linux 上游内核中，Qualcomm 音频子系统存在**两套完全独立的路径**：

| 维度 | Legacy AFE 路径 | AudioReach (APM) 路径 |
|------|----------------|----------------------|
| 协议 | APR (Asynchronous Packet Router) | GPR (Generic Packet Router) |
| 核心模块 | `q6afe.c` | `q6apm.c` + `audioreach.c` |
| DAI 驱动 | `q6afe-dai.c` | `q6apm-dai.c` |
| USB 支持 | **有** (完整实现) | **无** (零 USB 引用) |
| 拓扑管理 | 固定 AFE 模块 | 动态图 (topology.c) |
| 目标 SoC | SDM845 等旧平台 | SC7280/QCS6490 等新平台 |

**关键矛盾**：QCS6490 使用 AudioReach (GPR/APM) 架构，但 USB offload 代码全部挂在 Legacy AFE (APR) 路径上。

## 2. 源码级证据

### 2.1 q6afe.c — Legacy AFE，使用 APR 协议

```c
// source-reference/kernel/qdsp6/q6afe.c
#include <linux/soc/qcom/apr.h>    // APR 协议

struct q6afe {
    struct apr_device *apr;          // APR 设备句柄
    // ...
};

// 回调函数签名 — APR 回调
static int q6afe_callback(struct apr_device *adev,
                          const struct apr_resp_pkt *data)

// 发包函数 — 通过 APR 发送
static int afe_apr_send_pkt(struct q6afe *afe, struct apr_pkt *pkt, ...)
{
    ret = apr_send_pkt(afe->apr, pkt);
}
```

AFE 中的 USB 参数定义：
```c
#define AFE_PARAM_ID_USB_AUDIO_DEV_PARAMS    0x000102A5
#define AFE_PARAM_ID_USB_AUDIO_DEV_LPCM_FMT 0x000102AA
#define AFE_PARAM_ID_USB_AUDIO_CONFIG        0x000102A4
```

AFE 中的 USB 配置函数（完整实现）：
```c
// q6afe.c:1380-1440
static int q6afe_set_usb_cfg(struct q6afe_port *port, ...)
{
    // 设置 USB 设备参数
    ret = q6afe_port_set_param_v2(port, &usb_dev,
            AFE_PARAM_ID_USB_AUDIO_DEV_PARAMS, ...);
    // 设置 LPCM 格式
    ret = q6afe_port_set_param_v2(port, &lpcm_fmt,
            AFE_PARAM_ID_USB_AUDIO_DEV_LPCM_FMT, ...);
    // 设置服务间隔
    ret = q6afe_port_set_param_v2(port, &svc_int,
            AFE_PARAM_ID_USB_AUDIO_CONFIG, ...);
}
```

### 2.2 AudioReach (APM) — 零 USB 引用

验证方法：
```bash
$ grep -c "USB\|usb" q6apm.c q6apm-dai.c audioreach.c topology.c
q6apm.c:0
q6apm-dai.c:0
audioreach.c:0
topology.c:0
```

**四个 AudioReach 核心文件中，USB 出现次数为零。**

`q6apm.c` 使用 GPR 协议：
```c
// source-reference/kernel/qdsp6/q6apm.c
#include <linux/soc/qcom/apr.h>  // GPR 复用了 apr.h 头文件
// 但实际使用 GPR 命令：
#define APM_CMD_GRAPH_OPEN     0x01001000
#define APM_CMD_GRAPH_CLOSE    0x01001005
#define APM_CMD_SET_CFG        0x01001002
```

`q6apm-dai.c` 只支持 PCM 和 Compress：
```c
// q6apm-dai.c — 只有 PCM playback/capture 和 compressed offload
// 没有任何 USB backend DAI 定义
```

### 2.3 q6usb.c — USB offload 的 ASoC 桥接层

```c
// source-reference/kernel/qdsp6/q6usb.c
#include "q6afe.h"    // 依赖 AFE，不是 APM

static int q6usb_audio_port_start(...)
{
    q6afe_port_set_usb_cfg(q6usb->afe, ...);  // 调用 AFE 配置
    q6afe_port_start(q6usb->afe);              // 启动 AFE 端口
}

static int q6usb_hw_params(...)
{
    snd_soc_set_runtime_hwparams(substream, &q6usb_hw);
    // 通过 AFE 设置硬件参数
}
```

**q6usb.c 是 USB offload 的 ASoC component driver，它完全依赖 q6afe.h，不引用任何 AudioReach API。**

### 2.4 qc_audio_offload.c — USB 侧 class driver

这是 `sound/usb/qcom/` 下的 USB 侧驱动，负责：

1. **xhci-sideband**：获取 USB endpoint 的 transfer ring 和 event ring 物理地址
2. **IOMMU 映射**：将 USB DMA 地址映射到 ADSP 可访问的 IOVA 空间
3. **QMI 服务**：接收来自 ADSP 的 stream enable/disable 请求

```c
// qc_audio_offload.c 核心数据流：
//
// ADSP (AFE USB module)
//   |
//   | QMI request (stream enable)
//   v
// qc_audio_offload.c::handle_uaudio_stream_req()
//   |
//   |-- xhci_sideband_add_endpoint()     // 获取 USB EP 的 ring 地址
//   |-- xhci_sideband_create_interrupter() // 创建专用中断器
//   |-- uaudio_iommu_map_pa()            // IOMMU 映射给 ADSP
//   |-- prepare_qmi_response()           // 返回 IOVA 地址给 ADSP
//   v
// ADSP 直接 DMA 读写 USB transfer ring
```

关键结构体：
```c
struct uaudio_dev {
    struct xhci_sideband *sb;        // xHCI sideband 句柄
    struct snd_soc_usb_device *sdev; // SoC USB 设备
};

struct uaudio_qmi_svc {
    struct qmi_handle *uaudio_svc_hdl;  // QMI 服务句柄
    struct sockaddr_qrtr client_sq;      // ADSP 客户端地址
    bool client_connected;
};
```

## 3. 完整数据流路径

```
┌─────────────────────────────────────────────────────────────────┐
│                        用户空间                                  │
│  ALSA app → PCM write → /dev/snd/pcmCxDxp                      │
└──────────────────────────┬──────────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────────┐
│                     ASoC Framework                               │
│                                                                  │
│  q6apm-dai.c (FE)  ←──routing──→  q6usb.c (BE)                 │
│  [AudioReach PCM]                  [AFE USB port]                │
│                                                                  │
│  问题：q6apm-dai 使用 GPR/APM                                    │
│        q6usb 使用 APR/AFE                                        │
│        两者协议不兼容                                              │
└──────────────────────────┬──────────────────────────────────────┘
                           │ (如果能走通)
┌──────────────────────────▼──────────────────────────────────────┐
│                    q6afe.c (APR)                                  │
│  AFE_PORT_CMD_DEVICE_START → USB port                            │
│  AFE_PARAM_ID_USB_AUDIO_DEV_PARAMS                               │
│  AFE_PARAM_ID_USB_AUDIO_DEV_LPCM_FMT                            │
└──────────────────────────┬──────────────────────────────────────┘
                           │ APR → ADSP
┌──────────────────────────▼──────────────────────────────────────┐
│                    ADSP Firmware                                  │
│  AFE USB Module → QMI client                                     │
└──────────────────────────┬──────────────────────────────────────┘
                           │ QMI
┌──────────────────────────▼──────────────────────────────────────┐
│              qc_audio_offload.c (USB 侧)                         │
│  handle_uaudio_stream_req()                                      │
│    → xhci_sideband_add_endpoint()                                │
│    → uaudio_iommu_map_pa()                                       │
│    → QMI response (IOVA addresses)                               │
└──────────────────────────┬──────────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────────┐
│                    xHCI Controller                                │
│  ADSP 直接操作 USB transfer ring (DMA)                            │
│  → USB Audio Device                                              │
└─────────────────────────────────────────────────────────────────┘
```

## 4. QCS6490 上的核心矛盾

### 4.1 协议断层

QCS6490 的 ADSP 固件使用 **AudioReach (GPR/APM)** 架构：
- 设备树中配置的是 `qcom,q6apm` 节点
- 音频图通过 `APM_CMD_GRAPH_OPEN` 动态构建
- 不存在传统的 AFE service

但 USB offload 需要的是 **AFE (APR)** 服务：
- `q6usb.c` 调用 `q6afe_port_start()`
- AFE 通过 APR 协议与 ADSP 通信
- ADSP 固件中需要有 AFE service handler

**如果 QCS6490 的 ADSP 固件不包含 AFE service，APR 包发过去无人接收。**

### 4.2 固件依赖

USB offload 的 ADSP 侧需要：
1. AFE USB module（处理 USB 音频参数配置）
2. QMI client（向 `qc_audio_offload.c` 发送 stream request）
3. DMA engine（直接操作 USB transfer ring）

这些模块是否存在于 QCS6490 的 ADSP 固件中，**无法从内核源码确认**，需要：
- 检查实际固件文件 (`/lib/firmware/qcom/qcs6490/`)
- 或通过 APR/GPR 枚举 ADSP 上的可用服务

### 4.3 ASoC routing 问题

即使 AFE service 存在，还有 ASoC 层面的 routing 问题：

```
FE DAI (q6apm-dai) ←→ BE DAI (q6usb/q6afe-dai)
```

`q6apm-dai.c` 注册的 FE DAI 和 `q6afe-dai.c` 注册的 BE DAI 需要通过 DAPM routing 连接。
在 AudioReach 架构下，这个 routing 是否被正确配置，取决于 machine driver。

## 5. soc-usb.c — SoC USB 框架层

```c
// source-reference/kernel/soc/soc-usb.c
// 这是一个通用的 SoC-USB 桥接框架

struct snd_soc_usb {
    struct list_head list;
    struct device *dev;
    int (*connection_status_cb)(...);  // USB 连接状态回调
    void *priv;
};

// 当 USB 音频设备插入时通知 SoC 侧
int snd_soc_usb_connect(struct device *usbdev,
                        struct snd_soc_usb_device *sdev)
{
    // 遍历注册的 SoC USB handlers
    // 调用 connection_status_cb
}

// 当 USB 音频设备拔出时通知
void snd_soc_usb_disconnect(struct device *usbdev,
                            struct snd_soc_usb_device *sdev)
```

这个框架本身是协议无关的，但目前唯一的使用者 `q6usb.c` 绑定到了 AFE。

## 6. 结论

### 事实（源码验证）

1. **USB offload 内核驱动已完整上游化**：`q6usb.c`、`qc_audio_offload.c`、`soc-usb.c`、`xhci-sideband.c` 全部在 mainline
2. **USB offload 绑定在 AFE/APR 路径**：`q6usb.c` 只调用 `q6afe_*` API
3. **AudioReach 路径零 USB 支持**：`q6apm.c`、`q6apm-dai.c`、`audioreach.c`、`topology.c` 中无任何 USB 引用
4. **QCS6490 使用 AudioReach 架构**：GPR/APM 协议栈

### 推断（需要实机验证）

1. QCS6490 ADSP 固件**可能同时包含** AFE service 和 APM service（双栈共存）
2. 如果双栈共存，USB offload 可以通过 AFE 路径工作，与 AudioReach 的其他音频路径并行
3. 如果 ADSP 固件**只有** APM service，则 USB offload 在当前上游内核中**不可用**

### 验证方法

在实机上执行：
```bash
# 检查 APR/GPR 服务枚举
cat /sys/kernel/debug/remoteproc/remoteproc*/
dmesg | grep -i "apr\|gpr\|afe\|apm"

# 检查 AFE service 是否注册
ls /sys/bus/apr/devices/

# 检查 USB offload 模块是否加载
lsmod | grep -E "q6usb|qc_audio_offload|snd_soc_usb"
```
