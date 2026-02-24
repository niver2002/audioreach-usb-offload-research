dnl ============================================================================
dnl USB Playback Topology with Dynamic Resampler
dnl ============================================================================
dnl
dnl 带动态重采样器的 USB 播放拓扑配置
dnl 数据流: APPS → WR_SHARED_MEM → PCM_DEC → RESAMPLER → GAIN → MFC → USB_RX
dnl
dnl 适用场景:
dnl   - USB 设备支持多种采样率
dnl   - 需要运行时动态切换采样率
dnl   - 需要音量控制
dnl   - 需要格式转换
dnl
dnl 支持的采样率:
dnl   - 8000, 16000, 32000, 44100, 48000, 96000, 192000 Hz
dnl
dnl ============================================================================

include(`audioreach/module_usb.m4`)

<graph>
    graph_id 0x0001
    name USB_PLAYBACK_RESAMPLER
    
    dnl ------------------------------------------------------------------------
    dnl Subgraph 1: Stream Processing
    dnl ------------------------------------------------------------------------
    <subgraph>
        subgraph_id 0x0101
        name STREAM_PROCESSING
        
        <container>
            container_id 0x1001
            name STREAM_CNT
            priority 0
            
            dnl Module 1: APPS 写入端点
            AR_MODULE_WR_SHARED_MEM_EP(0x0001)
            
            dnl Module 2: PCM 解码器 (2ch, 48kHz, 16bit)
            AR_MODULE_PCM_DECODER(0x0002, 2, 48000, 16)
            
            dnl Module 3: 动态重采样器 (48kHz → 48kHz, 可运行时调整)
            AR_MODULE_DYNAMIC_RESAMPLER(0x0003, 48000, 48000)
            
            dnl Module 4: 增益控制 (0dB)
            AR_MODULE_GAIN(0x0004, 0.0)
            
            dnl 连接
            AR_USB_CONNECTION(0x0001, 1, 0x0002, 1)
            AR_USB_CONNECTION(0x0002, 1, 0x0003, 1)
            AR_USB_CONNECTION(0x0003, 1, 0x0004, 1)
            
        </container>
    </subgraph>
    
    dnl ------------------------------------------------------------------------
    dnl Subgraph 2: Device Endpoint
    dnl ------------------------------------------------------------------------
    <subgraph>
        subgraph_id 0x0102
        name DEVICE_ENDPOINT
        
        <container>
            container_id 0x1002
            name DEVICE_CNT
            priority 2
            
            dnl Module 5: 多格式转换器 (2ch→2ch, 48kHz→48kHz, 16bit→16bit)
            AR_MODULE_MFC(0x0005, 2, 2, 48000, 48000, 16, 16)
            
            dnl Module 6: USB 播放端点 (Port 136, 2ch, 48kHz, 16bit)
            AR_MODULE_USB_RX(0x0100, 2, 48000, 16)
            
            dnl 连接
            AR_USB_CONNECTION(0x0005, 1, 0x0100, 1)
            
        </container>
    </subgraph>
    
    dnl 跨子图连接
    AR_USB_CONNECTION(0x0004, 1, 0x0005, 1)
    
</graph>
