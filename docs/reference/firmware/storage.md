# Storage

Firmware storage settings control how the system communicates with
storage devices — the protocol, the controller mode, and the
discovery mechanism. A misconfigured storage setting is one of the
most common reasons a Linux installer cannot see an installed drive,
or a freshly installed system fails to boot.

These settings are straightforward once understood, but the
terminology is dense and the firmware menus are inconsistent across
vendors. This page explains what each setting does and why.

## Storage interfaces

Modern workstations use two primary storage interfaces. The
firmware must be configured to present the correct interface for
each device.

### SATA (Serial ATA)

SATA has been the standard storage interface since the mid-2000s.
SATA drives (both HDDs and 2.5" SSDs) connect via SATA ports on
the motherboard, communicate through the SATA controller (part of
the PCH — see [Hardware Topology](hardware-topology.md)), and are
managed by the AHCI protocol.

SATA III (the current and final version) signals at 6 Gb/s; after
8b/10b line encoding the usable payload ceiling is 4.8 Gb/s, about
600 MB/s. Real SATA SSDs reach ~550–560 MB/s, which is the practical
ceiling for any SATA device regardless of how fast the underlying
media is. A SATA SSD advertised at 560 MB/s sequential read is at the
effective limit of the interface.

### NVMe (Non-Volatile Memory Express)

NVMe is a storage protocol designed specifically for flash storage,
communicating over PCIe lanes instead of the SATA bus. NVMe drives
are physically M.2 form factor (the small, flat modules that slot
directly into the motherboard) or U.2 (2.5" form factor with PCIe
connector, primarily server/workstation).

NVMe performance depends on the PCIe generation and lane width:

| Interface | Per-lane bandwidth | Typical config | Max throughput |
|-----------|-------------------|----------------|----------------|
| PCIe 3.0 x4 | ~1 GB/s per lane | x4 | ~3.5 GB/s |
| PCIe 4.0 x4 | ~2 GB/s per lane | x4 | ~7 GB/s |
| PCIe 5.0 x4 | ~4 GB/s per lane | x4 | ~14 GB/s |

The key distinction: NVMe drives do not use the SATA controller or
the AHCI protocol. They communicate directly over PCIe. The
firmware's SATA settings (AHCI/RAID mode) do not affect NVMe
drives. The firmware's PCIe settings (lane allocation, generation)
do.

### M.2 slots: SATA or NVMe

The M.2 form factor supports both SATA and NVMe protocols. An M.2
slot on the motherboard may support:

- NVMe only (PCIe lanes routed to the slot)
- SATA only (SATA controller routed to the slot)
- Both (switched or shared)

The drive must match the slot's protocol. An NVMe drive in a
SATA-only M.2 slot will not be detected. A SATA M.2 drive in an
NVMe-only slot will not be detected. The motherboard manual
specifies which protocols each M.2 slot supports.

Firmware typically does not have a setting to switch M.2 slot
protocols — the routing is fixed in hardware. But some boards do
have settings that enable or disable specific M.2 slots or
configure lane sharing between M.2 slots and other PCIe devices.

## SATA controller modes

The firmware's SATA mode setting controls how the SATA controller
presents itself to the operating system. This is the setting that
causes the most confusion during Linux installation.

### AHCI (Advanced Host Controller Interface)

AHCI is the standard SATA controller mode. Each SATA port appears
as an independent device. The OS communicates with each drive
directly through the AHCI interface. Hot-plugging is supported.
Power management (HIPM/DIPM, partial/slumber states) is handled
per-port.

**AHCI is the correct setting for a Linux workstation.** Linux's
AHCI driver (`ahci`) is mature, stable, and performant. Every
Linux distribution supports AHCI out of the box.

### RAID mode (Intel RST / AMD RAIDXpert)

RAID mode activates the SATA controller's hardware RAID
capabilities (more accurately, firmware-assisted software RAID).
Under RAID mode, the SATA controller presents itself as a RAID
controller instead of an AHCI controller, and the individual
drives may not be visible to the OS without the vendor's RAID
driver.

**Intel Rapid Storage Technology (RST)** is Intel's RAID/storage
acceleration layer. When the firmware is set to "RST" or "Intel
RST Premium" mode, the SATA controller uses Intel's proprietary
interface instead of standard AHCI. Windows has a native RST driver.
Linux supports Intel RST/IMSM RAID volumes via the kernel `md` driver
and `mdadm` (using IMSM external metadata), but the cleaner path for a
Linux box is to switch the controller to AHCI in firmware and use
software RAID or Btrfs/ZFS instead.

This is the single most common reason a Linux installer cannot see
an installed SATA or M.2 SATA drive: the firmware is set to RST
mode, and the Linux installer does not have the RST driver. The
drives exist but the OS cannot talk to them through the RST
controller interface.

**The fix is to switch from RST/RAID mode to AHCI mode in
firmware.** The drives are the same; only the controller interface
changes.

**Caution on dual-boot systems:** If Windows was installed with the
SATA controller in RST mode, switching to AHCI will prevent
Windows from booting (Windows installed drivers for the RST
controller, not the AHCI controller). The Windows fix is to boot
into Safe Mode (which loads generic drivers), switch the firmware
to AHCI, boot Safe Mode again, then reboot normally. Windows will
detect the AHCI controller and install the appropriate driver.

### IDE / Legacy mode

Some firmware offers an "IDE" or "Legacy" SATA mode that emulates
the ancient IDE/PATA interface. This exists solely for backward
compatibility with very old operating systems. There is no reason
to use IDE mode on a modern Linux system. It disables AHCI features
(NCQ, hot-plug, power management) and reduces performance.

## NVMe configuration in firmware

NVMe drives generally require no firmware configuration beyond
being physically installed. However, several firmware settings
affect NVMe behavior:

**NVMe RAID / VMD (Intel Volume Management Device).** Intel's VMD
is a technology that places NVMe drives behind a virtual controller
for RAID and LED management. When VMD is enabled in firmware, NVMe
drives are not directly visible to the OS — they appear as devices
behind the VMD controller. Like RST for SATA, this requires a
specific driver.

Linux support for VMD exists in the kernel (`vmd` module) but can
cause complications during installation. If the Linux installer
does not see NVMe drives and the machine is Intel-based, check
whether VMD is enabled in firmware and disable it unless NVMe RAID
is specifically needed.

**NVMe boot.** Most modern firmware supports booting from NVMe
directly. If an NVMe drive does not appear in the boot menu,
check:

1. Is the drive detected in firmware? (Usually visible in a
   "Storage" or "NVMe Configuration" section.)
2. Is there an EFI System Partition on the NVMe drive with a
   valid bootloader?
3. Is Secure Boot blocking the bootloader on the NVMe drive?

## Firmware storage detection

Firmware detects and enumerates storage devices during POST. The
detection results are visible in the firmware setup under sections
named "Storage Configuration," "SATA Configuration," "NVMe
Configuration," or "Boot."

```bash
# What the OS sees (should match firmware detection)
lsblk -d -o NAME,SIZE,MODEL,TRAN,ROTA
# TRAN column: sata, nvme, usb
# ROTA column: 0 = SSD, 1 = HDD

# NVMe-specific information
sudo nvme list

# SATA-specific information
sudo hdparm -I /dev/sda | head -20

# Detailed storage topology
lsblk -t  # Shows queue depth, scheduler, block size
```

If a drive appears in firmware but not in the OS, the issue is
usually the SATA controller mode (RST vs AHCI) or a missing
kernel module. If a drive does not appear in firmware, the issue
is physical — the drive is not seated correctly, the M.2 slot
does not support the drive's protocol, or the drive is faulty.

## Partition table: GPT vs MBR

The partition table format is not a firmware setting but is tightly
coupled to the firmware's boot mode:

| Boot mode | Partition table | Boot mechanism |
|-----------|----------------|----------------|
| UEFI | GPT | EFI System Partition → bootloader |
| Legacy BIOS | MBR | MBR boot code → bootloader |
| UEFI + CSM | Either (but GPT preferred) | Depends on CSM priority |

A modern Linux workstation should use **UEFI boot with GPT
partitioning.** This is the default for every current Linux
distribution's installer.

If the installer creates an MBR partition table, it has detected
the system as legacy-boot — which means either CSM is enabled in
firmware (disable it — see the [index page](index.md)) or the
installer was booted from media in legacy mode (re-create the
USB installer in UEFI mode).

## Storage-related kernel parameters

Occasionally useful for diagnosing or working around storage
issues at the firmware/kernel boundary:

| Parameter | Effect |
|-----------|--------|
| `ahci.mobile_lpm_policy=1` | Enable link power management for AHCI (laptop battery savings) |
| `libata.force=noncq` | Disable Native Command Queuing (work around buggy SATA firmware) |
| `nvme_core.default_ps_max_latency_us=0` | Disable NVMe power state transitions (fix NVMe drives that hang after sleep) |
| `nvme_core.multipath=N` | Disable NVMe multipath (fix duplicate device entries) |

These are added to the kernel command line via GRUB configuration.
As with [ACPI parameters](acpi.md), they are diagnostic tools — if
one is required permanently, document it and check for upstream
fixes in newer firmware or kernel versions.

## Questions to ask

1. Is the SATA controller set to AHCI? If it is set to RST or
   RAID and RAID is not in use, switch to AHCI.
2. Are all installed drives visible in both firmware and the OS?
   `lsblk` should match the firmware's storage detection.
3. Is Intel VMD enabled? If NVMe drives are not visible during
   Linux installation, VMD is the likely cause.
4. Is the partition table GPT? `sudo gdisk -l /dev/nvme0n1` or
   `sudo fdisk -l` will show the partition table type.
5. If dual-booting: were both operating systems installed with the
   same SATA controller mode? Switching modes after installation
   requires OS-specific remediation.
