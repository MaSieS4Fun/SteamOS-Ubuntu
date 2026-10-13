# Security Policy

## Supported versions

This project is experimental tooling for switching a single Mesa Vulkan library
on aarch64 devices. Use the latest `master` / release you build yourself.

## Reporting issues

Please open a GitHub issue describing:

- Device / SoC (e.g. AYN Odin 2 SM8550, AYN Odin 3 SM8750)
- Kernel version
- Mesa version being compiled or installed (including **devel** if applicable)
- Whether bundled patches were applied (Batocera sync / ROCKNIX UBO / A830 chip-id)
- Steps to reproduce (including `vkcube` / game symptoms)

Do **not** report security issues that depend on already having root / `pkexec`
access solely as “privilege escalation”; install/restore intentionally require
authentication.
