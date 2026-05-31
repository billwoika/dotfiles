# Firmware Checklist

The [Firmware and UEFI](../firmware/index.md) section documents every
firmware setting in detail — what it does, why it exists, and when to
change it. This page distills that into an actionable checklist for
setting up a new machine.

The distinction matters: the firmware section is a reference for
understanding and tuning. This page is a runbook for first boot. Go
through it before installing the operating system. Firmware settings
that are wrong at install time produce problems that are confusing to
diagnose later — a Linux installer that cannot see the NVMe drive, a
kernel that panics on boot, a machine that will not sleep correctly —
because the symptoms appear to be OS problems when the cause is
firmware.

## Before OS installation

These settings must be correct before the OS installer runs. Getting
them wrong means reinstalling or, at minimum, booting from a live
USB to fix the bootloader.

### Boot mode: UEFI only

**Check:** Boot mode is set to UEFI, not Legacy or CSM.

**Where to find it:** Boot → Boot Mode, or Security → Secure Boot →
Boot Mode, or Advanced → CSM Configuration. Varies by vendor.

**What to set:**

- Boot Mode: **UEFI**
- CSM / Legacy Support: **Disabled**

**Why:** Legacy BIOS boot limits disk size to 2TB, uses MBR instead
of GPT, and prevents Secure Boot. Every modern Linux distribution
expects UEFI. If CSM is enabled, the installer may boot in legacy
mode and create an MBR partition table — producing a system that
works but cannot use Secure Boot, cannot boot from disks larger
than 2TB, and will require a reinstall to convert to UEFI later.

See [UEFI vs BIOS](../firmware/index.md#uefi-vs-bios) for the full
explanation.

### Storage mode: AHCI

**Check:** SATA controller mode is set to AHCI, not RAID or RST.

**Where to find it:** Advanced → SATA Configuration, or
Configuration → Storage, or Chipset → SATA Mode. Varies by vendor.

**What to set:**

- SATA Mode / SATA Controller Mode: **AHCI**
- Intel RST / Intel Rapid Storage: **Disabled** (if listed
  separately)
- Intel VMD: **Disabled** (unless NVMe RAID is specifically needed)

**Why:** When the SATA controller is in RAID/RST mode, Linux
installers cannot see SATA or M.2 SATA drives — the drives exist
but the installer does not have a driver for the RST controller
interface. This is the single most common "installer can't find my
disk" problem. Intel VMD similarly hides NVMe drives behind a
virtual controller.

See [Storage](../firmware/storage.md) for details on AHCI vs RAID
and VMD.

!!! warning "Dual-boot caution"

    If Windows is already installed with the storage controller in
    RST mode, switching to AHCI will prevent Windows from booting.
    The fix is documented in the
    [Storage page](../firmware/storage.md#sata-controller-modes) —
    boot Windows into Safe Mode before switching, then reboot
    normally after the switch.

### Secure Boot: leave enabled

**Check:** Secure Boot is enabled.

**Where to find it:** Security → Secure Boot, or Boot → Secure
Boot Configuration.

**What to set:**

- Secure Boot: **Enabled**
- Secure Boot Mode: **Standard** (not Custom, unless enrolling
  your own platform keys)

**Why:** Most Linux distributions (Fedora, Ubuntu, Debian) support
Secure Boot out of the box via the shim bootloader chain. Disabling
Secure Boot is almost never necessary and removes a real security
boundary. If a DKMS module (NVIDIA drivers, VirtualBox, ZFS)
requires it, the correct fix is MOK key enrollment, not disabling
Secure Boot.

See [Secure Boot](../firmware/secure-boot.md) for the chain of
trust, MOK enrollment, and the specific cases where disabling is
justified.

### Virtualization: enable

**Check:** CPU virtualization extensions are enabled.

**Where to find it:** Advanced → CPU Configuration, or Security →
Virtualization, or Advanced → Virtualization Technology.

**What to set (Intel):**

- Intel Virtualization Technology (VT-x): **Enabled**
- Intel VT-d (Directed I/O): **Enabled**

**What to set (AMD):**

- SVM Mode / AMD-V: **Enabled**
- IOMMU / AMD-Vi: **Enabled**

**Why:** Docker, Podman, QEMU/KVM, and most container runtimes
require hardware virtualization. Without VT-x/AMD-V, containers
run in degraded mode or refuse to start. VT-d/IOMMU provides DMA
remapping — a security boundary that is especially important if
the machine has Thunderbolt ports (which allow direct memory access
from connected devices).

On many laptops, virtualization is **disabled by default**. This is
the first setting to check if Docker or Podman fails to start on a
new machine.

See [Virtualization](../firmware/virtualization.md) for VT-x, IOMMU,
and nested virtualization.

### Display output: verify primary

**Check:** The primary display setting matches where the monitor is
plugged in.

**Where to find it:** Advanced → Graphics Configuration, or
Chipset → Primary Display, or Advanced → Display.

**What to check:**

- If using a discrete GPU: Primary Display should be set to
  **PCIe** or **Auto** (not iGPU/Integrated)
- If using integrated graphics only: **iGPU** or **Auto**

**Why:** A mismatch produces a blank screen during POST and early
boot. The machine is running — it just has no video output until
the OS loads its GPU driver. This looks like a hang but is actually
a firmware display routing issue.

See [VGA and display settings](../firmware/index.md#vga-and-display-settings)
for DVMT allocation and multi-monitor configuration.

## After OS installation

These settings can be checked and adjusted after the OS is running.
They do not affect the installation itself but do affect daily use.

### Sleep state: verify S3 availability

**Check:** Whether the machine supports S3 (suspend to RAM) or only
S0ix (Modern Standby).

**How to check from Linux:**

```sh
cat /sys/power/mem_sleep
# [s2idle] deep   → both available, S0ix is default
# s2idle [deep]   → both available, S3 is default
# [s2idle]        → S0ix only, S3 not available
```

**What to do:**

- If both are available and S3 is preferred (lower power draw in
  sleep), set `mem_sleep_default=deep` in the kernel command line
  via GRUB.
- If only S0ix is available, check whether the firmware has a hidden
  option to re-enable S3. Lenovo ThinkPads: Config → Power → Sleep
  State → "Linux" or "Windows and Linux."
- If S0ix is the only option and battery drain in sleep is
  excessive, see the
  [Power and Thermal](../firmware/power-thermal.md) page for tuning.

### TPM: verify and consider enrollment

**Check:** TPM is enabled and version 2.0.

**How to check from Linux:**

```sh
# Is TPM detected?
ls /dev/tpmrm0

# What version?
cat /sys/class/tpm/tpm0/tpm_version_major
# Should print "2"
```

**What to do:**

- If `/dev/tpmrm0` does not exist, enable TPM in firmware
  (Security → TPM / Security Chip / Intel PTT / AMD fTPM).
- If using LUKS full-disk encryption, consider enrolling the TPM
  for automatic unlock at boot. See
  [TPM](../firmware/tpm.md#disk-encryption-with-tpm) for the
  `systemd-cryptenroll` procedure.

### Thunderbolt security: set level

**Check:** Thunderbolt security level is not None (Level 0).

**How to check from Linux:**

```sh
# Requires bolt to be installed
boltctl domains
```

**What to set:** Level 1 (User Authorization) or Level 2 (Secure
Connect). Level 0 gives any Thunderbolt device unrestricted DMA
access to system memory.

Only relevant on machines with Thunderbolt ports. See
[USB and Thunderbolt](../firmware/usb.md#thunderbolt-security-levels).

### Battery charge thresholds (laptops)

**Check:** Whether the laptop supports charge thresholds.

**How to check from Linux:**

```sh
# ThinkPads and some other laptops
cat /sys/class/power_supply/BAT0/charge_control_end_threshold
```

**What to set:** For machines that spend most of their time plugged
in, setting start/stop thresholds (e.g., 75%/80%) significantly
extends battery longevity. Lithium-ion batteries degrade faster
when kept at 100% continuously.

See [Power and Thermal](../firmware/power-thermal.md#charge-thresholds)
for ThinkPad-specific configuration and TLP/tlp integration.

## Optional tuning

These settings have no impact on a basic working system. Adjust
them when a specific need arises.

| Setting | When to change | Reference |
|---------|---------------|-----------|
| Above 4G Decoding | Discrete GPU with 8GB+ VRAM | [PCI and PCIe](../firmware/pcie.md#above-4g-decoding) |
| Resizable BAR | Discrete GPU from 2020+ | [PCI and PCIe](../firmware/pcie.md#resizable-bar-rebar-smart-access-memory-sam) |
| PCIe ASPM | Laptop battery life vs latency | [PCI and PCIe](../firmware/pcie.md#aspm-active-state-power-management) |
| Fan curves | Desktop with configurable fans | [Power and Thermal](../firmware/power-thermal.md#firmware-fan-curve-settings) |
| CPU power limits (PL1/PL2) | Performance tuning on desktop | [Power and Thermal](../firmware/power-thermal.md#cpu-power-limits-pl1pl2) |
| Wake-on-LAN | Remote wake needed | [Power and Thermal](../firmware/power-thermal.md#wake-on-lan) |
| USB legacy support | Keyboard not working in firmware | [USB and Thunderbolt](../firmware/usb.md#usb-legacy-support) |
| XHCI Hand-off | USB devices fail after OS boots | [USB and Thunderbolt](../firmware/usb.md#xhci-hand-off) |
| Nested virtualization | VMs inside VMs | [Virtualization](../firmware/virtualization.md#nested-virtualization) |
| Serial console | Headless or remote machines | [Serial console access](../firmware/index.md#serial-console-access) |

## The checklist as a table

For quick reference during setup:

| Setting | Required value | Default usually correct? | Check before install? |
|---------|---------------|--------------------------|----------------------|
| Boot mode | UEFI | Often yes | **Yes** |
| CSM | Disabled | Often yes | **Yes** |
| SATA mode | AHCI | No (often RST on Intel) | **Yes** |
| Intel VMD | Disabled | Varies | **Yes** |
| Secure Boot | Enabled | Yes | Verify |
| VT-x / AMD-V | Enabled | No (often disabled on laptops) | **Yes** |
| VT-d / IOMMU | Enabled | Varies | **Yes** |
| Primary display | Matches monitor | Usually | Verify |
| Sleep state | S3 if available | Varies | After install |
| TPM | Enabled, v2.0 | Usually enabled | After install |
| Thunderbolt security | Level 1+ | Varies | After install |
| Charge thresholds | 75/80 for plugged-in laptops | Not set | After install |
