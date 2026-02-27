#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

RENDERER_NAME="${Q6A_DLNA_RENDERER_NAME:-Q6A-USB-Offload}"
SERVICE_FILE="/etc/systemd/system/q6a-dlna-offload.service"

cat >"$SERVICE_FILE" <<EOF
[Unit]
Description=Q6A DLNA Renderer -> USB Offload
After=network-online.target sound.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/gmediarender -f "${RENDERER_NAME}" --gstout-audiosink="alsasink device=q6a_usb_offload_192k"
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now q6a-dlna-offload.service

echo "DLNA renderer is active: ${RENDERER_NAME}"
echo "Push audio from QPlay/DLNA controller to this renderer."
