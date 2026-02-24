#!/bin/bash
# 环境搭建脚本
# 用于配置 USB Audio Offload 开发环境

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "请使用 root 权限运行 (sudo)"
        exit 1
    fi
}

check_dependencies() {
    print_info "检查依赖包..."
    
    local deps=(
        "alsa-utils"
        "alsa-topology-conf"
        "alsa-ucm-conf"
        "m4"
        "gcc"
        "make"
        "device-tree-compiler"
    )
    
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! dpkg -l | grep -q "^ii.*$dep"; then
            missing+=("$dep")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        print_warning "缺少以下依赖包: ${missing[*]}"
        print_info "正在安装..."
        apt-get update
        apt-get install -y "${missing[@]}"
        print_success "依赖包安装完成"
    else
        print_success "所有依赖包已安装"
    fi
}

setup_firmware_dir() {
    print_info "设置固件目录..."
    
    local firmware_dir="/lib/firmware/qcom/qcs6490"
    
    if [ ! -d "$firmware_dir" ]; then
        mkdir -p "$firmware_dir"
        print_success "创建固件目录: $firmware_dir"
    else
        print_info "固件目录已存在: $firmware_dir"
    fi
    
    print_warning "请确保以下固件文件存在:"
    echo "  - $firmware_dir/adsp.mbn"
    echo "  - $firmware_dir/audioreach-tplg.bin"
    echo "  - $firmware_dir/usb-offload-tplg.bin"
}

setup_alsa_ucm() {
    print_info "设置 ALSA UCM 配置..."
    
    local ucm_dir="/usr/share/alsa/ucm2/qcom/qcs6490"
    
    if [ ! -d "$ucm_dir" ]; then
        mkdir -p "$ucm_dir"
        print_success "创建 UCM 目录: $ucm_dir"
    fi
    
    print_info "UCM 配置目录: $ucm_dir"
}

compile_device_tree() {
    print_info "编译设备树..."
    
    local dts_file="../kernel/dts/qcs6490-radxa-q6a-usb-audio.dtsi"
    local dtbo_file="/boot/overlays/usb-audio-offload.dtbo"
    
    if [ ! -f "$dts_file" ]; then
        print_warning "设备树文件不存在: $dts_file"
        return 1
    fi
    
    print_info "编译 DTBO..."
    dtc -@ -I dts -O dtb -o "$dtbo_file" "$dts_file" 2>/dev/null || {
        print_warning "DTBO 编译失败，可能需要手动编译"
        return 1
    }
    
    print_success "DTBO 已编译: $dtbo_file"
}

show_next_steps() {
    cat << 'NEXTSTEPS'

========================================
环境搭建完成
========================================

后续步骤:

1. 准备固件文件
   将以下文件复制到 /lib/firmware/qcom/qcs6490/:
   - adsp.mbn (ADSP 固件)
   - audioreach-tplg.bin (AudioReach 拓扑)
   - usb-offload-tplg.bin (USB offload 拓扑)

2. 配置内核
   cd <kernel-source>
   ./scripts/kconfig/merge_config.sh \
       arch/arm64/configs/qcs6490_defconfig \
       path/to/usb_audio_offload.config

3. 编译内核
   make -j$(nproc)
   make modules_install
   make install

4. 更新设备树
   将 usb-audio-offload.dtbo 添加到启动配置

5. 重启系统
   reboot

6. 运行测试
   sudo ./test-usb-offload.sh --all

========================================

NEXTSTEPS
}

main() {
    check_root
    
    echo "========================================"
    echo "USB Audio Offload 环境搭建"
    echo "========================================"
    echo ""
    
    check_dependencies
    setup_firmware_dir
    setup_alsa_ucm
    compile_device_tree || true
    
    show_next_steps
}

main "$@"
