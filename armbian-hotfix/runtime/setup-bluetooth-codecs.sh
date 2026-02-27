#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

mkdir -p /etc/wireplumber/wireplumber.conf.d
cat >/etc/wireplumber/wireplumber.conf.d/30-q6a-bt-codecs.conf <<'EOF'
monitor.bluez.properties = {
    bluez5.codecs = [ sbc sbc_xq aac aptx aptx_hd ldac ]
    bluez5.roles = [ a2dp_sink a2dp_source hfp_hf hfp_ag ]
}
EOF

if [[ -f /etc/bluetooth/main.conf ]] && ! grep -q '^Experimental *= *true' /etc/bluetooth/main.conf; then
  sed -i 's/^#\?Experimental *=.*/Experimental = true/' /etc/bluetooth/main.conf || true
fi

echo "Bluetooth codec hotfix installed."
echo "Restart services: systemctl restart bluetooth; systemctl --user restart wireplumber pipewire pipewire-pulse"
echo "Verify codec negotiation: pactl list cards | sed -n '/bluez_card/,/Profiles/p'"
