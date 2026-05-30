# TPM

The Trusted Platform Module (TPM) is a dedicated security chip (or
firmware-based equivalent) on the motherboard that provides
hardware-backed cryptographic operations: key generation, key
storage, random number generation, platform integrity measurement,
and sealed storage. The TPM operates independently of the CPU and
OS — it has its own processor, its own memory, and its own firmware.

For a Linux development workstation, TPM is relevant for two
primary use cases: disk encryption without a passphrase at every
boot, and platform integrity verification (measured boot). Both are
practical on modern distributions with straightforward
configuration.

## TPM versions

Two versions of the TPM specification are in circulation:

| | TPM 1.2 | TPM 2.0 |
|---|---------|---------|
| **Specification** | Fixed algorithm set | Algorithm-agile (pluggable) |
| **Hash** | SHA-1 (mandatory) | SHA-256 (mandatory), SHA-1 (optional) |
| **Asymmetric** | RSA only | RSA + ECC |
| **Key hierarchy** | Single Storage Root Key | Multiple hierarchies (platform, storage, endorsement) |
| **PCR banks** | SHA-1 only | Multiple hash algorithms simultaneously |
| **Linux support** | Mature but limited | Full support in modern kernels |
| **Windows 11** | Not supported | Required |

**TPM 2.0 is the only version worth configuring.** TPM 1.2's
reliance on SHA-1 makes it cryptographically weak for modern use.
If the machine has a TPM 1.2 chip, check whether the firmware
offers an upgrade path (some manufacturers provide firmware updates
that replace TPM 1.2 firmware with TPM 2.0).

### Discrete vs firmware TPM

**Discrete TPM (dTPM).** A dedicated chip soldered to the
motherboard. Provides the strongest security guarantees because the
cryptographic operations and key storage are physically isolated
from the CPU. Common on business-class laptops (ThinkPad, EliteBook,
Latitude) and server platforms.

**Firmware TPM (fTPM).** A software implementation that runs inside
the CPU's trusted execution environment — Intel Platform Trust
Technology (PTT) on Intel CPUs, AMD fTPM on AMD CPUs. Provides
the same TPM 2.0 API as a discrete chip but the cryptographic
operations execute on the main CPU in a protected enclave rather
than on a separate chip.

For a development workstation, either form is adequate. Firmware
TPM is standard on consumer hardware and provides sufficient
security for disk encryption and measured boot. Discrete TPM is
preferred for machines with higher security requirements.

**Firmware setting name:** "TPM," "Security Chip," "Intel PTT,"
"AMD fTPM," "Trusted Computing," or "TCG" (Trusted Computing
Group). Location varies: typically under "Security" or "Advanced."

| Setting | Description | Recommendation |
|---------|-------------|----------------|
| TPM State | Enable / Disable | **Enable** |
| TPM Version | 1.2 / 2.0 (if selectable) | **2.0** |
| TPM Device | Discrete / Firmware (PTT/fTPM) | Use what is available |
| Clear TPM | Erase all keys and reset | Only if re-provisioning |

## Verifying TPM from Linux

```bash
# Check if TPM is detected
ls /dev/tpm*
# /dev/tpm0 = TPM character device (older interface)
# /dev/tpmrm0 = TPM resource manager device (preferred)

# TPM version and status
cat /sys/class/tpm/tpm0/tpm_version_major
# "2" for TPM 2.0

# Detailed TPM information (requires tpm2-tools)
tpm2_getcap properties-fixed
tpm2_getcap properties-variable

# Check PCR values (Platform Configuration Registers)
tpm2_pcrread

# For quick status
sudo dmesg | grep -i tpm
```

If `/dev/tpm0` or `/dev/tpmrm0` does not exist, either the TPM is
disabled in firmware or the kernel module is not loaded. Check
firmware first; if the TPM is enabled, verify that the kernel
has TPM support:

```bash
# Check for TPM kernel modules
lsmod | grep tpm
# tpm_tis, tpm_crb, tpm_tis_core should appear

# If not loaded
sudo modprobe tpm_crb    # Command Response Buffer (TPM 2.0)
sudo modprobe tpm_tis    # TPM Interface Specification
```

## Disk encryption with TPM

The primary developer-workstation use case for TPM is LUKS disk
encryption with TPM-backed automatic unlocking. Without TPM, a
LUKS-encrypted disk requires a passphrase at every boot — the
machine sits at a password prompt until someone types it, which
prevents unattended reboots, remote restarts, and headless
operation.

With TPM, the LUKS encryption key can be sealed to the TPM and
automatically released at boot if the platform state matches the
expected measurements. The disk is encrypted at rest (protected
against theft), but the boot process is unattended (no passphrase
required).

### How it works

1. **The LUKS volume is encrypted with a key slot.** LUKS supports
   multiple key slots — each can hold a different passphrase or key
   that unlocks the same volume.
2. **One key slot is bound to the TPM.** The key is sealed to
   specific Platform Configuration Register (PCR) values — hashes
   that represent the firmware state, bootloader, and kernel at the
   time of sealing.
3. **At boot, the initramfs asks the TPM to unseal the key.** If
   the current PCR values match the sealed values (meaning the boot
   chain has not been tampered with), the TPM releases the key and
   the volume unlocks automatically.
4. **If the PCR values do not match, the TPM refuses to unseal.**
   The system falls back to the passphrase prompt. This happens
   after a firmware update, a kernel update, or any change to the
   boot chain — which is correct behavior, not a bug.

### Setting up LUKS with TPM2

Modern distributions provide `systemd-cryptenroll` for binding
LUKS volumes to TPM 2.0:

```bash
# Verify the LUKS volume (typically the root partition)
sudo cryptsetup luksDump /dev/nvme0n1p3

# Enroll the TPM2 key in a new key slot
# PCR 7 = Secure Boot policy (recommended minimum)
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/nvme0n1p3

# The command will prompt for an existing LUKS passphrase
# to authorize adding the new key slot

# Verify the enrollment
sudo cryptsetup luksDump /dev/nvme0n1p3
# A new key slot should appear with type "systemd-tpm2"
```

**Which PCRs to bind:**

| PCR | Measures | Bind? |
|-----|----------|-------|
| 0 | UEFI firmware code | Breaks on firmware update — avoid |
| 1 | UEFI firmware configuration | Breaks on any firmware setting change — avoid |
| 4 | Bootloader (GRUB, shim) | Breaks on bootloader update — optional |
| 5 | GPT partition table | Breaks on repartitioning — optional |
| 7 | Secure Boot policy | **Recommended** — changes only if Secure Boot keys change |
| 8 | Kernel command line (systemd-boot) | Useful for systemd-boot users |
| 9 | Kernel image (systemd-boot) | Breaks on kernel update — avoid unless automated |
| 11 | Unified Kernel Image hash | For UKI-based boot chains |
| 14 | MOK certificates | Changes when MOK keys are enrolled/removed |

**PCR 7 alone is the pragmatic choice** for most workstations. It
ensures the disk will not unlock if Secure Boot is disabled or if
the Secure Boot key database is modified — protecting against an
attacker who boots from external media. It does not break on
routine kernel or firmware updates.

### After kernel or firmware updates

When a bound PCR value changes (firmware update, Secure Boot key
change, bootloader update if bound to PCR 4), the TPM will not
release the key. The system falls back to the passphrase prompt.
After booting with the passphrase, re-enroll the TPM key to seal
against the new PCR values:

```bash
# Remove the old TPM2 key slot
sudo systemd-cryptenroll --wipe-slot=tpm2 /dev/nvme0n1p3

# Re-enroll with current PCR values
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/nvme0n1p3
```

### Keep a passphrase key slot

Never remove the passphrase key slot from a LUKS volume that uses
TPM enrollment. The passphrase is the recovery mechanism. If the
TPM fails, is cleared, or the machine is moved to a new
motherboard (with a different TPM), the passphrase is the only way
to unlock the volume.

```bash
# Verify that a passphrase key slot still exists
sudo cryptsetup luksDump /dev/nvme0n1p3
# At least one key slot should be type "luks2" (passphrase)
# and one should be type "systemd-tpm2"
```

## Measured boot

Measured boot is a TPM feature that records the state of each
stage of the boot process into the TPM's Platform Configuration
Registers. Each PCR is a hash chain: the new measurement is hashed
together with the previous PCR value, producing an aggregate that
represents the entire sequence of measurements up to that point.

The measurements are not enforced — measured boot does not prevent
a tampered bootloader from running (that is Secure Boot's job).
What measured boot provides is an *audit trail*: after boot, the
PCR values can be checked against known-good values to determine
whether the boot chain was modified.

For a development workstation, measured boot is primarily valuable
as the foundation for TPM-sealed disk encryption (described above).
The PCR values are what the TPM checks when deciding whether to
release the sealed key.

### Viewing measurements

```bash
# Read current PCR values
tpm2_pcrread sha256

# Read the event log (what was measured into each PCR)
# Location varies by distribution
cat /sys/kernel/security/tpm0/binary_bios_measurements | \
  tpm2_eventlog /dev/stdin
```

## TPM and firmware updates

Firmware updates frequently change PCR values — particularly PCR 0
(firmware code) and PCR 1 (firmware configuration). This is why
binding disk encryption to PCR 0 is not recommended: every firmware
update would require a passphrase entry and TPM re-enrollment.

The safe sequence for firmware updates on a TPM-sealed system:

1. **Before the firmware update:** ensure the LUKS passphrase is
   known and a passphrase key slot exists.
2. **Apply the firmware update.** The system will reboot.
3. **At boot:** the TPM will refuse to unseal (PCR values changed).
   Enter the passphrase.
4. **After booting:** re-enroll the TPM key slot with the new PCR
   values.

This sequence is manual but infrequent — firmware updates on a
development workstation happen a few times per year at most.

## Clearing the TPM

Clearing the TPM erases all keys, resets all PCRs, and returns the
TPM to a factory state. This is destructive:

- Any LUKS key slot bound to the TPM becomes invalid. The
  passphrase key slot is the only recovery path.
- Any application that stored keys in the TPM (SSH keys, FIDO2
  resident credentials, PKCS#11 objects) loses those keys
  permanently.

Clear the TPM only when:

- Decommissioning the machine or transferring ownership.
- The TPM is in a broken state and re-provisioning is required.
- Switching between discrete and firmware TPM (some platforms
  require a TPM clear during the transition).

The TPM can be cleared from firmware setup (under "Security" →
"Clear TPM" or similar) or from Linux:

```bash
# Clear TPM from Linux (requires physical presence confirmation
# on next boot — a firmware prompt that asks to confirm the clear)
tpm2_clear
```

## Questions to ask

1. Does the machine have a TPM, and is it enabled? `ls /dev/tpmrm0`
   answers both.
2. Is the TPM version 2.0? `cat /sys/class/tpm/tpm0/tpm_version_major`
   — if it shows "1," check for a firmware upgrade path.
3. Is disk encryption in use? If so, is the TPM enrolled as a key
   slot for automatic unlock?
4. Is there still a passphrase key slot on the LUKS volume? Without
   one, a TPM failure means permanent data loss.
5. What PCRs are the TPM key bound to? `systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=help`
   shows the current binding. If PCR 0 is included, every firmware
   update will require manual intervention.
