#!/bin/bash
# USB Audio Offload 测试脚本
# 适用于 QCS6490 Radxa Q6A

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

LOG_FILE="/tmp/usb-offload-test.log"

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

print_header() {
    echo -e "\n${CYAN}========================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}========================================${NC}\n"
}

check_kernel_config() {
    print_header "检查内核配置"
    
    local config_file="/proc/config.gz"
    if [ ! -f "$config_file" ]; then
        config_file="/boot/config-$(uname -r)"
    fi
    
    if [ ! -f "$config_file" ]; then
        print_error "无法找到内核配置文件"
        return 1
    fi
    
    print_success "找到内核配置: $config_file"
    return 0
}

check_adsp_status() {
    print_header "检查 ADSP 固件状态"
    
    local adsp_rproc=$(find /sys/class/remoteproc -name "remoteproc*" 2>/dev/null | head -1)
    
    if [ -z "$adsp_rproc" ]; then
        print_error "未找到 ADSP remoteproc 设备"
        return 1
    fi
    
    print_info "ADSP remoteproc: $adsp_rproc"
    
    if [ -f "$adsp_rproc/state" ]; then
        local state=$(cat "$adsp_rproc/state")
        print_info "ADSP 状态: $state"
    fi
    
    return 0
}

check_usb_device() {
    print_header "检查 USB 音频设备"
    
    local usb_audio=$(lsusb | grep -i "audio" || true)
    
    if [ -z "$usb_audio" ]; then
        print_error "未检测到 USB 音频设备"
        return 1
    fi
    
    print_success "检测到 USB 音频设备:"
    echo "$usb_audio"
    return 0
}

check_alsa_devices() {
    print_header "检查 ALSA 设备"
    
    print_info "系统声卡列表:"
    aplay -l
    
    print_info "PCM 设备:"
    cat /proc/asound/pcm
    
    return 0
}

test_playback() {
    print_header "播放测试"
    
    print_info "生成测试音频 (1kHz 正弦波, 5秒)"
    
    speaker-test -t sine -f 1000 -c 2 -r 48000 -d 5 || true
    
    print_success "播放测试完成"
    return 0
}

show_help() {
    cat << 'HELPTEXT'
USB Audio Offload 测试脚本

用法: sudo ./test-usb-offload.sh [选项]

选项:
  -c, --check       检查环境配置
  -p, --play        播放测试
  -a, --all         运行所有测试
  -h, --help        显示帮助

示例:
  sudo ./test-usb-offload.sh --check
  sudo ./test-usb-offload.sh --all

HELPTEXT
}

main() {
    if [ "$EUID" -ne 0 ]; then
        print_error "请使用 root 权限运行 (sudo)"
        exit 1
    fi
    
    local run_check=0
    local run_play=0
    local run_all=0
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--check) run_check=1; shift ;;
            -p|--play) run_play=1; shift ;;
            -a|--all) run_all=1; shift ;;
            -h|--help) show_help; exit 0 ;;
            *) print_error "未知选项: $1"; exit 1 ;;
        esac
    done
    
    if [ $run_all -eq 0 ] && [ $run_check -eq 0 ] && [ $run_play -eq 0 ]; then
        show_help
        exit 0
    fi
    
    print_header "USB Audio Offload 测试工具"
    print_info "日志文件: $LOG_FILE"
    
    check_kernel_config || true
    check_adsp_status || true
    check_usb_device || true
    check_alsa_devices || true
    
    if [ $run_play -eq 1 ] || [ $run_all -eq 1 ]; then
        test_playback || true
    fi
    
    print_success "测试完成"
}

main "$@"
