# QMI 处理机制技术文档

## 概述

QMI (Qualcomm MSM Interface) 是高通平台上用于应用处理器（AP）与调制解调器/ADSP 之间通信的协议。在 USB Audio Offload 场景中，QMI 用于在内核驱动和 ADSP 之间传递音频配置和控制消息。

## QMI 架构

### 组件层次
```
用户空间
    ↓
内核驱动 (q6usb.c)
    ↓
QMI 内核框架
    ↓
SMD/GLINK 传输层
    ↓
ADSP QMI 服务
```

## QMI 服务初始化

### 服务注册
在 q6usb_probe() 中初始化 QMI 句柄，注册消息处理器。

### 服务发现
等待 ADSP 服务上线，通过 qmi_add_lookup 发现服务。

## QMI 消息类型

### 1. Stream Request (流请求)
用于启动或停止音频流。

**关键字段**：
- enable: 1=启动, 0=停止
- usb_token: USB 设备标识
- audio_format: 音频格式
- number_of_ch: 通道数
- bit_rate: 位率
- xfer_buff_size: 传输缓冲区大小

**处理流程**：
1. 验证请求参数
2. 配置或禁用 USB 音频
3. 准备并发送响应

### 2. Stream Indication (流指示)
ADSP 主动通知内核的消息。

**事件类型**：
- USB_AUDIO_DEV_CONNECT: 设备连接
- USB_AUDIO_DEV_DISCONNECT: 设备断开
- USB_AUDIO_DEV_SUSPEND: 设备挂起
- USB_AUDIO_DEV_RESUME: 设备恢复

### 3. Memory Map Request (内存映射请求)
用于在 ADSP 和 AP 之间共享内存。

**关键字段**：
- phys_addr: 物理地址
- size: 大小
- mem_pool_id: 内存池 ID
- property_flag: 属性标志

## QMI 响应处理

### 响应消息结构
包含基本响应类型和可选状态字段：
- resp.result: 结果码
- resp.error: 错误码
- status: 连接状态
- internal_status: 内部状态码

### 响应准备
根据操作结果设置响应字段，成功时设置 status，失败时设置 internal_status。

## 错误处理

### QMI 错误码
- QMI_ERR_NONE_V01: 无错误
- QMI_ERR_MALFORMED_MSG_V01: 消息格式错误
- QMI_ERR_NO_MEMORY_V01: 内存不足
- QMI_ERR_INTERNAL_V01: 内部错误
- QMI_ERR_INVALID_ID_V01: 无效 ID
- QMI_ERR_INCOMPATIBLE_STATE_V01: 状态不兼容
- QMI_ERR_NOT_SUPPORTED_V01: 不支持

### 超时处理
默认超时时间为 5000ms，超时后返回 -ETIMEDOUT。

### 重试机制
最多重试 3 次，每次重试间隔 100ms。

## 同步机制

### 互斥锁保护
使用 mutex 保护 QMI 操作，使用 spinlock 保护设备列表。

### 等待队列
使用 wait_queue 等待 QMI 服务就绪，超时时间 5000ms。

## 调试支持

### QMI 消息跟踪
```bash
# 启用 QMI 调试
echo 1 > /sys/kernel/debug/qmi/trace

# 查看 QMI 消息
cat /sys/kernel/debug/qmi/messages
```

### 内核日志
在关键路径添加调试日志，记录请求和响应信息。

## 性能优化

### 消息批处理
对于多个配置参数，尽可能在一个 QMI 消息中发送，减少往返次数。

### 异步处理
使用异步回调处理 QMI 响应，避免阻塞主线程。

## 最佳实践

1. **错误处理**：始终检查 QMI 响应的 result 和 error 字段
2. **超时设置**：根据操作复杂度设置合理的超时时间
3. **资源清理**：确保在错误路径上正确清理 QMI 事务
4. **并发控制**：使用适当的锁机制保护共享资源
5. **日志记录**：在关键路径添加调试日志，便于问题排查

## 常见问题

### Q: QMI 请求超时怎么办？
A: 检查 ADSP 是否正常运行，查看 ADSP 日志，考虑增加超时时间或实现重试机制。

### Q: 如何处理 QMI 服务断开？
A: 实现 QMI 服务的 new_server 和 del_server 回调，在服务恢复时重新初始化连接。

### Q: QMI 消息编码失败？
A: 检查消息结构定义是否与 IDL 文件一致，确保所有必需字段都已填充。
