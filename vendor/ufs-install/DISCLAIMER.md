# DISCLAIMER — USE AT YOUR OWN RISK

**Read this entire document before running any script in this repository.**

## What these tools do

The scripts in **MaSi-OS-UFS-install** repartition the **internal UFS** storage on Qualcomm SM8550 handhelds (AYN Odin 2, Thor, Retroid Pocket 6, etc.) to install **MaSi-OS / Armbian Linux** alongside **Android**, using a **ROCKNIX ABL** dual-boot layout.

This is **not** a supported manufacturer procedure. It is an **experimental community tool**.

## Data loss

Running `install-masios-to-internal.sh` (unless using `--resume` / `--deploy-only` on **existing** MaSi-OS partitions only):

- **Wipes Android `userdata`** — all apps, photos, game saves, accounts, and settings on internal Android storage are **permanently erased** (equivalent to repartition + factory reset).
- **May destroy other data** on internal UFS if the partition table is modified incorrectly.
- **Does not automatically back up** your microSD Linux system before copying it to UFS.

**Back up anything important before proceeding.**

## Boot failure risk

After installation or a failed attempt:

- **Android may not boot** until you perform a **factory data reset** from recovery (expected after userdata wipe).
- **Linux may not boot** from microSD or from internal UFS if the kernel, partitions, or cmdline are wrong (black screen, hang, etc.).
- **Both systems can fail** at the same time, leaving the device unusable without recovery steps (recovery mode, SD boot, ABL “Uninstall ROCKNIX”, EDL flash, etc.).

## Requirements (your responsibility)

- **ROCKNIX ABL** already installed and working.
- Boot **MaSi-OS from microSD** (not from UFS) when running the installer.
- A **dual-boot `/boot/KERNEL`** built for your device (see your MaSi-OS kernel build / `update.sh` documentation). This repo does **not** build kernels.
- Correct **ABL device profile** (“Set the Device” → your exact model).

## No warranty

THE SOFTWARE IS PROVIDED **"AS IS"**, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, OR NON-INFRINGEMENT.

## Limitation of liability

IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES, OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT, OR OTHERWISE, ARISING FROM, OUT OF, OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE, INCLUDING BUT NOT LIMITED TO:

- Loss of data
- Bricked or unbootable devices
- Loss of Android or Linux functionality
- Hardware damage (including UFS wear or corruption in edge cases)

## Your acceptance

By cloning, downloading, or running these scripts, **you confirm that**:

1. You understand the risks above.
2. You have backed up data you care about.
3. You accept **full responsibility** for the outcome.
4. You will not hold the authors liable for any damage or data loss.

If you do not agree, **do not run the installer**.

## ARMADA layout

These scripts target the **MaSi-OS / ROCKNIX two-partition layout** (`ROCKNIX` + `STORAGE`). They are **not** compatible with **ARMADA** three-partition layouts. Use ARMADA-specific tools for those devices.

## License

Scripts are licensed under **GPL-2.0-or-later** (see [LICENSE](LICENSE)). The disclaimer above is additional safety information and does not replace the license terms.
