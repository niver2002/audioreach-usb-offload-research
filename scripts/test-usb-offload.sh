#!/bin/bash
# USB Audio Offload 测试脚本
# 基于上游内核真实架构编写
# 适用于 QCS6490 Radxa Q6A + Linux 6.8+

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

LOG_FILE="/tmp/usb-offload-test-$(date +%Y%m%d-%H%M%S).log"

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1" | tee -a "$LOG_FILE"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1" | tee -a "$LOG_FILE"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1" | tee -a "$LOG_FILE"
}

print_header() {
    echo -e "\n${CYAN}========================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}========================================${NC}\n"
}

# 检查内核模块加载
check_kernel_modules() {
    print_header "检查内核模块"

    local modules=(
        "snd_soc_q6usb:Q6 USB ASoC component"
        "snd_usb_audio_qmi:USB Audio QMI 服务"
        "xhci_sideband:XHCI Sideband API"
        "snd_soc_qdsp6:QDSP6 ASoC 平台驱动"
        "qcom_q6v5_adsp:ADSP Remoteproc 驱动"
        "snd_usb_audio:USB Audio Class 驱动"
    )

    local loaded=0
    local total=${#modules[@]}

    for entry in "${modules[@]}"; do
        local module="${entry%%:*}"
        local desc="${entry##*:}"

        if lsmod | grep -q "^${module}"; then
            print_success "${desc} (${module})"
            ((loaded++))
        else
            print_warning "${desc} (${module}) 未加载"
        fi
    done

    echo ""
    print_info "已加载: ${loaded}/${total} 个模块"

    if [ $loaded -lt 3 ]; then
        print_error "关键模块未加载，USB offload 可能不可用"
        return 1
    fi

    return 0
}

# 检查 ADSP 固件状态
check_adsp_status() {
    print_header "检查 ADSP 固件状态"

    local adsp_found=0

    for rproc in /sys/class/remoteproc/remoteproc*; do
        if [ -f "$rproc/name" ]; then
            local name=$(cat "$rproc/name")
            if [[ "$name" == *"adsp"* ]]; then
                adsp_found=1
                print_info "找到 ADSP: $rproc"

                if [ -f "$rproc/state" ]; then
                    local state=$(cat "$rproc/state")
                    if [ "$state" == "running" ]; then
                        print_success "ADSP 状态: $state"
                    else
                        print_warning "ADSP 状态: $state (应为 running)"
                    fi
                fi

                if [ -f "$rproc/firmware" ]; then
                    local firmware=$(cat "$rproc/firmware")
                    print_info "固件: $firmware"
                fi

                break
            fi
        fi
    done

    if [ $adsp_found -eq 0 ]; then
        print_error "未找到 ADSP remoteproc 设备"
        return 1
    fi

    return 0
}

# 检查 Auxiliary Device
check_auxiliary_devices() {
    print_header "检查 Auxiliary Device"

    if [ ! -d "/sys/bus/auxiliary/devices" ]; then
        print_warning "Auxiliary bus 不存在"
        return 1
    fi

    local usb_audio_dev=$(ls /sys/bus/auxiliary/devices/ 2>/dev/null | grep -i "usb.*audio" || true)

    if [ -n "$usb_audio_dev" ]; then
        print_success "找到 USB Audio Auxiliary Device:"
        echo "$usb_audio_dev" | while read dev; do
            print_info "  - $dev"
        done
    else
        print_warning "未找到 USB Audio Auxiliary Device"
        print_info "这可能表示 q6usb 驱动未正确注册"
    fi

    return 0
}

# 检查 QMI 服务
check_qmi_services() {
    print_header "检查 QMI 服务"

    if [ ! -d "/sys/kernel/debug/qmi" ]; then
        print_warning "QMI debugfs 不存在（可能需要 CONFIG_DEBUG_FS=y）"
        return 1
    fi

    local qmi_services=$(ls /sys/kernel/debug/qmi/ 2>/dev/null || true)

    if [ -n "$qmi_services" ]; then
        print_success "找到 QMI 服务:"
        echo "$qmi_services" | while read svc; do
            print_info "  - $svc"
        done
    else
        print_warning "未找到 QMI 服务"
    fi

    return 0
}

# 检查 XHCI Sideband 状态
check_xhci_sideband() {
    print_header "检查 XHCI Sideband"

    local sideband_found=0

    # 检查 sysfs 中的 sideband 信息
    for xhci in /sys/kernel/debug/usb/xhci/*; do
        if [ -d "$xhci" ]; then
            print_info "XHCI 控制器: $(basename $xhci)"

            # 检查是否有 sideband 相关文件
            if [ -f "$xhci/sideband" ] || [ -d "$xhci/sideband" ]; then
                print_success "支持 Sideband"
                sideband_found=1
            fi
        fi
    done

    if [ $sideband_found -eq 0 ]; then
        print_warning "未找到 XHCI Sideband 支持"
        print_info "可能需要 CONFIG_USB_XHCI_SIDEBAND=y"
    fi

    return 0
}

# 检查 USB 音频设备
check_usb_audio_device() {
    print_header "检查 USB 音频设备"

    local usb_audio=$(lsusb 2>/dev/null | grep -i "audio" || true)

    if [ -n "$usb_audio" ]; then
        print_success "检测到 USB 音频设备:"
        echo "$usb_audio" | while read line; do
            print_info "  $line"
        done
    else
        print_warning "未检测到 USB 音频设备"
        print_info "请连接 USB 音频设备后重试"
        return 1
    fi

    # 检查 USB 设备详情
    if [ -f "/sys/kernel/debug/usb/devices" ]; then
        print_info "USB 音频设备详情:"
        grep -A 20 "Audio" /sys/kernel/debug/usb/devices 2>/dev/null | head -20 || true
    fi

    return 0
}

# 检查 IOMMU 映射
check_iommu_mappings() {
    print_header "检查 IOMMU 映射"

    if [ ! -d "/sys/kernel/debug/iommu" ]; then
        print_warning "IOMMU debugfs 不存在"
        return 1
    fi

    local usb_audio_mapping=0

    for iommu in /sys/kernel/debug/iommu/*; do
        if [ -f "$iommu/mappings" ]; then
            # 查找 USB 音频相关的映射（Stream ID 0x180f）
            if grep -q "180f" "$iommu/mappings" 2>/dev/null; then
                print_success "找到 USB 音频 IOMMU 映射"
                print_info "$(grep "180f" "$iommu/mappings" | head -5)"
                usb_audio_mapping=1
            fi
        fi
    done

    if [ $usb_audio_mapping -eq 0 ]; then
        print_warning "未找到 USB 音频 IOMMU 映射"
        print_info "这可能表示设备树配置不正确"
    fi

    return 0
}

# 检查 ASoC 设备
check_asoc_devices() {
    print_header "检查 ASoC 设备"

    print_info "系统声卡列表:"
    if command -v aplay &> /dev/null; then
        aplay -l 2>/dev/null || print_warning "aplay 命令失败"
    else
        print_warning "aplay 命令不存在"
    fi

    echo ""
    print_info "PCM 设备:"
    if [ -f "/proc/asound/pcm" ]; then
        cat /proc/asound/pcm
    else
        print_warning "/proc/asound/pcm 不存在"
    fi

    echo ""
    print_info "声卡信息:"
    if [ -f "/proc/asound/cards" ]; then
        cat /proc/asound/cards
    else
        print_warning "/proc/asound/cards 不存在"
    fi

    # 检查 USB offload PCM 设备
    echo ""
    local usb_offload_pcm=$(cat /proc/asound/pcm 2>/dev/null | grep -i "usb.*offload\|q6usb" || true)
    if [ -n "$usb_offload_pcm" ]; then
        print_success "找到 USB Offload PCM 设备:"
        echo "$usb_offload_pcm"
    else
        print_warning "未找到 USB Offload PCM 设备"
        print_info "可能使用传统的 USB Audio Class 驱动"
    fi

    return 0
}

# 检查 DAPM 路由
check_dapm_routing() {
    print_header "检查 DAPM 路由"

    if [ ! -d "/sys/kernel/debug/asoc" ]; then
        print_warning "ASoC debugfs 不存在"
        return 1
    fi

    print_info "查找 USB 相关的 DAPM widgets:"

    local usb_widgets=$(find /sys/kernel/debug/asoc -name "*USB*" -o -name "*usb*" 2>/dev/null || true)

    if [ -n "$usb_widgets" ]; then
        echo "$usb_widgets" | while read widget; do
            print_info "  - $widget"
        done
    else
        print_warning "未找到 USB DAPM widgets"
    fi

    return 0
}

# 播放测试
test_playback() {
    print_header "播放测试"

    # 查找 USB 音频设备
    local usb_card=$(aplay -l 2>/dev/null | grep -i "usb" | head -1 | sed -n 's/card \([0-9]*\).*/\1/p' || true)

    if [ -z "$usb_card" ]; then
        print_warning "未找到 USB 音频设备，跳过播放测试"
        return 1
    fi

    print_info "使用声卡: $usb_card"
    print_info "生成测试音频 (1kHz 正弦波, 5秒)"

    if command -v speaker-test &> /dev/null; then
        speaker-test -D hw:$usb_card,0 -t sine -f 1000 -c 2 -r 48000 -d 5 2>&1 | tee -a "$LOG_FILE" || {
            print_warning "播放测试失败"
            return 1
        }
        print_success "播放测试完成"
    else
        print_warning "speaker-test 命令不存在，跳过播放测试"
        return 1
    fi

    return 0
}

# 生成诊断报告
generate_report() {
    print_header "生成诊断报告"

    local report_file="/tmp/usb-offload-diagnostic-$(date +%Y%m%d-%H%M%S).txt"

    {
        echo "USB Audio Offload 诊断报告"
        echo "生成时间: $(date)"
        echo "内核版本: $(uname -r)"
        echo "=========================================="
        echo ""

        echo "=== 内核模块 ==="
        lsmod | grep -E "snd|usb|qcom|q6" || echo "无相关模块"
        echo ""

        echo "=== ADSP 状态 ==="
        for rproc in /sys/class/remoteproc/remoteproc*; do
            if [ -f "$rproc/name" ]; then
                echo "Name: $(cat $rproc/name)"
                echo "State: $(cat $rproc/state 2>/dev/null || echo 'N/A')"
                echo "Firmware: $(cat $rproc/firmware 2>/dev/null || echo 'N/A')"
                echo ""
            fi
        done

        echo "=== USB 设备 ==="
        lsusb 2>/dev/null || echo "lsusb 不可用"
        echo ""

        echo "=== ALSA 设备 ==="
        cat /proc/asound/cards 2>/dev/null || echo "/proc/asound/cards 不存在"
        echo ""
        cat /proc/asound/pcm 2>/dev/null || echo "/proc/asound/pcm 不存在"
        echo ""

        echo "=== 设备树节点 ==="
        ls -la /sys/firmware/devicetree/base/soc/ 2>/dev/null | grep -E "usb|adsp|audio" || echo "无相关节点"
        echo ""

        echo "=== 内核日志（最近50行） ==="
        dmesg | grep -iE "usb.*audio|q6usb|offload|adsp|qmi|sideband" | tail -50 || echo "无相关日志"

    } > "$report_file"

    print_success "诊断报告已保存: $report_file"
    print_info "请将此报告附加到 bug 报告中"
}

# 显示帮助
show_help() {
    cat << 'HELPTEXT'
USB Audio Offload 测试脚本

用法: sudo ./test-usb-offload.sh [选项]

选项:
  -c, --check       检查环境配置（默认）
  -p, --play        播放测试
  -a, --all         运行所有测试
  -r, --report      生成诊断报告
  -h, --help        显示帮助

示例:
  sudo ./test-usb-offload.sh --check
  sudo ./test-usb-offload.sh --all
  sudo ./test-usb-offload.sh --report

说明:
  此脚本用于测试 USB Audio Offload 功能是否正常工作。
  需要 root 权限以访问 debugfs 和系统信息。

检查项目:
  1. 内核模块加载（q6usb, QMI, sideband）
  2. ADSP 固件状态
  3. Auxiliary device 注册
  4. QMI 服务状态
  5. XHCI sideband 支持
  6. USB 音频设备枚举
  7. IOMMU 映射配置
  8. ASoC 设备和 PCM
  9. DAPM 路由
  10. 音频播放测试（可选）

HELPTEXT
}

# 主函数
main() {
    if [ "$EUID" -ne 0 ]; then
        print_error "请使用 root 权限运行 (sudo)"
        exit 1
    fi

    local run_check=0
    local run_play=0
    local run_all=0
    local run_report=0

    # 解析参数
    if [ $# -eq 0 ]; then
        run_check=1
    fi

    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--check) run_check=1; shift ;;
            -p|--play) run_play=1; shift ;;
            -a|--all) run_all=1; shift ;;
            -r|--report) run_report=1; shift ;;
            -h|--help) show_help; exit 0 ;;
            *) print_error "未知选项: $1"; show_help; exit 1 ;;
        esac
    done

    print_header "USB Audio Offload 测试工具"
    print_info "日志文件: $LOG_FILE"
    print_info "内核版本: $(uname -r)"
    print_info "测试时间: $(date)"

    # 运行检查
    if [ $run_check -eq 1 ] || [ $run_all -eq 1 ]; then
        check_kernel_modules || true
        check_adsp_status || true
        check_auxiliary_devices || true
        check_qmi_services || true
        check_xhci_sideband || true
        check_usb_audio_device || true
        check_iommu_mappings || true
        check_asoc_devices || true
        check_dapm_routing || true
    fi

    # 运行播放测试
    if [ $run_play -eq 1 ] || [ $run_all -eq 1 ]; then
        test_playback || true
    fi

    # 生成报告
    if [ $run_report -eq 1 ] || [ $run_all -eq 1 ]; then
        generate_report
    fi

    print_header "测试完成"
    print_info "详细日志: $LOG_FILE"
}

main "$@"
