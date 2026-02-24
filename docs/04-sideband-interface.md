# Sideband 接口技术文档

## 概述

Sideband 接口是 USB Audio Offload 架构中的关键组件，它提供了一个旁路通道，允许 ADSP 直接访问 USB 主机控制器（xHCI）的资源，而无需通过应用处理器。这种设计显著降低了音频数据传输的延迟和功耗。

## 架构设计

### 组件关系
```
ADSP
  ↓
Sideband 接口
  ↓
xHCI 控制器
  ↓
USB 音频设备
```

### 核心文件
- **xhci-sideband.c**: xHCI sideband 接口实现
- **q6usb.c**: 使用 sideband 接口的客户端驱动

## Sideband 接口 API

### 1. 注册和注销

#### xhci_sideband_register()
注册一个 sideband 客户端。

**函数原型**：
```c
struct xhci_sideband *xhci_sideband_register(struct device *dev);
```

**参数**：
- dev: 客户端设备指针

**返回值**：
- 成功：sideband 句柄指针
- 失败：ERR_PTR(-errno)

**使用示例**：
```c
struct xhci_sideband *sb;

sb = xhci_sideband_register(&pdev->dev);
if (IS_ERR(sb)) {
    dev_err(&pdev->dev, "Failed to register sideband\n");
    return PTR_ERR(sb);
}
```

#### xhci_sideband_unregister()
注销 sideband 客户端。

**函数原型**：
```c
void xhci_sideband_unregister(struct xhci_sideband *sb);
```

### 2. 端点管理

#### xhci_sideband_add_endpoint()
添加一个端点到 sideband 管理。

**函数原型**：
```c
int xhci_sideband_add_endpoint(struct xhci_sideband *sb,
                               struct usb_host_endpoint *ep);
```

**参数**：
- sb: sideband 句柄
- ep: USB 端点描述符

**返回值**：
- 0: 成功
- 负值: 错误码

**功能**：
1. 验证端点类型（必须是同步端点）
2. 在 xHCI 中分配端点资源
3. 配置端点上下文
4. 将端点添加到 sideband 管理列表

#### xhci_sideband_remove_endpoint()
从 sideband 管理中移除端点。

**函数原型**：
```c
int xhci_sideband_remove_endpoint(struct xhci_sideband *sb,
                                  struct usb_host_endpoint *ep);
```

**功能**：
1. 停止端点传输
2. 释放端点资源
3. 从管理列表中移除

#### xhci_sideband_stop_endpoint()
停止端点传输。

**函数原型**：
```c
int xhci_sideband_stop_endpoint(struct xhci_sideband *sb,
                                struct usb_host_endpoint *ep);
```

**功能**：
1. 发送停止端点命令到 xHCI
2. 等待命令完成
3. 清理待处理的传输

### 3. 传输环管理

#### xhci_sideband_get_ring_info()
获取传输环信息。

**函数原型**：
```c
int xhci_sideband_get_ring_info(struct xhci_sideband *sb,
                                struct usb_host_endpoint *ep,
                                struct xhci_ring_info *info);
```

**ring_info 结构**：
```c
struct xhci_ring_info {
    dma_addr_t dma;           // 传输环 DMA 地址
    u32 size;                 // 环大小（TRB 数量）
    u32 cycle_state;          // 循环状态位
    u32 dequeue;              // 出队指针
    u32 enqueue;              // 入队指针
};
```

**用途**：
ADSP 需要这些信息来直接操作传输环，提交传输请求。

#### xhci_sideband_get_event_ring_info()
获取事件环信息。

**函数原型**：
```c
int xhci_sideband_get_event_ring_info(struct xhci_sideband *sb,
                                      struct xhci_ring_info *info);
```

**用途**：
ADSP 通过事件环接收传输完成通知。

### 4. 中断管理

#### xhci_sideband_setup_interrupter()
为 sideband 客户端设置中断器。

**函数原型**：
```c
int xhci_sideband_setup_interrupter(struct xhci_sideband *sb,
                                    int intr_num);
```

**参数**：
- sb: sideband 句柄
- intr_num: 中断器编号（通常使用辅助中断器）

**功能**：
1. 分配中断器资源
2. 配置中断器寄存器
3. 设置事件环

#### xhci_sideband_cleanup_interrupter()
清理中断器资源。

**函数原型**：
```c
void xhci_sideband_cleanup_interrupter(struct xhci_sideband *sb);
```

### 5. 门铃通知

#### xhci_sideband_ring_doorbell()
触发门铃寄存器，通知 xHCI 有新的传输请求。

**函数原型**：
```c
int xhci_sideband_ring_doorbell(struct xhci_sideband *sb,
                                u32 slot_id,
                                u32 ep_index);
```

**参数**：
- slot_id: USB 设备槽位 ID
- ep_index: 端点索引

**用途**：
ADSP 在提交 TRB 到传输环后，通过此接口通知 xHCI 处理。

## 工作流程

### 初始化流程

1. **客户端注册**
```c
// q6usb 驱动注册为 sideband 客户端
sb = xhci_sideband_register(&pdev->dev);
```

2. **中断器设置**
```c
// 设置辅助中断器（通常是中断器 1）
ret = xhci_sideband_setup_interrupter(sb, 1);
```

3. **获取事件环信息**
```c
struct xhci_ring_info event_ring_info;
ret = xhci_sideband_get_event_ring_info(sb, &event_ring_info);
// 将事件环信息通过 QMI 发送给 ADSP
```

### 音频流启动流程

1. **添加端点**
```c
// 为音频端点添加 sideband 管理
ret = xhci_sideband_add_endpoint(sb, ep);
```

2. **获取传输环信息**
```c
struct xhci_ring_info ring_info;
ret = xhci_sideband_get_ring_info(sb, ep, &ring_info);
// 将传输环信息通过 QMI 发送给 ADSP
```

3. **ADSP 直接操作**
- ADSP 直接写入 TRB 到传输环
- ADSP 通过 sideband 接口触发门铃
- xHCI 处理传输请求
- 传输完成事件写入事件环
- ADSP 从事件环读取完成状态

### 音频流停止流程

1. **停止端点**
```c
ret = xhci_sideband_stop_endpoint(sb, ep);
```

2. **移除端点**
```c
ret = xhci_sideband_remove_endpoint(sb, ep);
```

### 清理流程

1. **清理中断器**
```c
xhci_sideband_cleanup_interrupter(sb);
```

2. **注销客户端**
```c
xhci_sideband_unregister(sb);
```

## 数据结构

### xhci_sideband 结构
```c
struct xhci_sideband {
    struct device *dev;           // 客户端设备
    struct xhci_hcd *xhci;        // xHCI 主机控制器
    struct list_head ep_list;     // 端点列表
    struct mutex mutex;           // 保护并发访问
    int interrupter;              // 中断器编号
    struct xhci_interrupter *ir;  // 中断器指针
};
```

### xhci_sideband_endpoint 结构
```c
struct xhci_sideband_endpoint {
    struct list_head list;
    struct usb_host_endpoint *ep;
    struct xhci_virt_device *vdev;
    unsigned int ep_index;
    struct xhci_ring *ring;
};
```

## 内存管理

### DMA 缓冲区
sideband 接口使用 DMA 一致性内存：
- 传输环：由 xHCI 驱动分配
- 事件环：由 xHCI 驱动分配
- 音频数据缓冲区：由 ADSP 管理

### 内存映射
ADSP 需要访问以下内存区域：
1. 传输环（读写）
2. 事件环（只读）
3. 门铃寄存器（只写）
4. 中断器寄存器（读写）

这些内存区域通过 IOMMU 映射到 ADSP 地址空间。

## 同步机制

### 锁保护
```c
// sideband 操作使用 mutex 保护
mutex_lock(&sb->mutex);
ret = xhci_sideband_add_endpoint(sb, ep);
mutex_unlock(&sb->mutex);
```

### 硬件同步
- 使用循环状态位（cycle bit）同步传输环
- 使用事件环出队指针（ERDP）同步事件环
- 使用门铃寄存器触发硬件处理

## 错误处理

### 端点停滞
当端点停滞时：
1. xHCI 生成停滞事件
2. ADSP 接收事件
3. 调用 xhci_sideband_stop_endpoint()
4. 重置端点状态
5. 重新启动传输

### 传输错误
当传输错误时：
1. xHCI 生成错误事件
2. ADSP 接收事件并记录错误
3. 根据错误类型决定重试或停止
4. 通过 QMI 通知内核驱动

### 设备断开
当设备断开时：
1. USB 核心通知断开事件
2. q6usb 驱动调用 xhci_sideband_remove_endpoint()
3. 清理所有端点资源
4. 通过 QMI 通知 ADSP

## 性能优化

### 减少中断
- 使用中断节流（interrupt throttling）
- 批量处理传输完成事件
- 使用事件环合并（event ring coalescing）

### 降低延迟
- ADSP 直接访问硬件，无需 AP 介入
- 使用专用中断器，避免与其他设备竞争
- 优化传输环大小，平衡内存使用和性能

## 调试支持

### 寄存器转储
```bash
# 查看 xHCI 寄存器
cat /sys/kernel/debug/usb/xhci/*/registers
```

### 传输环状态
```bash
# 查看传输环状态
cat /sys/kernel/debug/usb/xhci/*/ring_info
```

### 事件跟踪
```bash
# 启用 xHCI 事件跟踪
echo 1 > /sys/kernel/debug/tracing/events/xhci-hcd/enable
cat /sys/kernel/debug/tracing/trace
```

## 限制和约束

1. **端点类型**：仅支持同步端点（音频/视频）
2. **中断器数量**：受 xHCI 硬件限制（通常 8-16 个）
3. **传输环大小**：受内存限制，通常 256-1024 个 TRB
4. **并发访问**：同一端点不能同时被多个客户端访问

## 安全考虑

1. **权限检查**：确保只有授权的客户端可以注册
2. **地址验证**：验证 ADSP 访问的内存地址合法性
3. **资源隔离**：不同客户端的资源相互隔离
4. **错误恢复**：防止硬件错误影响系统稳定性

## 未来改进

1. 支持更多端点类型（批量、中断）
2. 改进错误恢复机制
3. 优化内存使用
4. 增强调试功能
5. 支持多个 ADSP 客户端
