# Firmware and UEFI

Firmware is the first code that runs when a machine powers on. It
initializes hardware, enumerates devices, configures memory, and
hands control to an operating system. On a Mac, this layer is
invisible — Apple controls the firmware, the bootloader, and the OS,
and the user interacts with none of it. On a Linux workstation, this
layer is yours to configure, and the choices made here affect
everything above: whether the OS can see all installed storage,
whether virtualization works, whether the machine sleeps correctly,
whether Secure Boot permits your kernel to load, and whether the
hardware runs at the performance it is capable of.

This section is comprehensive because the topic demands it. Firmware
configuration is surrounded by more mystery and cargo-cult advice
than almost any other area of workstation setup. Forum posts say
"disable Secure Boot" without explaining what Secure Boot does or
what you lose by disabling it. BIOS menus present hundreds of
settings with no indication of which ones matter. Vendor
documentation assumes either a data center audience or a consumer
who will never open the settings screen. The result is that most
Linux users either accept defaults they do not understand or change
settings based on advice they cannot evaluate.

This section aims to fix that. Every setting discussed includes what
it does, why it exists, and when to change it.

## Audience

This section applies to **Linux workstation users** — engineers
running Fedora, Debian, Ubuntu, or similar distributions on
physical hardware. It is irrelevant to macOS users (Apple's firmware
is not user-configurable), to VM users (the hypervisor abstracts the
firmware layer), and to cloud instance users (the cloud provider
manages firmware).

If the machine has a BIOS/UEFI setup screen you can enter at boot,
this section is for you.

## The firmware landscape

The firmware on a modern x86 machine is almost certainly based on
the UEFI specification, implemented by one of a small number of
vendors. Understanding which firmware your machine runs helps
interpret the settings screens, find documentation, and diagnose
boot problems.

| Firmware | Vendor | Common platforms | Base | License |
|----------|--------|-----------------|------|---------|
| **TianoCore EDK II** | Intel / Community | Reference implementation for all platforms | N/A (it *is* the base) | Open source (BSD) |
| **AMI Aptio** | American Megatrends | DIY motherboards, servers, desktops | TianoCore EDK II | Proprietary |
| **InsydeH2O** | Insyde Software | Laptops, mobile devices, embedded | TianoCore EDK II | Proprietary |
| **Dell BIOS** | Dell | Dell desktops, laptops, servers | AMI Aptio or InsydeH2O (varies by model) | Proprietary |
| **Lenovo BIOS** | Lenovo | ThinkPad, ThinkCentre, ThinkStation | AMI Aptio or InsydeH2O (varies by model) | Proprietary |
| **Sony/VAIO BIOS** | Sony / VAIO Corp | VAIO laptops | InsydeH2O (historically AMI) | Proprietary |
| **HP BIOS** | HP | ProBook, EliteBook, Z-series | InsydeH2O (consumer) or AMI (workstation) | Proprietary |

The hierarchy matters: TianoCore EDK II is the open-source reference
implementation of the UEFI specification. AMI and Insyde build
proprietary firmware on top of it. Dell, Lenovo, HP, and Sony build
OEM layers on top of AMI or Insyde — adding their own settings
screens, branding, and platform-specific options. A Dell XPS and a
Lenovo ThinkPad may both run InsydeH2O underneath, but their setup
screens look completely different because the OEM layer is different.

When searching for firmware documentation or troubleshooting boot
issues, knowing the stack helps. A ThinkPad T14 running InsydeH2O
will respond to different EFI shell commands than a desktop
motherboard running AMI Aptio. The OEM layer determines the menu
structure. The underlying framework determines the actual
capabilities.

### Identifying your firmware

```bash
# UEFI firmware vendor and version
sudo dmidecode -t bios

# More concise
sudo dmidecode -s bios-vendor
sudo dmidecode -s bios-version
sudo dmidecode -s bios-release-date

# From sysfs (no root required on some systems)
cat /sys/class/dmi/id/bios_vendor
cat /sys/class/dmi/id/bios_version
```

## UEFI vs BIOS

### Legacy BIOS

The original IBM PC BIOS (Basic Input/Output System) dates to 1981.
It was designed for 16-bit real-mode processors, 640KB of
conventional memory, and hard drives measured in megabytes. The boot
process was simple: the BIOS loaded the first 512 bytes of the first
bootable disk (the Master Boot Record), jumped to it, and the MBR's
code took over from there.

Legacy BIOS persisted for over three decades through backward
compatibility. A machine built in 2010 could still boot as though
it were an IBM PC/AT from 1984 — the same real-mode initialization,
the same 512-byte MBR, the same 2TB disk size limit (a consequence
of MBR's 32-bit logical block addressing). This compatibility was
both the BIOS's greatest strength and its eventual limitation:
modern hardware simply outgrew the assumptions.

Legacy BIOS limitations that UEFI addresses:

- **2TB disk limit.** MBR uses 32-bit LBAs with 512-byte sectors.
  2^32 * 512 = 2TB. Disks larger than 2TB cannot be used as boot
  devices under legacy BIOS.
- **Four primary partitions.** MBR supports a maximum of four
  primary partitions. Extended partitions work around this but add
  complexity and fragility.
- **16-bit real mode.** BIOS initialization runs in 16-bit real
  mode, limiting the firmware's ability to address memory, run
  complex drivers, or present a graphical interface.
- **No standardized boot manager.** The MBR contains both a
  partition table and boot code in 512 bytes. Multi-boot
  configurations require third-party bootloaders that overwrite the
  MBR.
- **No secure boot chain.** There is no mechanism for verifying
  that the bootloader, kernel, or drivers have not been tampered
  with.

### UEFI

The Unified Extensible Firmware Interface (UEFI) replaces legacy
BIOS with a specification designed for modern hardware. It was
originally developed by Intel as EFI in the late 1990s for the
Itanium platform and evolved into UEFI through the UEFI Forum, a
consortium of hardware and software vendors.

UEFI provides:

- **GPT partitioning.** GUID Partition Table supports disks up to
  9.4 ZB (zettabytes) and up to 128 partitions by default.
- **EFI System Partition (ESP).** A FAT32 partition (typically
  mounted at `/boot/efi`) that contains bootloader executables. The
  firmware reads the ESP directly — no MBR boot code required.
- **Boot manager.** UEFI maintains its own boot entry list stored
  in NVRAM. Each entry points to a specific `.efi` executable on the
  ESP. The `efibootmgr` utility manages these entries from Linux.
- **Driver model.** UEFI can load drivers from the ESP, enabling
  firmware-level support for network booting, storage controllers,
  and graphical output without OS involvement.
- **Secure Boot.** A chain-of-trust mechanism that verifies
  bootloader and kernel signatures against keys stored in firmware.
  Covered in detail in the [Secure Boot](secure-boot.md) page.
- **Pre-boot environment.** UEFI provides a shell (the EFI shell)
  and pre-boot applications that can run before any OS loads —
  useful for diagnostics, firmware updates, and boot recovery.

### Legacy boot (CSM)

The Compatibility Support Module (CSM) is UEFI's backward
compatibility layer. When CSM is enabled, the firmware can boot
legacy MBR-partitioned disks using the old BIOS boot process. This
is occasionally necessary for older operating systems or specialized
tools that do not support UEFI.

For a modern Linux workstation, **CSM should be disabled.** CSM
enabled means:

- The firmware may attempt legacy boot before UEFI boot, producing
  confusing boot failures.
- Secure Boot is unavailable (it requires pure UEFI mode).
- GPT partitioning may not be used for the boot disk on some
  firmware implementations.
- Some firmware enters a hybrid mode with reduced UEFI
  functionality.

The only reason to enable CSM on a development workstation in 2026
is dual-booting with an OS that requires legacy boot — a
diminishingly rare scenario.

### Determining your boot mode

```bash
# If this directory exists, the system booted in UEFI mode
ls /sys/firmware/efi

# If it does not exist, the system booted in legacy BIOS mode
# (or is a VM without EFI firmware configured)
```

## Accessing firmware settings

The method for entering firmware setup varies by vendor and is the
first source of confusion for many users.

| Vendor | Key at POST | Notes |
|--------|------------|-------|
| **Lenovo ThinkPad** | F1 (or Enter, then F1) | ThinkPads often require Enter first to interrupt boot, then F1 for BIOS Setup, F12 for Boot Menu |
| **Dell** | F2 (Setup), F12 (Boot Menu) | Consistent across most Dell lines |
| **HP** | F10 (Setup), F9 (Boot Menu) | Esc opens a startup menu on some models |
| **AMI Aptio (DIY boards)** | Del or F2 | Most ASUS, MSI, Gigabyte, ASRock boards use Del |
| **InsydeH2O (generic)** | F2 | Common default for Insyde-based OEM firmware |
| **Sony/VAIO** | F2 (or ASSIST button) | Some VAIO models have a dedicated ASSIST button |

On a running Linux system, you can request a reboot directly into
firmware setup:

```bash
# systemd-based systems
sudo systemctl reboot --firmware-setup

# This sets an EFI variable that tells the firmware to enter setup
# on the next boot, then reboots. Avoids the key-press timing game.
```

### Serial console access

Firmware setup screens are designed for a locally attached keyboard
and display. For headless servers, remote workstations, or machines
where the display output is not available, most enterprise and
server-class firmware supports serial console access — redirecting
the firmware interface over a serial (RS-232) or USB-serial
connection.

Serial console is configured in firmware under names like **Console
Redirection**, **Serial Port Console Redirection**, or **Remote
Access** (varies by vendor). The typical settings:

| Setting | Common value | Notes |
|---------|-------------|-------|
| Console Redirection | Enabled | Redirects firmware output to serial |
| Terminal Type | VT-UTF8 or VT100+ | VT-UTF8 is correct for modern terminal emulators |
| Baud Rate | 115200 | Match this on the connecting terminal |
| Data Bits | 8 | Standard |
| Parity | None | Standard |
| Stop Bits | 1 | Standard |
| Flow Control | None or Hardware | Hardware (RTS/CTS) if the cable supports it |

On the Linux side, the kernel must also be told to use the serial
console:

```bash
# In /etc/default/grub (or grub configuration)
GRUB_CMDLINE_LINUX="console=tty0 console=ttyS0,115200n8"
GRUB_TERMINAL="serial console"
GRUB_SERIAL_COMMAND="serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1"
```

The `console=` parameter can be specified multiple times. The last
one becomes the primary console (where kernel messages and login
prompts appear); earlier ones also receive output. Specifying both
`tty0` (the local display) and `ttyS0` (the serial port) keeps
both active.

### VGA and display settings

Firmware controls the initial display output — which port is active
at POST, what resolution is used, and whether integrated or discrete
graphics is primary. These settings matter for Linux workstations
because the kernel inherits the firmware's display state during
early boot, before the GPU driver loads.

Common firmware display settings:

**Primary Display / Init Display First.** Selects which GPU
produces output at boot: integrated (iGPU), discrete (dGPU), or
auto-detect. On machines with both, "auto" typically selects the
discrete GPU if one is detected. Set this to match where your
monitor is plugged in — a mismatch produces a blank screen at POST
and during early boot, which looks like a hang.

**iGPU Multi-Monitor / IGD Multi-Monitor.** On Intel platforms,
this setting determines whether the integrated GPU remains active
when a discrete GPU is installed. Enabling it allows the iGPU to
drive additional displays independently of the dGPU. Disabling it
frees the memory and interrupt resources the iGPU would otherwise
claim.

**DVMT Pre-Allocated.** The amount of system memory pre-allocated
to the Intel integrated GPU. The default (typically 64MB) is
sufficient for most development workstations. Increase only if
using the iGPU for high-resolution multi-monitor setups without a
discrete GPU.

**Above 4G Decoding.** Required for GPUs with large BARs (Base
Address Registers) — primarily high-end discrete GPUs with large
VRAM. If this is disabled and the GPU has more than 4GB of VRAM,
the system may fail to map the full VRAM space. Enable it on any
machine with a modern discrete GPU.

## Pages

The following pages cover each firmware domain in detail:

- **[Hardware Topology](hardware-topology.md)** — northbridge,
  southbridge, the modern SoC reality, and what talks to what.
- **[ACPI](acpi.md)** — power states, device enumeration, thermal
  management, ACPI tables, and the kernel's relationship with
  firmware.
- **[Secure Boot](secure-boot.md)** — the chain of trust, MOK
  management, DKMS, and when to disable vs when to enroll keys.
- **[Virtualization](virtualization.md)** — VT-x, VT-d, AMD-V,
  IOMMU, SVM, and nested virtualization.
- **[TPM](tpm.md)** — Trusted Platform Module, disk encryption,
  measured boot, and the developer workstation case.
- **[Storage](storage.md)** — AHCI, NVMe, RAID mode, and
  implications for Linux installers.
- **[USB and Thunderbolt](usb.md)** — USB configuration, power
  delivery, Thunderbolt security levels, and legacy USB support.
- **[PCI and PCIe](pcie.md)** — lane allocation, bifurcation, ASPM,
  and resizable BAR.
- **[Power and Thermal](power-thermal.md)** — sleep states, ACPI
  S-states, wake-on-LAN, fan curves, and battery management.
- **[Boot Management](boot-management.md)** — boot order, EFI boot
  entries, efibootmgr, and recovery.
- **[GRUB](grub.md)** — GRUB 2 configuration, kernel parameters,
  multi-boot, rescue, and the EFI shim chain.
- **[Firmware Updates](firmware-updates.md)** — fwupd, LVFS, vendor
  tools, and the risk calculus.

## After this section

Firmware configuration is a prerequisite for the platform-specific
setup guides. Once firmware is configured correctly:

- Fedora users proceed to [Fedora setup](../platform-setup/fedora.md)
- Debian/Ubuntu users proceed to
  [Debian / Ubuntu setup](../platform-setup/debian-ubuntu.md)
- macOS users can skip this section entirely — Apple manages
  firmware and does not expose configuration to the user.
