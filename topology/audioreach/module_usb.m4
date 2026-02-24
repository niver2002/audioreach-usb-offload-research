dnl ============================================================================
dnl USB Audio Module Definitions for AudioReach
dnl ============================================================================
dnl
dnl 文件说明：
dnl   本文件定义了 AudioReach 拓扑中 USB Audio 相关的 M4 宏
dnl   用于构建 USB 音频播放和录制的硬件端点模块
dnl
dnl USB Audio 端口定义（基于 Linux 内核 dt-bindings）：
dnl   - USB_RX Port ID: 136 (USB Audio Playback - 播放到 USB 设备)
dnl   - USB_TX Port ID: 137 (USB Audio Capture - 从 USB 设备录制)
dnl
dnl AudioReach 模块 ID：
dnl   - WR_SHARED_MEM_EP: 0x07001000 (写入共享内存端点，APPS → DSP)
dnl   - RD_SHARED_MEM_EP: 0x07001001 (读取共享内存端点，DSP → APPS)
dnl   - CODEC_DMA/HW_EP: 0x07001015 (通用硬件端点模块)
dnl   - HW_EP_POWER_MODE: 0x0700105A (硬件端点电源模式)
dnl
dnl ============================================================================

dnl AR_MODULE_USB_RX - USB 播放硬件端点模块
dnl 参数: $1=instance_id, $2=channels, $3=rate, $4=width
define(`AR_MODULE_USB_RX',
`      <module>
          module_id 0x07001015
          instance_id $1
          max_in_ports 1
          max_out_ports 0
          <hw_ep_config>
              port_id 136
              direction 0
              num_channels ifelse($2,,2,$2)
              sample_rate ifelse($3,,48000,$3)
              bit_width ifelse($4,,16,$4)
              data_format 1
          </hw_ep_config>
      </module>')

dnl AR_MODULE_USB_TX - USB 录制硬件端点模块
dnl 参数: $1=instance_id, $2=channels, $3=rate, $4=width
define(`AR_MODULE_USB_TX',
`      <module>
          module_id 0x07001015
          instance_id $1
          max_in_ports 0
          max_out_ports 1
          <hw_ep_config>
              port_id 137
              direction 1
              num_channels ifelse($2,,2,$2)
              sample_rate ifelse($3,,48000,$3)
              bit_width ifelse($4,,16,$4)
              data_format 1
          </hw_ep_config>
      </module>')

dnl AR_MODULE_WR_SHARED_MEM_EP - APPS 写入共享内存端点
dnl 参数: $1=instance_id
define(`AR_MODULE_WR_SHARED_MEM_EP',
`      <module>
          module_id 0x07001000
          instance_id $1
          max_in_ports 0
          max_out_ports 1
      </module>')

dnl AR_MODULE_RD_SHARED_MEM_EP - APPS 读取共享内存端点
dnl 参数: $1=instance_id
define(`AR_MODULE_RD_SHARED_MEM_EP',
`      <module>
          module_id 0x07001001
          instance_id $1
          max_in_ports 1
          max_out_ports 0
      </module>')

dnl AR_MODULE_PCM_DECODER - PCM 解码器模块
dnl 参数: $1=instance_id, $2=channels, $3=rate, $4=width
define(`AR_MODULE_PCM_DECODER',
`      <module>
          module_id 0x07001005
          instance_id $1
          max_in_ports 1
          max_out_ports 1
          <pcm_config>
              num_channels ifelse($2,,2,$2)
              sample_rate ifelse($3,,48000,$3)
              bit_width ifelse($4,,16,$4)
              alignment 1
              endianness 0
          </pcm_config>
      </module>')

dnl AR_MODULE_PCM_ENCODER - PCM 编码器模块
dnl 参数: $1=instance_id, $2=channels, $3=rate, $4=width
define(`AR_MODULE_PCM_ENCODER',
`      <module>
          module_id 0x07001006
          instance_id $1
          max_in_ports 1
          max_out_ports 1
          <pcm_config>
              num_channels ifelse($2,,2,$2)
              sample_rate ifelse($3,,48000,$3)
              bit_width ifelse($4,,16,$4)
              alignment 1
              endianness 0
          </pcm_config>
      </module>')

dnl AR_MODULE_DYNAMIC_RESAMPLER - 动态重采样器模块
dnl 参数: $1=instance_id, $2=input_rate, $3=output_rate
define(`AR_MODULE_DYNAMIC_RESAMPLER',
`      <module>
          module_id 0x07001016
          instance_id $1
          max_in_ports 1
          max_out_ports 1
          <resampler_config>
              input_sample_rate ifelse($2,,48000,$2)
              output_sample_rate ifelse($3,,48000,$3)
              quality 2
          </resampler_config>
      </module>')

dnl AR_MODULE_GAIN - 增益控制模块
dnl 参数: $1=instance_id, $2=gain_db
define(`AR_MODULE_GAIN',
`      <module>
          module_id 0x07001026
          instance_id $1
          max_in_ports 1
          max_out_ports 1
          <gain_config>
              gain_db ifelse($2,,0.0,$2)
          </gain_config>
      </module>')

dnl AR_MODULE_MFC - 多格式转换器模块
dnl 参数: $1=iid, $2=in_ch, $3=out_ch, $4=in_rate, $5=out_rate, $6=in_width, $7=out_width
define(`AR_MODULE_MFC',
`      <module>
          module_id 0x07001015
          instance_id $1
          max_in_ports 1
          max_out_ports 1
          <mfc_config>
              input_channels ifelse($2,,2,$2)
              output_channels ifelse($3,,2,$3)
              input_sample_rate ifelse($4,,48000,$4)
              output_sample_rate ifelse($5,,48000,$5)
              input_bit_width ifelse($6,,16,$6)
              output_bit_width ifelse($7,,16,$7)
          </mfc_config>
      </module>')

dnl AR_USB_CONNECTION - 模块间连接宏
dnl 参数: $1=src_iid, $2=src_port, $3=dst_iid, $4=dst_port
define(`AR_USB_CONNECTION',
`      <connection>
          src_module_instance_id $1
          src_port_id ifelse($2,,1,$2)
          dst_module_instance_id $3
          dst_port_id ifelse($4,,1,$4)
      </connection>')
