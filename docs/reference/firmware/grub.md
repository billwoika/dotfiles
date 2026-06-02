# GRUB

GRUB (GRand Unified Bootloader) is the bootloader used by the
majority of Linux distributions. It is the second stage of the boot
chain on UEFI systems — loaded by shim (see
[Secure Boot](secure-boot.md)) or directly by the firmware — and
its job is to present a boot menu, load the selected kernel and
initramfs into memory, and hand control to the kernel.

GRUB is simultaneously the most critical piece of software on a
Linux system (if it breaks, the system does not boot) and one of
the least understood. Most engineers interact with it only when
something goes wrong. This page covers how GRUB works, how to
configure it, and how to recover from failures.

## GRUB on UEFI systems

On a UEFI system, GRUB exists as an EFI application on the EFI
System Partition (ESP). The boot chain is:

```
Firmware → shim (shimx64.efi) → GRUB (grubx64.efi) → kernel + initramfs
```

GRUB's EFI binary and its configuration live on the ESP under
the distribution's directory:

```
/boot/efi/EFI/fedora/
├── shimx64.efi      # First-stage bootloader (signed by Microsoft)
├── grubx64.efi      # GRUB itself (signed by the distribution)
├── grub.cfg         # GRUB configuration (generated)
└── mmx64.efi        # MOK Manager (for key enrollment)
```

On some distributions (notably Fedora), the main `grub.cfg` on the
ESP is a stub that points to the full configuration on the root
filesystem:

```
# /boot/efi/EFI/fedora/grub.cfg (stub)
search --no-floppy --fs-uuid --set=dev <root-fs-uuid>
set prefix=($dev)/boot/grub2
export prefix
configfile $prefix/grub.cfg
```

The full configuration lives at `/boot/grub2/grub.cfg` (Fedora) or
`/boot/grub/grub.cfg` (Debian/Ubuntu).

## Configuration

GRUB's configuration file (`grub.cfg`) is **generated, not
hand-edited.** The generation tools differ by distribution:

| Distribution | Config location | Generator | Input files |
|-------------|----------------|-----------|-------------|
| Fedora | `/boot/grub2/grub.cfg` | `grub2-mkconfig` | `/etc/default/grub`, `/etc/grub.d/` |
| Debian/Ubuntu | `/boot/grub/grub.cfg` | `update-grub` (wrapper for `grub-mkconfig`) | `/etc/default/grub`, `/etc/grub.d/` |

**Never edit `grub.cfg` directly.** The next kernel update or
`grub-mkconfig` run will overwrite it. All customization goes into
`/etc/default/grub` (for settings) or scripts in `/etc/grub.d/`
(for menu entries).

### /etc/default/grub

The primary configuration file. Key settings:

```bash
# Default boot entry (0-indexed, or "saved" for last-booted)
GRUB_DEFAULT=0

# Timeout in seconds before booting the default entry
# Set to 0 for no menu (immediate boot)
GRUB_TIMEOUT=5

# Timeout style: "menu" (always show), "hidden" (show on keypress),
# "countdown" (show countdown)
GRUB_TIMEOUT_STYLE=menu

# Kernel command line parameters appended to every boot entry
GRUB_CMDLINE_LINUX="rd.luks.uuid=<uuid> resume=/dev/mapper/swap"

# Additional parameters appended only to the default (non-recovery) entry
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"

# Console + serial. NOTE: GRUB_TERMINAL overrides BOTH
# GRUB_TERMINAL_INPUT and GRUB_TERMINAL_OUTPUT, so do not also set
# GRUB_TERMINAL_OUTPUT — it would be ignored. Use either GRUB_TERMINAL
# alone (input+output together, as below), or only the split
# INPUT/OUTPUT keys — not a mix.
GRUB_TERMINAL="serial console"
GRUB_SERIAL_COMMAND="serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1"

# Disable OS detection (speeds up grub-mkconfig on single-boot systems)
GRUB_DISABLE_OS_PROBER=true

# Enable/disable recovery entries in the menu
GRUB_DISABLE_RECOVERY=false

# Graphics resolution for GRUB menu
GRUB_GFXMODE=auto

# Pass the graphics mode to the kernel (for a smooth boot splash)
GRUB_GFXPAYLOAD_LINUX=keep
```

After modifying `/etc/default/grub`, regenerate the configuration:

```bash
# Fedora
sudo grub2-mkconfig -o /boot/grub2/grub.cfg

# Debian/Ubuntu
sudo update-grub
```

### Kernel command line parameters

`GRUB_CMDLINE_LINUX` is where kernel boot parameters are set
permanently. Parameters discussed throughout this firmware section:

| Parameter | Purpose | Reference |
|-----------|---------|-----------|
| `acpi_osi=!` `acpi_osi="Linux"` | Override ACPI OS identification | [ACPI](acpi.md) |
| `acpi_backlight=vendor` | Fix laptop backlight control | [ACPI](acpi.md) |
| `acpi.ec_no_wakeup=1` | Prevent spurious EC wakes | [ACPI](acpi.md) |
| `intel_iommu=on` | Enable Intel IOMMU | [Virtualization](virtualization.md) |
| `iommu=pt` | IOMMU passthrough mode | [Virtualization](virtualization.md) |
| `pcie_aspm=off` | Disable PCIe power management | [PCI and PCIe](pcie.md) |
| `nvme_core.default_ps_max_latency_us=0` | Fix NVMe sleep issues | [Storage](storage.md) |
| `mem_sleep_default=deep` | Prefer S3 over S0ix | [Power and Thermal](power-thermal.md) |
| `resume=/dev/mapper/swap` | Swap device for hibernate | [Power and Thermal](power-thermal.md) |
| `console=ttyS0,115200n8` | Serial console output | [Firmware index](index.md) |

### /etc/grub.d/ scripts

The scripts in `/etc/grub.d/` generate sections of `grub.cfg`. They
run in lexicographic order:

| Script | Purpose |
|--------|---------|
| `00_header` | GRUB settings (timeout, default, etc.) |
| `10_linux` | Linux kernel entries (auto-detected) |
| `20_linux_xen` | Xen hypervisor entries |
| `30_os-prober` | Other operating systems (Windows, etc.) |
| `40_custom` | User-defined menu entries |
| `41_custom` | Additional user-defined entries |

To add a custom menu entry, edit `40_custom`:

```bash
#!/bin/sh
exec tail -n +3 $0

menuentry "EFI Shell" {
    insmod fat
    insmod chain
    search --no-floppy --fs-uuid --set=root <esp-uuid>
    chainloader /EFI/BOOT/Shell.efi
}

menuentry "Firmware Setup" {
    fwsetup
}
```

The `fwsetup` command tells the firmware to enter setup on the
next boot — useful when the key-press timing at POST is unreliable.

### OS prober

`os-prober` scans all disks for other installed operating systems
and generates GRUB menu entries for them. This is how a dual-boot
Windows entry appears in the GRUB menu automatically.

Some distributions (Fedora since 34) disable `os-prober` by
default for security reasons (it mounts foreign partitions during
configuration generation). To enable it:

```bash
# /etc/default/grub
GRUB_DISABLE_OS_PROBER=false

# Install os-prober if not present
sudo dnf install os-prober      # Fedora
sudo apt install os-prober      # Debian/Ubuntu

# Regenerate
sudo grub2-mkconfig -o /boot/grub2/grub.cfg   # Fedora
sudo update-grub                                # Debian/Ubuntu
```

## GRUB command line

When GRUB is running (at the menu screen), pressing `c` opens the
GRUB command line — a minimal shell that can inspect disks, load
kernels, and boot manually. This is the primary recovery tool when
the GRUB configuration is broken but GRUB itself loads.

Essential GRUB shell commands:

```bash
# List available disks and partitions
ls

# Show partition details
ls (hd0,gpt1)/

# Show the contents of a directory
ls (hd0,gpt2)/boot/

# Set the root partition
set root=(hd0,gpt2)

# Load a kernel manually
linux /boot/vmlinuz-6.8.0 root=/dev/nvme0n1p3 ro

# Load the initramfs
initrd /boot/initramfs-6.8.0.img

# Boot
boot
```

### GRUB rescue shell

If GRUB cannot find its configuration, its modules, or the
partition containing them, it drops to the rescue shell
(`grub rescue>`). The rescue shell has a minimal command set —
no `linux` or `initrd` commands. Recovery requires loading the
`normal` module:

```bash
# In grub rescue>
# 1. Find the partition with GRUB's files
ls
ls (hd0,gpt2)/boot/grub2/

# 2. Set the prefix and root
set prefix=(hd0,gpt2)/boot/grub2
set root=(hd0,gpt2)

# 3. Load the normal module
insmod normal

# 4. Enter normal mode
normal

# GRUB's full menu should now appear
# Once booted, reinstall GRUB properly (see Boot Management page)
```

## GRUB and Secure Boot

When Secure Boot is enabled, GRUB is loaded by shim, which verifies
GRUB's signature against the distribution's embedded key. GRUB in
turn verifies the kernel's signature via shim's verification
protocol.

This has practical implications:

- **Custom GRUB builds will not boot under Secure Boot** unless
  signed with a MOK-enrolled key or the distribution's key.
- **GRUB modules loaded from the configuration** (via `insmod`)
  must also be signed on Secure Boot systems. Most distributions
  bundle the necessary modules into the GRUB EFI binary to avoid
  this issue.
- **`grub-install` must use the correct target.** For UEFI Secure
  Boot: `--target=x86_64-efi`. Using the wrong target produces a
  binary that either does not boot or fails Secure Boot
  verification.

## GRUB and LUKS

When the root filesystem is on a LUKS-encrypted volume, GRUB must
either:

1. **Prompt for the passphrase in GRUB itself** (GRUB 2 supports
   LUKS1; GRUB 2.06–2.12 support LUKS2 with PBKDF2 only, not Argon2;
   GRUB 2.14+ adds native Argon2id/Argon2i support). This is required
   when `/boot` is inside the LUKS volume. If your GRUB predates 2.14
   and the volume uses Argon2, convert the LUKS2 header's KDF to PBKDF2
   for the boot device.

2. **Load an unencrypted `/boot`**, which contains the kernel and
   initramfs. The initramfs then handles LUKS unlocking during
   early boot. This is the more common configuration.

If using TPM-based LUKS unlocking (see [TPM](tpm.md)), the
unlocking happens in the initramfs, not in GRUB. GRUB loads the
kernel and initramfs from an unencrypted `/boot` or from the ESP,
and the initramfs uses `systemd-cryptenroll` and the TPM to unlock
the root volume.

```bash
# Check if /boot is a separate partition or inside the root volume
lsblk -f
# If /boot has its own entry, it is separate
# If it is a directory on the root partition, the root volume
# must be accessible to GRUB (either unencrypted or GRUB-decrypted)
```

## Reinstalling GRUB

When GRUB is broken — the binary is corrupted, the EFI entry is
missing, or a firmware update wiped the ESP — reinstallation from
a live environment restores it. The full procedure is on the
[Boot Management](boot-management.md) page. The GRUB-specific
commands:

```bash
# Inside a chroot from a live environment

# Fedora
sudo dnf reinstall grub2-efi-x64 shim-x64
sudo grub2-mkconfig -o /boot/grub2/grub.cfg

# Debian/Ubuntu
sudo apt install --reinstall grub-efi-amd64-signed shim-signed
sudo update-grub

# Both: verify the EFI entry exists
efibootmgr -v
```

## systemd-boot (alternative)

Some distributions (notably Arch Linux and its derivatives, and
optionally Ubuntu 23.10+) use `systemd-boot` instead of GRUB.
systemd-boot is simpler, faster, and manages boot entries through
plain text files in the ESP rather than a generated configuration
script. It does not support BIOS/legacy boot — UEFI only.

This framework does not take a strong position on GRUB vs
systemd-boot. Both work. GRUB is the default on the framework's
target distributions (Fedora, Debian, Ubuntu) and is covered in
detail here for that reason. Engineers who prefer systemd-boot can
configure it via `bootctl` and the
[systemd-boot documentation](https://www.freedesktop.org/software/systemd/man/systemd-boot.html).

## Questions to ask

1. Can GRUB be modified safely right now? Is there a USB live
   environment available for recovery if a configuration change
   makes the system unbootable?
2. What kernel parameters are currently in effect?
   `cat /proc/cmdline` shows the command line the running kernel
   was booted with.
3. Is `os-prober` enabled? If dual-booting, the other OS must
   appear in the GRUB menu. If not dual-booting, disabling
   `os-prober` is a minor security improvement.
4. Is `/boot` separate or inside the root filesystem? If inside a
   LUKS volume, does GRUB support the LUKS version and key
   derivation function in use?
5. After a kernel update: does GRUB's configuration include the new
   kernel? `grub2-mkconfig` / `update-grub` must run after kernel
   installation (most distributions do this automatically via
   package manager hooks).
