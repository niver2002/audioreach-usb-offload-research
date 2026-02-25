# Radxa Q6A ADSP 固件反编译分析报告

## 固件信息

| 属性 | 值 |
|------|-----|
| 文件 | `qcom/qcs6490/radxa/dragon-q6a/adsp.mbn` |
| 来源 | `radxa-pkg/radxa-firmware` GitHub 仓库 |
| 大小 | 9,871,840 bytes (9.4 MB) |
| 格式 | ELF 32-bit LSB executable, QUALCOMM DSP6 |
| 提取字符串总数 | 68,680 |

---

## 核心结论

**Radxa Q6A 的 ADSP 固件是 AudioReach/GPR 固件，但内置了完整的 USB Audio Offload 支持。**

固件使用 GPR (不是 APR) 作为通信协议，但 USB 音频模块通过 QMI 独立通信，不依赖 APR 协议栈。

---

## 详细分析

### 1. 通信协议: GPR (非 APR)

| 协议 | 字符串数量 | 结论 |
|------|-----------|------|
| GPR | 496 | 主协议栈，大量 GPR 初始化/注册/通信代码 |
| APR | 5 | 仅 `@apr`、`aprm` 等残留，无 APR 协议处理代码 |

关键证据:
```
audio_main.c: ADSP: FAILED to init gpr with status %ld
apm.c: ADSP: APM INIT: Failed to register with GPR, result: 0x%8x
prm.c: ADSP: PRM INIT: Failed to register with GPR, result: 0x%8x
gpr_init_adsp_kernel_wrapper.c: GPR INIT START
```

初始化序列: `spf_framework_init` → `gpr init` → `APM register with GPR` → `PRM register with GPR`

**APR 协议处理器不存在于此固件中。** `@apr` 和 `aprm` 是无关的残留字符串。

### 2. USB Audio Offload: 完整支持

| 组件 | 字符串数量 | 状态 |
|------|-----------|------|
| USB 总计 | 290 | 完整 |
| usb_afe.c | 48 | 完整的 USB AFE 数据管道 |
| capi_usb.c | 40+ | 完整的 CAPI USB 模块 |
| usb_driver.c | 15+ | USB 驱动层 |
| usb_qdi_qmi.c | 15+ | QMI 通信层 |
| usb_xhcd.c | 1+ | XHCI 控制器驱动 |
| XHCI 内存 | 4 | transfer ring / event ring / xfer buffer |

USB 模块源文件清单:
```
usb_afe.c          - USB AFE 数据管道（isochronous 读写、时间戳、漂移补偿）
usb_driver.c       - USB 驱动层（媒体格式配置、接口配置）
usb_driver_ext.c   - USB 驱动扩展（打开/关闭/启动设备会话）
usb_main.c         - USB 主模块
usb_memory.c       - USB 内存管理
usb_interrupt.c    - USB 中断处理
usb_sync.c         - USB 同步机制
usb_log.c          - USB 日志
usb_dci.c          - USB 设备控制器接口
usb_xhcd.c         - XHCI 主机控制器驱动
usb_qdi.c          - QDI (QuRT Driver Invocation) 层
usb_qdi_qmi.c      - QMI 通信（uaudio stream req/resp）
usb_qdi_log.c      - QDI 日志
capi_usb.c         - CAPI USB 模块（AudioReach 模块接口）
```

### 3. USB 数据路径详解

从固件字符串重建的 USB offload 数据路径:

```
[内核] qc_audio_offload.c
    ↓ QMI: qmi_uaudio_stream_req_msg_v01
    ↓      qmi_uaudio_stream_resp_msg_v01
[ADSP] usb_qdi_qmi.c
    ↓ usb_qdi_qmi_send_req_sync / _async
    ↓ usb_qdi_qmi_ind_cb (indication callback)
[ADSP] usb_driver.c
    ↓ USB_Drv: Received interface config: usb_token, svc_interval
    ↓ USB_Drv: Received hw media format config: sample_rate, bit_width, num_channels
[ADSP] usb_afe.c
    ↓ usb_afe_pipe_enable
    ↓ usb_afe_isoc_write (playback) / usb_afe_isoc_read (capture)
    ↓ usb_afe_calculate_tick_offset
    ↓ usb_afe_timestamp_enq / _deq
[ADSP] usb_xhcd.c
    ↓ xhci_mem_info: evt_ring, tr_data, tr_sync, xfer_buff
[硬件] USB XHCI 控制器 transfer ring
```

### 4. QMI 通信: 完整

```
qmi_uaudio_stream_req_msg_v01   - 流请求消息
qmi_uaudio_stream_resp_msg_v01  - 流响应消息
qmi_client_error_type            - 错误类型
usb_qdi_qmi_init                 - QMI 初始化
usb_qdi_qmi_deinit               - QMI 去初始化
usb_qdi_qmi_send_req_sync       - 同步请求
usb_qdi_qmi_send_req_async      - 异步请求
usb_qdi_qmi_ind_cb              - 指示回调
usb_qdi_qmi_error_cb            - 错误回调
```

### 5. XHCI Sideband 内存映射

固件直接操作 XHCI 硬件:
```
xhci_mem_info evt_ring   - 事件环（ADSP 接收 USB 完成事件）
xhci_mem_info tr_data    - 数据传输环（isochronous 音频数据）
xhci_mem_info tr_sync    - 同步传输环
xhci_mem_info xfer_buff  - 传输缓冲区
```

### 6. AudioReach 框架: SPF/APM/GPR

```
spf_framework_init → READY to receive the cmds
APM register with GPR → APM thread launched successfully
PRM register with GPR → PRM is initialized
GEN_CNTR (GC) → register with GPR
SPL_CNTR (SC) → register with GPR
```

固件使用 AudioReach SPF (Signal Processing Framework)，所有服务通过 GPR 注册。

---

## 关键发现：USB Offload 不依赖 APR

**这是最重要的发现。**

USB Audio Offload 在 ADSP 固件中的通信路径是:

```
内核 ←→ ADSP 通信:
  音频图管理: GPR (adsp_apps glink channel)
  USB 设备控制: QMI (独立通道，不经过 APR 或 GPR)
```

USB offload 使用 QMI 协议与内核通信，QMI 是独立于 APR/GPR 的通信机制:
- `qc_audio_offload.c` (内核) 通过 QMI 发送 `UAUDIO_STREAM_REQ`
- `usb_qdi_qmi.c` (ADSP) 接收并处理请求
- XHCI sideband 内存地址通过 QMI 响应返回给 ADSP

**这意味着：即使内核使用 GPR/AudioReach 栈，USB offload 的 QMI 通道仍然可以工作。**

但问题在于：主线内核的 `qc_audio_offload.c` 通过 `snd_soc_usb_connect()` 通知 `q6usb.c`，而 `q6usb.c` 硬编码依赖 `q6afe.h`。这是内核侧的限制，不是固件侧的限制。

---

## 对方案的影响

### 方向 A（切换到 APR 栈）: 不可行

**固件不支持 APR 协议。** 固件中没有 APR 协议处理器，只有 GPR。
切换设备树到 APR 栈后，内核会尝试通过 `apr_audio_svc` glink channel 通信，
但 ADSP 固件只监听 `adsp_apps` channel (GPR)，APR 消息将无人处理。

### 方向 B（在 q6apm 中实现 USB offload）: 技术上可行

固件已经有完整的 USB offload 支持（capi_usb.c + usb_afe.c + QMI）。
缺失的只是内核侧的 q6apm → USB 桥接层。

需要的工作:
1. 在 `audioreach.h` 中添加 `MODULE_ID_USB_AUDIO_SINK/SOURCE`
2. 在 `q6apm-lpass-dais.c` 中添加 USB DAI
3. 在 `audioreach.c` 中实现 USB 模块参数配置
4. 将 `q6usb.c` 从 q6afe 依赖改为 q6apm 依赖（或创建新的桥接）
5. 复用 `qc_audio_offload.c` 的 QMI + XHCI sideband 逻辑

### 方向 E（新发现）: 仅修改 q6usb.c 的依赖

由于 USB offload 的实际数据通道是 QMI（不经过 APR 或 GPR），
理论上可以:
1. 保持 AudioReach/GPR 设备树不变
2. 修改 `q6usb.c` 去掉对 `q6afe.h` 的硬依赖
3. 让 `q6usb.c` 直接与 `soc-usb` 和 `qc_audio_offload` 交互
4. 在 `q6apm-lpass-dais.c` 中添加 USB DAI 定义
5. USB 音频图通过 GPR/APM 配置（使用 MODULE_ID_USB_AUDIO_SINK）

这是工程量最小的路径，因为 QMI 通道是独立的。

---

## 修正后的推荐路径

| 优先级 | 方向 | 可行性 | 工作量 | 说明 |
|--------|------|--------|--------|------|
| 1 | C: 标准 USB Audio | 立即可用 | 零 | snd-usb-audio + PipeWire |
| 2 | E: 修改 q6usb 依赖 | 高 | 中等 | 保持 GPR 栈，修改内核桥接 |
| 3 | B: q6apm 添加 USB | 可行 | 大 | 完整的 AudioReach USB 支持 |
| ~~4~~ | ~~A: 切换 APR 栈~~ | ~~不可行~~ | - | ~~固件不支持 APR~~ |
