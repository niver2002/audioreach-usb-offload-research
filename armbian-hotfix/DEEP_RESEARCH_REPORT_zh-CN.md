# Q6A USB Offload 深度验证报告（Armbian + Patch/Hotfix）

## 1) 最终结论（代码约束交集）
- USB offload 最终最大输出：24-bit / 192000 Hz / 2ch
- 可实现“任意频率输入 + 最高质量升频输出”：输入任意率 -> PipeWire/ALSA 重采样 -> 固定 S24_LE/192000/2ch 输出

## 2) 证据链（源码行号）

### 2.1 USB Backend DAI 约束
文件：armbian-hotfix/_apply-check3/sound/soc/qcom/qdsp6/q6usb.c
- rates 到 192000
- formats 仅到 16/24bit（无 32bit）
- channels_max=2
证据：q6usb.c:100-112

### 2.2 AFE USB 配置约束
文件：audioreach-usb-offload-research/source-reference/kernel/qdsp6/q6afe.c
- sample_rate 支持到 AFE_PORT_SAMPLE_RATE_192K
- bit_width 支持值仅 16,24
- num_channels 支持值仅 1,2
证据：q6afe.c:529-550

### 2.3 APM 前端播放约束
文件：audioreach-usb-offload-research/source-reference/kernel/qdsp6/q6apm-dai.c
- playback formats: S16_LE | S24_LE
- playback rates: SNDRV_PCM_RATE_8000_192000
证据：q6apm-dai.c:111-116

### 2.4 QMI 层可到 U32，但被上游 DAI 截断
文件：audioreach-usb-offload-research/upstream-src/sound/usb/qcom/qc_audio_offload.c
- 枚举到 USB_QMI_PCM_FORMAT_U32_LE/U32_BE
- 也可映射到 SNDRV_PCM_FORMAT_U32_*
证据：qc_audio_offload.c:158-175,295-330,1558-1561

结论：QMI 支持 32bit 不等于链路可达 32bit，最终仍受 q6usb DAI 限制。

## 3) q6a 落地补丁（可应用）
目录：armbian-hotfix/patches

- 0001：新增 AudioReach USB module/media-format 下发路径
  关键：0001...patch:22-73,82-85
- 0002：q6apm-lpass-dais 增加 q6usb_hw_params + cfg.q6usb_ops 绑定
  关键：0002...patch:9-34,43-48,57
- 0003：AFE USB 端口缺失时允许 fallback，保留 QMI/xHCI sideband 路径
  关键：0003...patch:10-17
- 0004：DTS 增加 q6usb 节点与 usb-dai-link（q6apmbedai USB_RX -> q6usb USB_RX）
  关键：0004...patch:9-17,27-41
- 0005：topology 增加 USB module ID 处理
  关键：0005...patch:8-11

## 4) 补丁验证
- 已在 armbian-hotfix/_apply-check3 对 0001..0005 执行 git apply --check
- 结果：5/5 通过
- 另外已去除 5 个 patch 文件 UTF-8 BOM，避免解析歧义

## 5) Armbian 构建与运行设置

### 5.1 内核补丁
sudo ./armbian-hotfix/apply-kernel-hotfix.sh <armbian_kernel_source_dir>

### 5.2 运行时升频与 offload
sudo ./armbian-hotfix/runtime/setup-runtime-hotfix.sh

该脚本写入：
- ALSA 端点 q6a_usb_offload_raw -> hw:card,dev
- ALSA 升频端点 q6a_usb_offload_192k：format S24_LE, rate 192000, channels 2
- PipeWire：default.clock.rate=192000, allowed-rates 覆盖常见输入率, resample.quality=14
证据：setup-runtime-hotfix.sh:26-40,51-59

## 6) 输入端点与链路

### 6.1 本机播放输入
应用/播放器 -> PipeWire/ALSA -> q6a_usb_offload_192k -> q6usb -> USB DAC

### 6.2 外部 QPlay/DLNA 输入
sudo ./armbian-hotfix/runtime/setup-dlna-offload.sh
- gmediarender 输出到 alsasink device=q6a_usb_offload_192k
证据：setup-dlna-offload.sh:20

## 7) 蓝牙输入（aptX HD / LDAC）链路与 offload 边界

### 7.1 已实现
sudo ./armbian-hotfix/runtime/setup-bluetooth-codecs.sh
- WirePlumber 开启 codecs: aptx_hd, ldac
- BlueZ Experimental=true
证据：setup-bluetooth-codecs.sh:10-19

链路：BT A2DP（编解码在用户态）-> PipeWire -> q6a_usb_offload_192k -> USB offload 输出

### 7.2 不可达边界（当前开源主线）
“蓝牙解码 + 升频 + USB 输出全链路 DSP/hardware offload”无完整可验证实现。
本交付是：蓝牙用户态编解码 + USB 输出段 offload（q6usb/QMI/xHCI sideband）。

## 8) 控制点与验收
- 端点发现：/proc/asound/pcm
- 硬件参数：aplay --dump-hw-params -D hw:X,Y
- 内核日志：dmesg | grep -E 'q6usb|qc_audio_offload|sideband'
- 统一验证脚本：armbian-hotfix/runtime/verify-q6a-offload-chain.sh

## 9) 范围声明
本次已完成：源码级核验 + 补丁重建 + apply-check + 运行脚本落地。
本次未完成：真实 Q6A 硬件上的端到端实机播放验证（当前环境不可接入目标硬件）。