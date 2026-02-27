# Q6A USB Offload Armbian Hotfix (Verified)

## 1) Kernel max capability (code-constrained)

- Final output max (verified): **24-bit / 192000 Hz / 2 channels**
- Evidence chain:
  - USB backend DAI constraints are 16/24-bit and up to 192k.
  - AFE USB config contract also documents 16/24-bit, 1/2ch.
  - QMI layer can parse up to U32 formats, but that is not reachable through current USB_RX DAI constraints.

## 2) What this hotfix patches

Patch set (`patches/*.patch`):

1. `0001`: add AudioReach USB module IDs and media-format path
2. `0002`: wire USB backend ops in `q6apm-lpass-dais`
3. `0003`: allow q6usb fallback when AFE USB port is unavailable
4. `0004`: add Q6A DTS USB offload link (`q6apmbedai USB_RX` -> `q6usb USB_RX`)
5. `0005`: topology parser handles USB module IDs

## 3) Armbian usage

Apply kernel patch set:

```bash
sudo ./apply-kernel-hotfix.sh /path/to/armbian/kernel/source
```

Install runtime hotfix:

```bash
sudo ./runtime/setup-runtime-hotfix.sh
sudo ./runtime/setup-dlna-offload.sh
sudo ./runtime/setup-bluetooth-codecs.sh
```

Verify:

```bash
sudo ./runtime/verify-q6a-offload-chain.sh
```

## 4) Input endpoints and routing

- Local playback endpoint:
  - ALSA/PipeWire playback stream -> `q6apm` frontend (MultiMedia) -> `q6apmbedai USB_RX` -> `q6usb` -> QMI/xHCI sideband -> USB DAC
- DLNA endpoint:
  - `gmediarender` service receives QPlay/DLNA stream -> ALSA sink `q6a_usb_offload_192k`
- Bluetooth endpoint:
  - BlueZ + PipeWire A2DP (aptX HD/LDAC enabled in WirePlumber config) -> ALSA sink `q6a_usb_offload_192k`

## 5) Bluetooth full-offload status

- Mainline open-source stack does **not** provide end-to-end aptX HD/LDAC DSP offload implementation on this path.
- This hotfix provides:
  - codec negotiation (aptX HD/LDAC) in user space,
  - then USB output leg offload through q6usb/QMI/xHCI sideband.

That is the maximum reproducible open implementation without proprietary BT DSP offload modules/firmware interfaces.
