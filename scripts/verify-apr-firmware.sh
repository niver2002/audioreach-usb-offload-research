#!/bin/bash
# ============================================
# ADSP 固件 APR 协议兼容性验证脚本
# ============================================
# 在 Radxa Q6A (QCS6490) 设备上运行
# 验证 ADSP 固件是否支持 APR 协议栈
#
# 用法: sudo bash verify-apr-firmware.sh
# ============================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }

TOTAL=0
PASSED=0
FAILED=0

check() {
    TOTAL=$((TOTAL + 1))
    if eval "$1" >/dev/null 2>&1; then
        pass "$2"
        PASSED=$((PASSED + 1))
        return 0
    else
        fail "$2"
        FAILED=$((FAILED + 1))
        return 1
    fi
}

echo "============================================"
echo " ADSP 固件 APR 兼容性验证"
echo " 目标: Radxa Q6A (QCS6490)"
echo " 日期: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================"
echo ""

# ============================================
# Phase 1: 固件文件检查
# ============================================
info "Phase 1: 固件文件检查"
echo ""

ADSP_FW="/lib/firmware/qcom/qcs6490/radxa/dragon-q6a/adsp.mbn"
ADSP_FW_ALT="/lib/firmware/qcom/qcs6490/adsp.mbn"

if [ -f "$ADSP_FW" ]; then
    info "ADSP 固件路径: $ADSP_FW"
    ADSP_FW_PATH="$ADSP_FW"
elif [ -f "$ADSP_FW_ALT" ]; then
    info "ADSP 固件路径: $ADSP_FW_ALT"
    ADSP_FW_PATH="$ADSP_FW_ALT"
else
    fail "未找到 ADSP 固件文件"
    info "  尝试查找..."
    find /lib/firmware/qcom -name "adsp*" -type f 2>/dev/null | head -5
    ADSP_FW_PATH=""
fi

if [ -n "${ADSP_FW_PATH:-}" ]; then
    FW_SIZE=$(stat -c%s "$ADSP_FW_PATH" 2>/dev/null || stat -f%z "$ADSP_FW_PATH" 2>/dev/null)
    info "固件大小: $((FW_SIZE / 1024 / 1024)) MB"

    info ""
    info "扫描固件中的协议标识..."

    APR_STRINGS=$(strings "$ADSP_FW_PATH" | grep -ci "apr" 2>/dev/null || echo "0")
    AFE_STRINGS=$(strings "$ADSP_FW_PATH" | grep -ci "afe" 2>/dev/null || echo "0")
    GPR_STRINGS=$(strings "$ADSP_FW_PATH" | grep -ci "gpr" 2>/dev/null || echo "0")
    APM_STRINGS=$(strings "$ADSP_FW_PATH" | grep -ci "apm" 2>/dev/null || echo "0")

    info "  APR 相关字符串: $APR_STRINGS 个"
    info "  AFE 相关字符串: $AFE_STRINGS 个"
    info "  GPR 相关字符串: $GPR_STRINGS 个"
    info "  APM 相关字符串: $APM_STRINGS 个"

    if [ "$APR_STRINGS" -gt 0 ] && [ "$AFE_STRINGS" -gt 0 ]; then
        pass "固件包含 APR/AFE 协议标识"
    else
        warn "固件中未发现明显的 APR/AFE 标识（可能被压缩或混淆）"
    fi

    USB_STRINGS=$(strings "$ADSP_FW_PATH" | grep -ci "usb" 2>/dev/null || echo "0")
    info "  USB 相关字符串: $USB_STRINGS 个"

    if [ "$USB_STRINGS" -gt 0 ]; then
        pass "固件包含 USB 相关标识"
        strings "$ADSP_FW_PATH" | grep -i "usb" | sort -u | head -10 | while read -r line; do
            info "    $line"
        done
    else
        warn "固件中未发现 USB 标识"
    fi
fi

echo ""

# ============================================
# Phase 2: 运行时状态检查
# ============================================
info "Phase 2: 运行时状态检查"
echo ""

info "ADSP Remoteproc 状态:"
for rproc in /sys/class/remoteproc/remoteproc*; do
    if [ -d "$rproc" ]; then
        name=$(cat "$rproc/name" 2>/dev/null || echo "unknown")
        state=$(cat "$rproc/state" 2>/dev/null || echo "unknown")
        fw=$(cat "$rproc/firmware" 2>/dev/null || echo "unknown")
        info "  $name: state=$state firmware=$fw"
    fi
done

echo ""

# ============================================
# Phase 3: APR 协议栈检查
# ============================================
info "Phase 3: APR 协议栈检查"
echo ""

if [ -d "/sys/bus/apr" ]; then
    pass "APR bus 已注册 (/sys/bus/apr)"
    info "  APR 设备:"
    ls /sys/bus/apr/devices/ 2>/dev/null | while read -r dev; do
        info "    $dev"
    done
else
    fail "APR bus 不存在 — APR 协议栈未加载"
    info "  可能原因:"
    info "  1. 内核未编译 CONFIG_QCOM_APR"
    info "  2. 设备树中 APR 节点被删除 (/delete-node/ apr)"
    info "  3. ADSP 固件不支持 APR 协议"
fi

if [ -d "/sys/bus/gpr" ]; then
    info "GPR bus 已注册 — 当前使用 AudioReach 栈"
    ls /sys/bus/gpr/devices/ 2>/dev/null | while read -r dev; do
        info "    $dev"
    done
fi

echo ""
info "GLINK 通道检查:"
if [ -d "/sys/kernel/debug/rpmsg" ]; then
    for ch in /sys/kernel/debug/rpmsg/*/name; do
        [ -f "$ch" ] || continue
        chname=$(cat "$ch" 2>/dev/null)
        case "$chname" in
            apr_audio_svc) pass "APR glink 通道: $chname" ;;
            adsp_apps)     info "  GPR glink 通道: $chname" ;;
        esac
    done
else
    warn "无法访问 debugfs（需要 root 权限）"
fi

echo ""

# ============================================
# Phase 4: 音频内核模块检查
# ============================================
info "Phase 4: 音频内核模块检查"
echo ""

info "APR 栈模块:"
for mod in snd_soc_qdsp6_core snd_soc_qdsp6_afe snd_soc_qdsp6_asm \
           snd_soc_qdsp6_adm snd_soc_qdsp6_usb qcom_apr; do
    if lsmod 2>/dev/null | grep -q "$mod"; then
        pass "  已加载: $mod"
    else
        info "  未加载: $mod"
    fi
done

echo ""
info "USB Offload 模块:"
for mod in snd_soc_usb snd_usb_audio; do
    if lsmod 2>/dev/null | grep -q "$mod"; then
        pass "  已加载: $mod"
    else
        info "  未加载: $mod"
    fi
done

echo ""

# ============================================
# Phase 5: ALSA 设备检查
# ============================================
info "Phase 5: ALSA 设备检查"
echo ""

if [ -f /proc/asound/cards ]; then
    info "声卡:"
    cat /proc/asound/cards | while read -r line; do
        info "  $line"
    done
fi

if [ -f /proc/asound/pcm ]; then
    echo ""
    info "PCM 设备:"
    cat /proc/asound/pcm | while read -r line; do
        info "  $line"
    done
fi

echo ""

# ============================================
# 总结
# ============================================
echo "============================================"
echo " 验证总结: $PASSED 通过 / $FAILED 失败 / $TOTAL 总计"
echo "============================================"
echo ""

if [ -d "/sys/bus/apr" ]; then
    pass "APR 栈已激活，可以尝试 USB offload"
elif [ -d "/sys/bus/gpr" ]; then
    warn "当前使用 GPR/AudioReach 栈，需要切换到 APR 栈"
    info "  步骤: 使用 APR 设备树 + 内核补丁 + APR 兼容固件"
else
    fail "音频子系统未初始化"
fi
