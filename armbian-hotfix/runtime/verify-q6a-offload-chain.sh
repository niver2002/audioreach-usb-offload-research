#!/usr/bin/env bash
set -euo pipefail

WAV_FILE="${1:-/usr/share/sounds/alsa/Front_Center.wav}"
line=$(grep -m1 -E 'USB Playback|q6usb' /proc/asound/pcm || true)
if [[ -z "$line" || ! "$line" =~ ^([0-9]+)-([0-9]+): ]]; then
  echo "Cannot find USB offload PCM in /proc/asound/pcm" >&2
  exit 1
fi

CARD="${BASH_REMATCH[1]}"
DEV="${BASH_REMATCH[2]}"
echo "Using PCM hw:${CARD},${DEV}"

echo "== HW params dump =="
if [[ -f "$WAV_FILE" ]]; then
  aplay --dump-hw-params -D "hw:${CARD},${DEV}" "$WAV_FILE" 2>&1 | tee /tmp/q6a-offload-hwparams.log || true
else
  echo "WAV not found: $WAV_FILE"
fi

echo "== Kernel evidence =="
uname -a
modinfo snd_soc_q6usb 2>/dev/null | sed -n '1,20p' || true
dmesg | grep -iE 'q6usb|qc_audio_offload|uaudio|sideband' | tail -n 80 || true

echo "== Bluetooth codec evidence =="
pactl list cards 2>/dev/null | sed -n '/bluez_card/,/Profiles/p' || true

echo "== Result hint =="
echo "Expected max verified by kernel constraints: 24-bit, 192000 Hz, 2ch"
