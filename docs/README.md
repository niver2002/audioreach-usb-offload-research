# AudioReach USB Offload 研究文档

本目录包含 AudioReach USB Offload 技术的深度研究文档。

## 文档列表

### 04-mfc-module.md - MFC 模块详解
**行数**: 832 行  
**大小**: 22KB

**内容概要**:
- MFC (Media Format Converter) 模块完整技术规格
- 核心参数详解 (PARAM_ID_MFC_OUTPUT_MEDIA_FORMAT, PARAM_ID_MFC_RESAMPLER_CFG)
- IIR vs FIR 重采样算法对比
- MFC vs Dynamic Resampler 详细对比表
- 多种使用场景和代码示例
- AudioReach Graph 配置示例
- 性能特征和最佳实践
- 调试和故障排查方法

**关键技术点**:
- MODULE_ID: 0x07001015
- 支持采样率转换 (8kHz - 384kHz)
- 支持位深转换 (16/24/32-bit)
- 支持通道混音 (1-8 通道)
- IIR 模式: 低延迟 (3-5ms)，适合语音
- FIR 模式: 高音质 (15-20ms)，适合音乐

---

### 05-radxa-q6a-implementation.md - Radxa Q6A 实现方案
**行数**: 847 行  
**大小**: 22KB

**内容概要**:
- Radxa Q6A 硬件架构详解 (QCS6490 SoC)
- 完整的系统架构图
- Linux 内核配置步骤 (6.8+)
- 详细的设备树配置 (DTS)
- AudioReach 拓扑配置和编译
- ALSA UCM、PulseAudio、PipeWire 配置
- 端到端测试流程
- 性能验证方法 (CPU、延迟、功耗)
- 完整的 Shell 脚本示例

**关键配置**:
- 必需内核选项: CONFIG_SND_SOC_QDSP6_Q6USB, CONFIG_USB_XHCI_SIDEBAND
- ADSP 固件路径: /lib/firmware/qcom/qcs6490/adsp/
- 性能提升: CPU 使用率降低 80%，功耗降低 30-50%

---

### 06-troubleshooting.md - 故障排查指南
**行数**: 869 行  
**大小**: 18KB

**内容概要**:
- 问题分类体系 (内核/固件/USB/拓扑/用户空间)
- 10+ 个常见问题的详细排查步骤
- 每个问题包含: 症状、原因分析、解决方案、验证命令
- 完整的调试工具和命令集合
- 日志分析方法和关键字
- 性能调优技巧
- 快速诊断脚本

**涵盖问题**:
1. USB Offload 驱动未加载
2. XHCI Sideband 初始化失败
3. IOMMU 映射失败
4. QMI 服务连接失败
5. ADSP 固件加载失败
6. USB AFE 模块不可用
7. Graph 打开失败
8. USB 设备未被 Offload 识别
9. 采样率不支持
10. 播放无声音

## 文档特点

✅ **全中文**: 所有文档使用中文编写，便于中文用户阅读  
✅ **技术准确**: 基于 Linux 内核源码和 Qualcomm 官方文档  
✅ **内容详实**: 每篇文档 800+ 行，包含丰富的技术细节  
✅ **代码示例**: 包含大量 C 代码、Shell 脚本、设备树配置  
✅ **实用性强**: 提供可直接使用的配置和脚本  
✅ **架构图表**: 包含系统架构图和对比表格  
✅ **UTF-8 编码**: 正确的中文编码，无乱码问题

## 使用建议

1. **初学者**: 按顺序阅读，从 MFC 模块开始了解基础概念
2. **开发者**: 重点阅读 Radxa Q6A 实现方案，获取配置细节
3. **调试人员**: 直接查阅故障排查指南，快速定位问题
4. **系统集成**: 参考所有文档，完整实现 USB Offload 功能

## 技术栈

- **硬件平台**: Qualcomm QCS6490 (Radxa Q6A)
- **操作系统**: Linux 6.8+
- **音频框架**: AudioReach
- **通信协议**: GLINK, QMI, GPR
- **音频接口**: ALSA, PulseAudio, PipeWire

## 相关资源

- Linux 内核源码: `sound/soc/qcom/qdsp6/`
- 设备树文档: `Documentation/devicetree/bindings/sound/qcom,*`
- ALSA 文档: `Documentation/sound/`

## 文档版本

- 创建日期: 2026-02-24
- 基于内核版本: Linux 6.8+
- AudioReach 版本: 最新稳定版

---

**注意**: 这些文档基于公开的技术资料和开源代码编写，用于技术研究和学习目的。
