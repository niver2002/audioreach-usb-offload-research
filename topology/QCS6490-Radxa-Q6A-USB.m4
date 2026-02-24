dnl AudioReach Topology: QCS6490 Radxa Q6A USB Audio Offload
include(`audioreach/module_usb.m4`)

<graph>
    graph_id 0x0001
    name USB_PLAYBACK_GRAPH
    
    <subgraph>
        subgraph_id 0x0101
        name STREAM_USB_PB
        
        <container>
            container_id 0x1001
            name STREAM_USB_PB_CNT
            priority 0
            
            AR_MODULE_WR_SHARED_MEM_EP(0x0001)
            AR_MODULE_PCM_DECODER(0x0002, 2, 48000, 16)
            AR_MODULE_DYNAMIC_RESAMPLER(0x0003, 48000, 48000)
            AR_MODULE_GAIN(0x0004, 0.0)
            
            AR_USB_CONNECTION(0x0001, 1, 0x0002, 1)
            AR_USB_CONNECTION(0x0002, 1, 0x0003, 1)
            AR_USB_CONNECTION(0x0003, 1, 0x0004, 1)
            
        </container>
    </subgraph>
    
    <subgraph>
        subgraph_id 0x0102
        name DEVICE_USB_PB
        
        <container>
            container_id 0x1002
            name DEVICE_USB_PB_CNT
            priority 2
            
            AR_MODULE_MFC(0x0005, 2, 2, 48000, 48000, 16, 16)
            AR_MODULE_USB_RX(0x0100, 2, 48000, 16)
            
            AR_USB_CONNECTION(0x0005, 1, 0x0100, 1)
            
        </container>
    </subgraph>
    
    AR_USB_CONNECTION(0x0004, 1, 0x0005, 1)
    
</graph>

<graph>
    graph_id 0x0002
    name USB_CAPTURE_GRAPH
    
    <subgraph>
        subgraph_id 0x0201
        name DEVICE_USB_CAP
        
        <container>
            container_id 0x2001
            name DEVICE_USB_CAP_CNT
            priority 2
            
            AR_MODULE_USB_TX(0x0200, 2, 48000, 16)
            AR_MODULE_MFC(0x0201, 2, 2, 48000, 48000, 16, 16)
            
            AR_USB_CONNECTION(0x0200, 1, 0x0201, 1)
            
        </container>
    </subgraph>
    
    <subgraph>
        subgraph_id 0x0202
        name STREAM_USB_CAP
        
        <container>
            container_id 0x2002
            name STREAM_USB_CAP_CNT
            priority 0
            
            AR_MODULE_GAIN(0x0202, 0.0)
            AR_MODULE_DYNAMIC_RESAMPLER(0x0203, 48000, 48000)
            AR_MODULE_PCM_ENCODER(0x0204, 2, 48000, 16)
            AR_MODULE_RD_SHARED_MEM_EP(0x0205)
            
            AR_USB_CONNECTION(0x0202, 1, 0x0203, 1)
            AR_USB_CONNECTION(0x0203, 1, 0x0204, 1)
            AR_USB_CONNECTION(0x0204, 1, 0x0205, 1)
            
        </container>
    </subgraph>
    
    AR_USB_CONNECTION(0x0201, 1, 0x0202, 1)
    
</graph>
