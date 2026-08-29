# SM8550 audio drop-in — AYN Odin 2 / Thor
#
# Board ALSA UCM, ADSP firmware extras, and optional PipeWire buffer tuning
# for Ubuntu Resolute images built by sm8550-resolute.
#
# Profiles (Plasma / PipeWire ACP, no custom WirePlumber policy required):
#
# | UI label                                      | Role                          |
# |-----------------------------------------------|-------------------------------|
# | HiFi quality Music. (DisplayPort, Speaker)    | HDMI / DisplayPort audio      |
# | HiFi quality Music. (Headphones, Speaker)     | 3.5 mm jack (when plugged)    |
# | Pro Audio                                     | Speakers + mini-jack (raw PCM)|
# | Off                                           | —                             |

## Layout

```
vendor/audio/
  ucm2/AYN/Odin2/          # board UCM (required)
  ucm2/AYN/Thor/           # sibling board
  ucm2/conf.d/sm8550/      # driver lookup symlinks
  firmware/qcom/sm8550/    # ADSP + AW883xx + topology extras
  pipewire/                # optional min-quantum=512
  ucm2-shared-reference/   # wcd938x + qcom-lpass if alsa-ucm-conf is too old
  docs/                    # notes and a reference runtime snapshot
  scripts/
    install-into-rootfs.sh
    40-customize-snippet.sh
```

## Image build

`scripts/40-customize-image.sh` installs this tree automatically when
`vendor/audio/` is present (UCM + firmware merge after the kernel firmware stage).

Manual install into a mounted rootfs:

```bash
sudo ./scripts/install-into-rootfs.sh /path/to/rootfs
```

Required packages on the image:

- `pipewire` `pipewire-pulse` `wireplumber` `pipewire-alsa`
- `alsa-ucm-conf` `alsa-utils`

## Verify after boot

```bash
cat /proc/asound/cards          # expect AYNOdin2 / sm8550
pactl list cards                # HiFi (DisplayPort, Speaker) + pro-audio
wpctl status
```

The kernel must expose `qcom,sm8550-sndcard` and load the usual LPASS/WCD/AW88166
stack. Firmware paths must match the device tree
(`qcom/sm8550/ayn/odin2/adsp.mbn`, etc.).

## Authorship

UCM files: Teguh Sobirin `<teguh@sobir.in>` (as commonly shipped for AYN SM8550 boards).
