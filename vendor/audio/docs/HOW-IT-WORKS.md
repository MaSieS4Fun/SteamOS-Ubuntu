# How SM8550 board audio profiles work

## Stack

1. Kernel ASoC card `AYN-Odin2` (`snd_soc_sc8280xp`), DT `qcom,sm8550-sndcard`
2. ADSP firmware under `qcom/sm8550/ayn/odin2/` (+ `aw883xx_acf.bin`)
3. ALSA UCM verb **HiFi** from `/usr/share/alsa/ucm2/AYN/Odin2/`
4. PipeWire opens the card with `api.alsa.use-acp=true`
5. ACP turns UCM devices (Speaker / Headphones / DisplayPort) into selectable
   profile combinations and also exposes built-in **pro-audio** (raw `hw:0,N`)

No custom PipeWire policy is required for coexistence. Optional
`99-sm8550-buffers.conf` raises min quantum to 512 to reduce underruns.

**Pro Audio is fallback only** (raw PCM debugging). Daily driver is always a
HiFi combination profile. Optional WirePlumber drop-in
`51-sm8550-hifi-priority.conf` prefers HiFi over pro-audio when no sticky
profile is stored.

## HiFi.conf mapping

| UCM SectionDevice | PCM | Jack | Meaning |
|---|---|---|---|
| Speaker | `hw:Card,0` (MultiMedia1) | — | Internal speakers |
| Headphones | `hw:Card,1` via RX_CODEC_DMA | `Headphone Jack` | mini-jack playback |
| DisplayPort | `hw:Card,1` via DISPLAY_PORT_RX_0 | `DP0 Jack` | HDMI/DP audio |

DisplayPort EnableSequence remuxes **MultiMedia2** to DP only. It does **not**
`JackHWMute` the speakers and does **not** disable `PRIMARY_MI2S_RX` /
MultiMedia1, so Speaker (MM1) and DisplayPort (MM2) can coexist. Headphones
still use `JackHWMute Speaker` for the mini-jack.

**Pro Audio** bypasses UCM exclusivity and exposes raw PCMs (speakers + jack).

## HiFi + HDMI/DP watcher

`/usr/libexec/steamos-ubuntu/sm8550-prefer-speaker-sink` (user unit
`sm8550-prefer-speaker-sink.service`, `Type=simple` / `--watch`) applies:

| DP jack / DRM | Card profile | Default sink |
|---|---|---|
| connected | `HiFi (DisplayPort, Speaker)` | DisplayPort |
| disconnected | `HiFi (Headphones, Speaker)` | Speaker (or Headphones if jack on) |

It polls every ~2s for DP jack / `/sys/class/drm/card*-DP-*/status` flips and
never selects `pro-audio`. Thor uses the same `platform-sound` + `DP0 Jack`
pattern, so no device-specific unit is required.

## What this drop-in provides

Board UCM under `ucm2/AYN/Odin2` (and Thor), `conf.d/sm8550` symlinks, and any
firmware bits not already in the kernel firmware tree. Shared `wcd938x` /
`qcom-lpass` includes normally come from distro `alsa-ucm-conf`
(see `ucm2-shared-reference/` if the distro copy is too old).
