# Firmware Updates

Firmware updates modify the code that runs before the operating
system. Unlike OS or application updates — which can be rolled back,
reinstalled, or recovered from — a failed firmware update can render
a machine unbootable in a way that no software recovery can fix.
This page covers the mechanisms for updating firmware on Linux
workstations, the risk calculus for deciding when to update, and
the practical steps for each vendor.

## Why update firmware

Firmware updates address three categories of issues:

**Security vulnerabilities.** Firmware-level vulnerabilities
(Spectre/Meltdown mitigations, SMM attacks, Secure Boot bypasses,
TPM vulnerabilities) are patched through firmware updates. These
are the most compelling reason to update — a firmware-level
vulnerability cannot be fully mitigated by OS patches alone.

**Hardware compatibility.** Firmware updates add support for new
hardware (newer CPU steppings, new NVMe controllers, new memory
modules), fix compatibility issues with existing hardware (sleep/
wake failures, USB device recognition, PCIe link training problems),
and add support for new specifications (TPM 2.0 on machines that
shipped with TPM 1.2, Resizable BAR on older GPUs).

**Bug fixes.** Incorrect ACPI tables, broken S3 support, fan
control errors, incorrect sensor readings, boot failures after
OS updates — firmware bugs that affect day-to-day operation.

## The risk calculus

Firmware updates carry more risk than software updates:

- **Non-recoverable failure.** If a firmware update fails mid-write
  (power loss, crash, incompatible firmware image), the firmware
  chip may contain corrupted code. On machines without dual-BIOS
  (a backup firmware chip), this is a hardware-level failure that
  requires manufacturer repair or chip replacement.
- **Irreversibility.** Most firmware updates cannot be downgraded.
  Once the firmware is updated, the previous version is gone. If
  the new firmware introduces a regression (a setting that was
  available is now missing, sleep behavior changes, a peripheral
  stops working), the only path is to wait for a further update
  that fixes the regression.
- **Interacting changes.** A firmware update that changes ACPI
  tables, Secure Boot dbx entries, or TPM PCR measurements may
  affect the OS boot chain. LUKS volumes sealed to TPM PCRs will
  require manual passphrase entry and re-enrollment after a
  firmware update that changes measured values (see [TPM](tpm.md)).

The decision framework:

| Situation | Recommendation |
|-----------|---------------|
| Security vulnerability with CVE | Update promptly |
| Hardware compatibility fix for issue you are experiencing | Update |
| Stability fix for issue you are experiencing | Update |
| "General improvements" with no specific changelog | Wait; update on next major version or when a specific fix is needed |
| Machine is working correctly, no known issues | No urgency; update on a schedule (quarterly or with OS upgrades) |
| Machine is in production or critical-path | Update in a maintenance window with physical access and recovery media available |

## fwupd and LVFS

**fwupd** is the Linux firmware update daemon. **LVFS** (Linux
Vendor Firmware Service) is the repository of firmware images that
fwupd downloads from. Together, they provide a standardized,
distribution-agnostic mechanism for firmware updates on Linux — the
equivalent of Windows Update's firmware delivery, but open.

### Vendor support

Not all vendors publish firmware to LVFS. Current status (2026):

| Vendor | LVFS support | Notes |
|--------|-------------|-------|
| Lenovo (ThinkPad) | Excellent | Most ThinkPad models have full LVFS coverage |
| Dell | Good | Most Latitude, XPS, and Precision models |
| HP | Partial | Some EliteBook and ProBook models |
| System76 | Excellent | Full coverage for System76 hardware |
| Framework | Excellent | Full coverage |
| ASUS (consumer) | Minimal | Few models published |
| MSI | Minimal | Few models published |
| Gigabyte | Minimal | Few models published |

For machines not on LVFS, firmware updates must be applied manually
via the vendor's tools (see below).

### Using fwupd

```bash
# Install fwupd (usually pre-installed on Fedora and Ubuntu)
sudo dnf install fwupd       # Fedora
sudo apt install fwupd       # Debian/Ubuntu

# Check for available updates
fwupdmgr get-updates

# View installed firmware versions
fwupdmgr get-devices

# Download and apply updates
fwupdmgr update

# The update is staged — it will be applied on the next reboot
# Some firmware updates require the machine to reboot into a
# UEFI capsule update mode, which shows a vendor logo and a
# progress bar during the update process
```

### UEFI capsule updates

The standard mechanism for UEFI firmware updates on Linux. fwupd
places the firmware update file on the ESP, sets an EFI variable
that tells the firmware to apply the update, and reboots. The
firmware detects the pending update during POST, applies it, and
boots normally.

This process is safe as long as:

- Power is not interrupted during the update (use AC power, not
  battery alone, for laptop firmware updates)
- The firmware image is correct for the hardware (fwupd and LVFS
  handle this matching automatically)
- The ESP has sufficient free space for the update capsule

### After a fwupd update

```bash
# Verify the update was applied
fwupdmgr get-devices
# The firmware version should match the update

# Check for TPM re-enrollment needs
# If using TPM-sealed LUKS (see TPM page), the firmware update
# may have changed PCR values
mokutil --sb-state           # Verify Secure Boot is still enabled
tpm2_pcrread sha256:7        # Check PCR 7 value
```

## Vendor-specific update methods

### Lenovo ThinkPad

Lenovo provides LVFS coverage for most ThinkPads. For models not
on LVFS, or for manual updates:

1. Download the BIOS update from
   [Lenovo Support](https://pcsupport.lenovo.com/) — select the
   machine's model, navigate to "Drivers & Software" → "BIOS/UEFI."
2. Lenovo provides two formats:
   - **Windows executable (.exe):** Requires Windows or a Windows
     PE environment.
   - **Bootable CD image (.iso):** Can be written to a USB drive
     and booted directly. This works without Windows.

```bash
# Write the bootable ISO to a USB drive
sudo dd if=<firmware-update>.iso of=/dev/sdX bs=4M status=progress
# Boot from the USB drive and follow the on-screen instructions
```

### Dell

Dell provides LVFS coverage for most business-class machines. For
manual updates:

1. Download the BIOS update from
   [Dell Support](https://www.dell.com/support/home/) — enter the
   Service Tag, navigate to "Drivers & Downloads" → "BIOS."
2. The normal Linux path is fwupd/LVFS: most Dell systems ship firmware
   as `.cab` files on the LVFS, applied with `fwupdmgr`. Dell's
   downloadable `.exe` is a Windows executable — it is NOT directly
   runnable on Linux. (If a needed update is only offered as an .exe,
   extract the firmware payload, or update via the BIOS's own
   flash-from-USB feature.) When a `.cab` is available locally:

```bash
# Apply a locally downloaded Dell firmware update
fwupdmgr install <firmware-file>.cab
```

### HP

HP's LVFS coverage is partial. For manual updates, HP provides
Windows-only tools for most models. The workaround for Linux-only
machines:

1. Create a FreeDOS USB boot drive.
2. Download the HP BIOS update (the DOS/bootable version, if
   available).
3. Boot from the FreeDOS USB and run the update utility.

### DIY motherboards (ASUS, MSI, Gigabyte, ASRock)

Consumer motherboard vendors rarely publish to LVFS. Updates are
applied through the firmware's built-in update utility:

1. Download the firmware update file from the vendor's website.
2. Place it on a FAT32-formatted USB drive.
3. Enter firmware setup, navigate to the update utility (names vary:
   "EZ Flash" on ASUS, "M-Flash" on MSI, "Q-Flash" on Gigabyte,
   "Instant Flash" on ASRock).
4. Select the firmware file from the USB drive and apply.

These utilities are firmware-native — they do not depend on any OS.
They are the most reliable update method for DIY hardware because
the firmware itself manages the write process.

## Before any firmware update

A checklist regardless of update method:

- [ ] **AC power connected** (laptops). A battery-only firmware
  update risks corruption if the battery dies mid-write.
- [ ] **LUKS passphrase known** (if using TPM-sealed encryption).
  The firmware update will change PCR values, requiring passphrase
  entry on next boot.
- [ ] **USB live environment available.** If the update breaks the
  boot chain, a live USB is the recovery tool.
- [ ] **Note current firmware version.** `sudo dmidecode -s bios-version`
  — record it before and after for verification.
- [ ] **Read the changelog.** Understand what the update changes.
  If the changelog is vague ("general improvements"), weigh whether
  the update is worth the risk.
- [ ] **Close all applications and save work.** The update will
  reboot the machine.

## Questions to ask

1. Is fwupd installed and functional? `fwupdmgr get-devices`
   should list recognized hardware.
2. Is the machine's firmware available on LVFS? `fwupdmgr get-updates`
   will show available updates if the vendor publishes to LVFS.
3. What is the current firmware version and date?
   `sudo dmidecode -t bios` provides both.
4. Is there a specific issue driving the update, or is it
   precautionary? Targeted updates (fixing a known issue) have
   clearer risk/benefit than general updates.
5. Is the machine using TPM-sealed disk encryption? If so, the
   LUKS passphrase must be available before the update, and TPM
   re-enrollment is required after.
