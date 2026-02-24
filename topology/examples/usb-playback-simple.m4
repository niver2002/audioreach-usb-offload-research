dnl ============================================================================
dnl Simple USB Playback Topology (No Resampler)
dnl ============================================================================
dnl
dnl 最简单的 USB 播放拓扑配置
dnl 数据流: APPS → WR_SHARED_MEM → PCM_DECODER → USB_RX
dnl
dnl 适用场景:
dnl   - USB 设备支持固定采样率 (48kHz)
dnl   - 不需要动态采样率转换
dnl   - 最低延迟要求
dnl
dnl ============================================================================

include(`audioreach/module_usb.m4`)

<graph>
    graph_id 0x0001
    name USB_PLAYBACK_SIMPLE
    
    <subgraph>
        subgraph_id 0x0101
        name USB_PB_SIMPLE
        
        <container>
            container_id 0x1001
            name USB_PB_SIMPLE_CNT
            priority 1
            
            dnl APPS 写入端点
            AR_MODULE_WR_SHARED_MEM_EP(0x0001)
            
            dnl PCM 解码器: 2ch, 48kHz, 16bit
            AR_MODULE_PCM_DECODER(0x0002, 2, 48000, 16)
            
            dnl USB 播放端点: Port 136
            AR_MODULE_USB_RX(0x0100, 2, 48000, 16)
            
            dnl 连接: WR_SHARED_MEM → PCM_DECODER → USB_RX
            AR_USB_CONNECTION(0x0001, 1, 0x0002, 1)
            AR_USB_CONNECTION(0x0002, 1, 0x0100, 1)
            
        </container>
    </subgraph>
    
</graph>
