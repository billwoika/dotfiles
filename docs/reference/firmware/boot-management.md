# Boot Management

Boot management is the process of controlling which operating system
or bootloader the firmware loads when the machine starts. On UEFI
systems, this is managed through a combination of firmware boot
entries (stored in NVRAM), the EFI System Partition (ESP) on disk,
and the `efibootmgr` utility from Linux.

Understanding boot management matters for Linux workstation users
because boot failures — a blank screen after a firmware update, a
machine that boots the wrong OS in a dual-boot setup, or a system
that enters a boot loop — are almost always boot entry or ESP
problems, not disk or OS problems. The data is fine. The firmware
just does not know where to find the bootloader.

## UEFI boot entries

UEFI firmware maintains an ordered list of boot entries in NVRAM.
Each entry points to a specific `.efi` executable on a specific
partition (usually the ESP). When the machine powers on, the
firmware walks the list in order and loads the first entry that
points to a valid, present, and (if Secure Boot is enabled)
properly signed binary.

```bash
# List all boot entries
efibootmgr -v

# Typical output:
# BootCurrent: 0001
# BootOrder: 0001,0002,0003,2001
# Boot0001* fedora    HD(1,GPT,...)/File(\EFI\fedora\shimx64.efi)
# Boot0002* ubuntu    HD(1,GPT,...)/File(\EFI\ubuntu\shimx64.efi)
# Boot0003* Windows Boot Manager  HD(1,GPT,...)/File(\EFI\Microsoft\Boot\bootmgfw.efi)
# Boot2001* EFI USB Device  ...
```

**BootOrder** is the priority list. The firmware tries each entry
in sequence. The first valid entry boots.

**BootCurrent** indicates which entry was used for the current boot.

Each entry contains:

- A human-readable label ("fedora," "ubuntu," "Windows Boot Manager")
- A disk and partition identifier (GPT GUID)
- A path to the `.efi` binary on that partition

### Managing boot entries

```bash
# Change boot order (boot fedora first, then ubuntu, then Windows)
sudo efibootmgr -o 0001,0002,0003

# Set a one-time boot entry (next boot only, then reverts to BootOrder)
sudo efibootmgr -n 0002

# Create a new boot entry
sudo efibootmgr --create \
  --disk /dev/nvme0n1 \
  --part 1 \
  --loader '\EFI\fedora\shimx64.efi' \
  --label "Fedora" \
  --verbose

# Delete a boot entry
sudo efibootmgr -b 0004 -B

# Toggle an entry active/inactive
sudo efibootmgr -b 0002 -a  # activate
sudo efibootmgr -b 0002 -A  # deactivate
```

### Firmware boot menu

Most firmware provides a one-time boot menu accessible by pressing
a key at POST (typically F12, F9, or Esc — see the
[index page](index.md) for vendor-specific keys). The boot menu
shows available boot entries and allows selecting one without
changing the persistent boot order.

This is the preferred method for one-off actions: booting a USB
installer, selecting a different OS in a dual-boot setup, or
booting from a recovery disk. It does not modify NVRAM.

## The EFI System Partition (ESP)

The ESP is a FAT32 partition (typically 256MB-1GB) that contains
bootloader executables, kernel images (on some configurations),
and firmware-accessible files. It is created by the OS installer
and mounted at `/boot/efi` (traditional) or `/efi` (newer
systemd convention).

```bash
# Identify the ESP
sudo fdisk -l | grep "EFI System"
# Example: /dev/nvme0n1p1  2048  1050623  1048576  512M  EFI System

# View ESP contents
ls /boot/efi/EFI/
# Typical contents:
#   BOOT/       — fallback bootloader (BOOTX64.EFI)
#   fedora/     — Fedora's shim and GRUB
#   ubuntu/     — Ubuntu's shim and GRUB
#   Microsoft/  — Windows Boot Manager
```

### ESP layout

Each operating system creates its own directory on the ESP:

```
/boot/efi/
├── EFI/
│   ├── BOOT/
│   │   └── BOOTX64.EFI          # Fallback — firmware loads this
│   │                             # if no NVRAM entries are valid
│   ├── fedora/
│   │   ├── shimx64.efi           # Signed first-stage bootloader
│   │   ├── grubx64.efi           # GRUB, loaded by shim
│   │   ├── grub.cfg              # GRUB configuration (or pointer to it)
│   │   └── mmx64.efi             # MOK Manager
│   ├── ubuntu/
│   │   ├── shimx64.efi
│   │   ├── grubx64.efi
│   │   └── grub.cfg
│   └── Microsoft/
│       └── Boot/
│           ├── bootmgfw.efi      # Windows Boot Manager
│           └── BCD               # Boot Configuration Data
```

**BOOTX64.EFI** in the `EFI/BOOT/` directory is the fallback
bootloader. If the firmware has no valid NVRAM boot entries (or if
the NVRAM is cleared), the firmware looks for
`\EFI\BOOT\BOOTX64.EFI` on the ESP and loads it. Linux
installers typically copy their shim to this path as a recovery
mechanism.

### Shared vs separate ESPs

In a dual-boot or multi-boot setup, the question is whether
operating systems share a single ESP or each has its own.

**Shared ESP (recommended).** All operating systems install their
bootloaders in their respective directories on a single ESP. The
firmware's boot entries all point to the same partition. This is
simpler to manage and is the default behavior of most installers.

**Separate ESPs.** Each operating system has its own ESP on its own
disk. This is more resilient (a problem with one ESP does not
affect the other) but requires managing multiple boot entries
pointing to different partitions, and the firmware must be able to
see all disks at boot time.

## Common boot problems and recovery

### "No bootable device found"

The firmware cannot find a valid boot entry. Causes:

1. **NVRAM boot entries were cleared.** Firmware updates, CMOS
   battery removal, or firmware resets can clear NVRAM. Fix: enter
   firmware setup, navigate to the boot menu, and add a boot
   entry pointing to the ESP's shim or GRUB binary. Or: the
   fallback `BOOTX64.EFI` should catch this automatically if the
   ESP is intact.

2. **The ESP is missing or corrupted.** If the ESP was accidentally
   deleted, reformatted, or its filesystem is damaged, no
   bootloader is accessible. Fix: boot from USB live media,
   mount the root partition, `chroot` in, and reinstall the
   bootloader (see below).

3. **CSM is enabled and the disk is GPT.** Some firmware in CSM
   mode will not boot GPT disks. Fix: disable CSM
   (see [index page](index.md)).

4. **The firmware does not see the disk.** Storage mode mismatch
   (RST vs AHCI) or a hardware connection issue. See
   [Storage](storage.md).

### "Security violation" or "Access denied"

Secure Boot is rejecting the bootloader. Causes:

1. **The bootloader is unsigned.** A custom GRUB or kernel that
   was not signed with a trusted key. Fix: sign it with a MOK key
   (see [Secure Boot](secure-boot.md)) or temporarily disable
   Secure Boot for diagnosis.

2. **The bootloader was revoked.** A dbx update revoked the
   current version of shim. Fix: boot from USB live media and
   update the shim package.

3. **MOK enrollment is needed.** A DKMS module or custom kernel
   requires a MOK key that has not been enrolled. The MOK Manager
   screen appears automatically during boot if shim detects a
   pending enrollment.

### GRUB rescue shell

GRUB drops to a rescue shell (`grub rescue>`) when it cannot find
its configuration or the root filesystem. This is covered in detail
on the [GRUB page](grub.md).

### Recovering a broken boot with a live USB

The general recovery procedure for a Linux system that will not
boot:

```bash
# 1. Boot from a USB live environment (same distribution preferred)

# 2. Identify the partitions
lsblk
# Find the root partition (e.g., /dev/nvme0n1p3)
# Find the ESP (e.g., /dev/nvme0n1p1)

# 3. Mount the root filesystem
sudo mount /dev/nvme0n1p3 /mnt

# 4. Mount the ESP
sudo mount /dev/nvme0n1p1 /mnt/boot/efi

# 5. Mount required virtual filesystems
sudo mount --bind /dev /mnt/dev
sudo mount --bind /dev/pts /mnt/dev/pts
sudo mount --bind /proc /mnt/proc
sudo mount --bind /sys /mnt/sys
sudo mount --bind /sys/firmware/efi/efivars /mnt/sys/firmware/efi/efivars

# 6. chroot into the installed system
sudo chroot /mnt

# 7. Reinstall the bootloader (distribution-specific)
# Fedora:
grub2-mkconfig -o /boot/grub2/grub.cfg
grub2-install --target=x86_64-efi --efi-directory=/boot/efi

# Debian/Ubuntu:
update-grub
grub-install --target=x86_64-efi --efi-directory=/boot/efi

# 8. Verify boot entries
efibootmgr -v

# 9. Exit and reboot
exit
sudo umount -R /mnt
sudo reboot
```

### LUKS-encrypted root

If the root partition is LUKS-encrypted, the recovery procedure
adds a step before mounting:

```bash
# Unlock the LUKS volume
sudo cryptsetup luksOpen /dev/nvme0n1p3 root

# Mount the unlocked volume
sudo mount /dev/mapper/root /mnt

# If using LVM inside LUKS
sudo vgchange -ay
sudo mount /dev/mapper/<vg-name>-root /mnt

# Continue with steps 4-9 above
```

## Firmware boot settings

| Setting | Description | Recommendation |
|---------|-------------|----------------|
| Boot Mode | UEFI / Legacy / Both | **UEFI only** |
| CSM | Enable / Disable | **Disable** |
| Secure Boot | Enable / Disable | **Enable** (see [Secure Boot](secure-boot.md)) |
| Boot Order | Priority list | OS first, USB second, network last |
| Fast Boot | Skip some POST tests | Disable (reduces POST time by ~1s at the cost of suppressing diagnostic output and sometimes skipping USB initialization) |
| Quiet Boot | Show logo instead of POST messages | Preference; disable for diagnostics |
| Network Boot / PXE | Boot from network | Disable unless using network boot |
| USB Boot | Boot from USB devices | **Enable** (needed for installation and recovery) |

**Fast Boot** deserves specific attention. When enabled, the
firmware skips some hardware initialization — often including USB
controller initialization. This can prevent USB keyboards from
working during POST, making it impossible to enter firmware setup
or the boot menu. If the machine ignores key presses at boot, Fast
Boot is the likely cause. Disable it from within the OS:

```bash
# Reboot directly into firmware setup (bypasses key-press timing)
sudo systemctl reboot --firmware-setup
```

## Questions to ask

1. Can you list the current boot entries? `efibootmgr -v` should
   show entries for every installed OS plus the fallback.
2. Is CSM disabled? If enabled, it can cause confusing dual-mode
   boot behavior.
3. Is there a fallback bootloader on the ESP?
   `ls /boot/efi/EFI/BOOT/BOOTX64.EFI` should exist.
4. Is Fast Boot enabled? If the keyboard does not respond at POST,
   this is the most likely cause.
5. Is there a known-working USB live environment available for
   boot recovery? This is the most important safety net for any
   boot management problem.
