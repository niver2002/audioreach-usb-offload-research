#!/usr/bin/env bash
set -euo pipefail

require_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    echo "Run as root: sudo $0" >&2
    exit 1
  fi
}

detect_offload_pcm() {
  local line
  line=$(grep -m1 -E 'USB Playback|q6usb' /proc/asound/pcm || true)
  if [[ -n "$line" && "$line" =~ ^([0-9]+)-([0-9]+): ]]; then
    echo "${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"
    return 0
  fi
  return 1
}

write_alsa_conf() {
  local card="$1"
  local dev="$2"
  mkdir -p /etc/asound.conf.d
  cat >/etc/asound.conf.d/90-q6a-offload.conf <<EOF
pcm.q6a_usb_offload_raw {
  type hw
  card ${card}
  device ${dev}
}

pcm.q6a_usb_offload_192k {
  type plug
  slave {
    pcm q6a_usb_offload_raw
    format S24_LE
    rate 192000
    channels 2
  }
}

ctl.q6a_usb_offload {
  type hw
  card ${card}
}
EOF
}

write_pipewire_conf() {
  mkdir -p /etc/pipewire/pipewire.conf.d
  cat >/etc/pipewire/pipewire.conf.d/20-q6a-usb-offload.conf <<'EOF'
context.properties = {
    default.clock.rate = 192000
    default.clock.allowed-rates = [ 44100 48000 88200 96000 176400 192000 ]
    default.clock.quantum = 1024
    default.clock.min-quantum = 256
    default.clock.max-quantum = 8192
    resample.quality = 14
}
EOF
}

write_bluez_conf() {
  mkdir -p /etc/wireplumber/wireplumber.conf.d
  cat >/etc/wireplumber/wireplumber.conf.d/20-q6a-bluez-codecs.conf <<'EOF'
monitor.bluez.properties = {
    bluez5.codecs = [ sbc sbc_xq aac aptx aptx_hd ldac ]
    bluez5.default.rate = 48000
    bluez5.default.channels = 2
}
EOF
}

main() {
  require_root

  local card="${Q6A_OFFLOAD_CARD:-}"
  local dev="${Q6A_OFFLOAD_DEV:-}"

  if [[ -z "$card" || -z "$dev" ]]; then
    if read -r card dev < <(detect_offload_pcm); then
      echo "Detected offload PCM: hw:${card},${dev}"
    else
      echo "Cannot auto-detect offload PCM from /proc/asound/pcm." >&2
      echo "Set Q6A_OFFLOAD_CARD and Q6A_OFFLOAD_DEV, then rerun." >&2
      exit 1
    fi
  fi

  write_alsa_conf "$card" "$dev"
  write_pipewire_conf
  write_bluez_conf

  echo "Runtime hotfix installed."
  echo "Restart user audio stack: systemctl --user restart pipewire pipewire-pulse wireplumber"
  echo "Required packages for codecs: pipewire, pipewire-audio, wireplumber, libldac, libopenaptx"
}

main "$@"
