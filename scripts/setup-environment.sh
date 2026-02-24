#!/bin/bash
# USB Audio Offload 环境搭建脚本
# 基于上游内核真实架构编写
# 适用于 QCS6490 Radxa Q6A + Linux 6.8+

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
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

# 检查 root 权限
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "请使用 root 权限运行 (sudo)"
        exit 1
    fi
}

# 检查依赖包
check_dependencies() {
    print_header "检查依赖包"

    local deps=(
        "build-essential:编译工具链"
        "bc:内核编译依赖"
        "bison:内核编译依赖"
        "flex:内核编译依赖"
        "libssl-dev:内核编译依赖"
        "libelf-dev:内核编译依赖"
        "device-tree-compiler:设备树编译器"
        "git:版本控制"
        "wget:文件下载"
        "alsa-utils:ALSA 工具"
    )

    local missing=()

    for entry in "${deps[@]}"; do
        local pkg="${entry%%:*}"
        local desc="${entry##*:}"

        if dpkg -l | grep -q "^ii.*$pkg"; then
            print_success "$desc ($pkg)"
        else
            print_warning "$desc ($pkg) 未安装"
            missing+=("$pkg")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        print_info "正在安装缺失的依赖包..."
        apt-get update
        apt-get install -y "${missing[@]}"
        print_success "依赖包安装完成"
    else
        print_success "所有依赖包已安装"
    fi
}

# 检查内核版本
check_kernel_version() {
    print_header "检查内核版本"

    local kernel_version=$(uname -r | cut -d. -f1,2)
    local major=$(echo $kernel_version | cut -d. -f1)
    local minor=$(echo $kernel_version | cut -d. -f2)

    print_info "当前内核版本: $(uname -r)"

    if [ "$major" -gt 6 ] || ([ "$major" -eq 6 ] && [ "$minor" -ge 8 ]); then
        print_success "内核版本满足要求 (>= 6.8)"
    else
        print_warning "内核版本过低，建议升级到 6.8 或更高版本"
        print_info "USB Audio Offload 需要 Linux 6.8+ 的完整支持"
    fi
}

# 设置固件目录
setup_firmware_dir() {
    print_header "设置固件目录"

    local firmware_dir="/lib/firmware/qcom/qcs6490"

    if [ ! -d "$firmware_dir" ]; then
        mkdir -p "$firmware_dir"
        print_success "创建固件目录: $firmware_dir"
    else
        print_info "固件目录已存在: $firmware_dir"
    fi

    # 检查固件文件
    print_info "检查固件文件:"

    if [ -f "$firmware_dir/adsp.mbn" ]; then
        print_success "adsp.mbn 存在"
        local size=$(stat -c%s "$firmware_dir/adsp.mbn")
        print_info "  大小: $((size / 1024 / 1024)) MB"
    else
        print_warning "adsp.mbn 不存在"
        print_info "  请从以下来源获取 ADSP 固件:"
        print_info "  1. Qualcomm 官方固件包"
        print_info "  2. 设备厂商提供的固件"
        print_info "  3. linux-firmware 仓库（如果有）"
    fi

    echo ""
    print_info "固件文件必须支持 USB Audio Offload 功能"
    print_info "固件版本需要与内核驱动匹配"
}

# 检查内核源码
check_kernel_source() {
    print_header "检查内核源码"

    local kernel_src_paths=(
        "/usr/src/linux-$(uname -r)"
        "/lib/modules/$(uname -r)/build"
        "/usr/src/linux"
    )

    local kernel_src=""

    for path in "${kernel_src_paths[@]}"; do
        if [ -d "$path" ]; then
            kernel_src="$path"
            print_success "找到内核源码: $kernel_src"
            break
        fi
    done

    if [ -z "$kernel_src" ]; then
        print_warning "未找到内核源码"
        print_info "如需编译内核模块，请安装内核源码:"
        print_info "  apt-get install linux-source-$(uname -r)"
        print_info "或从上游获取:"
        print_info "  git clone https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git"
        return 1
    fi

    # 检查关键配置选项
    print_info "检查内核配置:"

    local config_file=""
    if [ -f "$kernel_src/.config" ]; then
        config_file="$kernel_src/.config"
    elif [ -f "/proc/config.gz" ]; then
        config_file="/proc/config.gz"
    elif [ -f "/boot/config-$(uname -r)" ]; then
        config_file="/boot/config-$(uname -r)"
    fi

    if [ -n "$config_file" ]; then
        local key_configs=(
            "CONFIG_SND_SOC_QDSP6_Q6USB"
            "CONFIG_SND_USB_AUDIO_QMI"
            "CONFIG_USB_XHCI_SIDEBAND"
            "CONFIG_SND_SOC_USB"
        )

        for cfg in "${key_configs[@]}"; do
            if zgrep -q "^${cfg}=" "$config_file" 2>/dev/null || grep -q "^${cfg}=" "$config_file" 2>/dev/null; then
                print_success "$cfg 已启用"
            else
                print_warning "$cfg 未启用"
            fi
        done
    else
        print_warning "未找到内核配置文件"
    fi

    return 0
}

# 克隆 audioreach-engine 仓库（如果需要）
check_audioreach_engine() {
    print_header "检查 AudioReach Engine"

    print_info "注意: USB Audio Offload 不需要 AudioReach 拓扑文件"
    print_info "AudioReach 拓扑主要用于 codec、HDMI 等其他音频路径"

    local audioreach_dir="/opt/audioreach-engine"

    if [ -d "$audioreach_dir" ]; then
        print_info "AudioReach Engine 目录已存在: $audioreach_dir"
    else
        print_info "AudioReach Engine 未安装"
        print_info "如需支持其他音频路径（codec、HDMI），可以克隆:"
        print_info "  git clone https://github.com/linux-audio/audioreach-topology.git $audioreach_dir"
    fi
}

# 编译设备树
compile_device_tree() {
    print_header "编译设备树"

    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local dts_file="$script_dir/../kernel/dts/qcs6490-radxa-q6a-usb-audio.dtsi"

    if [ ! -f "$dts_file" ]; then
        print_error "设备树文件不存在: $dts_file"
        return 1
    fi

    print_info "设备树文件: $dts_file"

    # 检查是否有 dtc 命令
    if ! command -v dtc &> /dev/null; then
        print_error "dtc 命令不存在，请安装 device-tree-compiler"
        return 1
    fi

    print_warning "设备树编译需要完整的 SoC DTS 文件"
    print_info "qcs6490-radxa-q6a-usb-audio.dtsi 是一个 include 文件"
    print_info "需要在主 DTS 文件中 include 它:"
    echo ""
    echo "  #include \"qcs6490-radxa-q6a-usb-audio.dtsi\""
    echo ""
    print_info "然后编译完整的 DTB:"
    echo ""
    echo "  dtc -I dts -O dtb -o qcs6490-radxa-q6a.dtb qcs6490-radxa-q6a.dts"
    echo ""

    return 0
}

# 配置内核
configure_kernel() {
    print_header "配置内核"

    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local config_file="$script_dir/../kernel/config/usb_audio_offload.config"

    if [ ! -f "$config_file" ]; then
        print_error "配置文件不存在: $config_file"
        return 1
    fi

    print_info "USB Audio Offload 配置文件: $config_file"
    print_info ""
    print_info "配置内核步骤:"
    echo ""
    echo "  1. 进入内核源码目录:"
    echo "     cd /path/to/kernel-source"
    echo ""
    echo "  2. 合并配置:"
    echo "     ./scripts/kconfig/merge_config.sh \\"
    echo "         arch/arm64/configs/qcs6490_defconfig \\"
    echo "         $config_file"
    echo ""
    echo "  3. 更新配置:"
    echo "     make olddefconfig"
    echo ""
    echo "  4. 编译内核:"
    echo "     make -j\$(nproc)"
    echo ""
    echo "  5. 安装模块:"
    echo "     make modules_install"
    echo ""
    echo "  6. 安装内核:"
    echo "     make install"
    echo ""

    return 0
}

# 设置 ALSA 配置
setup_alsa_config() {
    print_header "设置 ALSA 配置"

    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local alsa_conf="$script_dir/../examples/alsa-configs/usb-offload.conf"

    if [ -f "$alsa_conf" ]; then
        print_info "ALSA 配置示例: $alsa_conf"
        print_info "此配置需要根据实际的 ASoC card 名称调整"
    else
        print_warning "ALSA 配置示例不存在"
    fi

    print_info ""
    print_info "ALSA UCM 配置目录: /usr/share/alsa/ucm2/"
    print_info "根据实际的声卡名称创建配置文件"
}

# 显示后续步骤
show_next_steps() {
    print_header "后续步骤"

    cat << 'NEXTSTEPS'
1. 准备固件文件
   将 ADSP 固件复制到:
   /lib/firmware/qcom/qcs6490/adsp.mbn

   固件必须支持 USB Audio Offload 功能

2. 配置和编译内核
   参考上面的"配置内核"部分
   确保启用所有必需的配置选项

3. 配置设备树
   在主 DTS 文件中 include:
   #include "qcs6490-radxa-q6a-usb-audio.dtsi"

   编译 DTB 并部署到 /boot/

4. 重启系统
   reboot

5. 验证驱动加载
   sudo lsmod | grep -E "q6usb|qmi|sideband"
   sudo cat /sys/class/remoteproc/remoteproc*/state

6. 连接 USB 音频设备
   插入 USB 音频设备
   检查设备枚举: lsusb | grep -i audio

7. 运行测试脚本
   sudo ./test-usb-offload.sh --all

8. 调试（如果有问题）
   # 查看内核日志
   dmesg | grep -iE "usb.*audio|q6usb|offload|adsp"

   # 查看 ADSP 状态
   cat /sys/class/remoteproc/remoteproc*/state

   # 查看 QMI 服务
   ls /sys/kernel/debug/qmi/

   # 查看 ASoC 设备
   cat /proc/asound/cards
   cat /proc/asound/pcm

重要提示:
- USB Audio Offload 需要 Linux 6.8+ 内核
- ADSP 固件必须支持 USB offload 功能
- 设备树配置必须正确（IOMMU、sideband）
- 不需要 AudioReach 拓扑文件（数据走 QMI + sideband）

参考文档:
- /c/Users/Administrator/audioreach-usb-offload-research/topology/README.md
- /c/Users/Administrator/audioreach-usb-offload-research/kernel/config/usb_audio_offload.config
- /c/Users/Administrator/audioreach-usb-offload-research/kernel/dts/qcs6490-radxa-q6a-usb-audio.dtsi

NEXTSTEPS
}

# 主函数
main() {
    check_root

    echo "=========================================="
    echo "USB Audio Offload 环境搭建"
    echo "QCS6490 Radxa Q6A"
    echo "=========================================="
    echo ""

    check_dependencies
    check_kernel_version
    setup_firmware_dir
    check_kernel_source || true
    check_audioreach_engine
    compile_device_tree || true
    configure_kernel
    setup_alsa_config

    show_next_steps

    print_success "环境搭建脚本执行完成"
}

main "$@"
