# MaSi kernel overlays (post-Armbian)

Applied after the matching Armbian `sm8550-<major.minor>` patch set (live archive + `dt/` board trees) via `lib/kbuild/patches.sh`.

| File | Purpose |
|------|---------|
| `1000-add-qcom-haptics-driver.patch` | Qualcomm HV haptics driver (`qcom-hv-haptics`). Odin 3 then replaces this file with `odin3/haptics/` so PMIH0108 (HAP530) probes |
| `1002-haptics-driver-support-periodic-sine-and-fixes.patch` | Haptics sine/periodic + timing fixes |
| `1003-rsinput-add-ff.patch` | Route gamepad FF to PMIC haptics (controller rumble) |
| `1004-haptics-steam-ff-deadlock-fix.patch` | Safer HPWR brake poll + skip erase when idle |
| `1005-thor-ch13726a-reset-polarity-fix.patch` | Thor bottom AMOLED: fix inverted reset GPIO in `panel-ddic-ch13726a` |
| Thor touch (build hook + `fix-thor-screen/`) | `apply_masi_thor_touch_dts` in kernel; userspace via `output/.../fix-thor-screen/fix-thor.sh` — see `docs/THOR-TOUCH.md` |
| `1024-input-edt-ft5x06-retain-power-in-suspend.patch` | Thor bottom FT5452: skip power-off on deep suspend without wake IRQ |
| `1032-input-rsinput-suspend-resume-center-sticks.patch` | Center sticks + rumble cancel on suspend/resume |
| `1047-PCI-qcom-sm8550-skip-l23-and-suspend-opp.patch` | SM8550: skip PCIe L23 poll; honour `opp-suspend` |
| `1048-arm64-dts-qcom-sm8550-add-a-pcie-suspend-opp.patch` | `pcie0` suspend OPP 1000 kBps DDR/LLCC floor |
| `1049-regulator-qcom-rpmh-add-suspend-state-support.patch` | RPMH SLEEP/WAKE votes for `regulator-state-mem` |
| `1050-thermal-qcom-tsens-mask-lower-irqs-across-suspend.patch` | Mask TSENS LOWER IRQs in prepare |
| `1051-tty-serial-qcom-geni-mask-non-console-irq-on-suspend.patch` | Mask gamepad UART IRQ across suspend |
| `1052-input-rsinput-quiesce-mcu-and-drop-vdd-on-suspend.patch` | Drop MCU enable/reset/VDD in suspend |
| `1053` (retired) | **Do not apply.** The `software_node` on the DWC3 device duplicates sysfs and use-after-frees on dock unplug. Replaced in `apply-masi-energy.py` by `skip_phy_init` on the xHCI child |
| `1054` (overlay) | sdhci-msm: mask controller IRQs while runtime suspended (mmc0 IRQ storm) |
| `1055` (retired) | Do not boot the WCN from the resume thread. That holds the panel off or freezes the machine. Odin 3 keeps the endpoint out of D3cold and leaves the four PMU rails on |
| `1056-ath12k-resume-retry-mhi.patch` | WCN resume: 3s MHI wait, one cold start, then reset_work so the screen is not held on a dead radio |
| `1057-ath12k-resume-fbc-and-reinit.patch` | Reload WCN over FBC after resume returns, so the panel is not stuck in the MHI boot |
| `1058-pmic-glink-altmode-dp-retimer-fallback.patch` | If the DP retimer rejects the dock pin, program a pin it accepts so HDMI can come up |
| `1059-ath12k-resume-mission-before-qrtr.patch` | Reload the radio after resume returns. The reload itself starts three seconds later, once the panel is back |
| `1060-qrtr-mhi-wait-mission-mode.patch` | Reopen IPCR after resume on its own workqueue. The resume thread only queues that open |
| `1062-mhi-notify-clients-on-mission-mode.patch` | Tell bound MHI clients when the controller reaches mission mode |
| `1014-drm-hdmi-audio-hw-params.patch` | DP/HDMI: call `msm_dp_audio_prepare` from hdmi-codec `hw_params` |
| `1015-q6apm-dp-graph-start-on-trigger.patch` | DP/HDMI: defer `q6apm_graph_start` to PCM `trigger` |
| `1025-misc-fastrpc-adsp-sensor-pd-and-legacy-ioctl.patch` | FastRPC SensorsPD routing + PDR + Qualcomm legacy ioctl (gyro) |
| `1033-sound-aw88166-quiet-early-iis-probe.patch` | Odin/AYN: demote aw88166 early IIS/PLL retry `dev_err` → `dev_dbg` (panel spam ~21s boot) |
| `1026-dt-bindings-misc-qcom-fastrpc-pd-routing.patch` | DT bindings for `qcom,pd-type` / SensorsPD |
| `qcs8550-ayn-gyro-fastrpc.dtsi.frag` | Remote heap + SensorsPD FastRPC overrides (all AYN SM8550) |
| Gyro userspace | **External** project `giroscopio` (`./install.sh`) — not staged in kernel output; see `docs/GYRO.md` |
| `1013` | TSENS: skip uplow wake on all `qcom,sm8550` (PR #2954; was Thor-only) |
| `qcs8550-ayn-haptics.dtsi.frag` | Device-tree nodes for `pm8550b` haptics (all AYN boards) |
| `qcs8550-retroidpocket-rp6.dts` | Retroid Pocket 6 board DTS |
| `odin3/` | AYN Odin 3 (SM8750) DTS + SoC patches. ABL slot 0. Slots 1–6 unchanged. `0522`/`0524` keep SM8750 on s2idle (the shared cmdline requests deep, and a power tap does not wake that path). The four WCN PMU rails stay on in the sleep set; turning them back on at resume hangs the SoC. `0525` leaves the PCIe GDSC in retention. `0523` clears a charger USB role across suspend |

Patches `1006`–`1013` are the deep-suspend stack (ROCKNIX PR [#2952](https://github.com/ROCKNIX/distribution/pull/2952) / [#2954](https://github.com/ROCKNIX/distribution/pull/2954)). `1013` uses SoC-wide `qcom,sm8550` (not Thor-only). `1045`/`1046` are xiaodoudou UFS follow-ups (`recover-hibern8-enter-clk-gating`, `hold-clk-gating-across-system-pm`) needed so 7.2.8 does not hang in filesystem sync after a failed idle Hibern8 during suspend.

`1047`–`1052` plus `1054` are the SM8550 energy subset that stays compatible with MaSi **deep/S2RAM**: PCIe skip L23 + suspend OPP, RPMH `regulator-state-mem`, TSENS LOWER mask, GENI UART IRQ mask, rsinput MCU quiesce and sdhci IRQ mask. The former `1053` software_node is stripped. Host suspend still skips the extra xHCI PHY init, but the flag is a property of the xHCI child (`skip_phy_init`), which is the form Qualcomm sent after reverting the software_node. Do not boot the WCN from the resume thread: that holds the panel off or freezes the machine. On SM8750 the WCN7860 stays out of D3cold and its four PMU rails stay on across sleep (ARMADA, tested on Odin 3). Interconnect QoS (`0122`) is **not** carried (GMU HFI timeouts). Re-fetch with `scripts/fetch-rocknix-suspend-patches.py` only for **missing** 1006–1013 files. Set `SUSPEND_DEEP_PATCHES=0` to skip.

**Apply order:** `1011` (QMP RX LineCfg) runs before `1009`/`1010` so `ufs-qcom.c` hunks still match linux-7.0. The vendored `1011` also anchors on `qmp_ufs_init_registers()` (upstream name) instead of downstream `qmp_ufs_init()`.

Kconfig (also in `config/golden.config`): `CONFIG_INPUT_QCOM_HV_HAPTICS`, `CONFIG_JOYSTICK_RSINPUT`, `CONFIG_INPUT_FF_MEMLESS`.

See `docs/SUSPEND.md` for deep sleep testing and `docs/GYRO.md` for Thor/Odin 2 motion (ADSP Sensor Core → DSU :26760).

## AYANEO Pocket (SM8550)

- `ayaneo/` — common dtsi + ACE/DMG/DS/EVO/S1 board DTS (slots 9–13).
- `1020` AR02 DMG panel, `1021` AR11 DS secondary, `1022`/`1023` Renesas R63419 (Pocket S 2K).
- `sgm3804-regulator.c` — panel AVDD (`sgmicro,sgm3804`), built into the Image. Armbian `sm8550-7.2` no longer ships it; ACE/DMG/DS/S reference DTBs need it or the panel stays off.
- ICNA3512 (Pocket EVO and the DS main panel): the driver required `vdd`/`disp`/`blvdd`, which those DTBs do not have (only `vci` + `vddio`). Those three are optional. Portal still enables all five.
- ACE/DMG: `avee` is not in the DTB; the AR06/AR02 drivers no longer require it.
- DS lower panel: the DTB only has `avdd`; `vci`/`vddio` are no longer required.
- Pocket S 2K (slot 13) uses the kbuild DTB. The reference blob only exposed `avdd`, and the R63419 driver needs `vdd`/`vddio`/`vci`/`vsp`/`vsn`.
