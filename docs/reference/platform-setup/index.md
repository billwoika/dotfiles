# Platform Setup

This section covers machine-level setup — the work that happens after
a fresh OS install and before `bootstrap.sh` runs. It is the
prerequisite to the [Onboarding Runbook](../onboarding.md).

## Why a separate section

The framework's shell configuration, toolchain orchestration, and git
identity setup are platform-agnostic. `bootstrap.sh` runs identically
on macOS and Linux. But the *machine* under that framework is not
agnostic — each platform has its own package manager, init system,
firewall, filesystem defaults, and system services that need to be
configured correctly before the framework's tools can do their job.

This section handles that platform-specific layer so the onboarding
runbook can remain clean and cross-platform.

## The asymmetry

These pages are deliberately unequal in length:

- **macOS** is the shortest. Most macOS development machines arrive
  with MDM profiles applied, FileVault enabled, and system preferences
  locked. The page covers what MDM does not: developer tools, Homebrew,
  system settings that affect terminal and editor workflows.
- **Fedora** is the longest. A fresh Fedora Workstation install
  requires meaningful post-install optimization (dnf, codecs, SELinux
  posture, systemd services, GNOME tuning) before it is a productive
  development machine.
- **Debian/Ubuntu** is middle-ground. Ubuntu's defaults are
  developer-friendly but its snap strategy creates friction that needs
  addressing.

The asymmetry reflects reality: some platforms need more pre-framework
work than others. We do not pad the short pages or trim the long ones
for symmetry.

## Pages

- **[Disk and Partition Strategy](disk-strategy.md)** — partition
  schemes, LVM configuration, filesystem selection (ext4, Btrfs, XFS,
  ZFS), RAID, swap strategy, and encryption layout for development
  workstations. Read this before installing — these decisions are
  hardest to change after the fact.
- **[Firmware Checklist](firmware-checklist.md)** — the actionable
  subset of the [Firmware and UEFI](../firmware/index.md) section,
  distilled into a first-boot checklist. What to verify before the OS
  installer runs (boot mode, storage mode, Secure Boot, virtualization),
  what to check after installation (sleep states, TPM, Thunderbolt),
  and what to tune later.
- **[macOS](macos.md)** — Xcode CLT, Homebrew, system preferences for
  developers, Rosetta, disk encryption verification.
- **[Fedora](fedora.md)** — dnf optimization, RPM Fusion, codecs,
  firmware, SELinux, firewalld, systemd services, GNOME tuning,
  developer prerequisites.
- **[Debian / Ubuntu](debian-ubuntu.md)** — apt configuration,
  backports, snap removal, codecs, ufw, systemd services, developer
  prerequisites.

## After this section

Once the machine is configured, proceed to the
[Onboarding Runbook](../onboarding.md) for framework installation.
