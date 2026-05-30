# PCI and PCIe

PCI Express (PCIe) is the primary high-speed interconnect on modern
x86 systems. Every discrete GPU, NVMe drive, network card, sound
card, Thunderbolt controller, and many on-board peripherals
communicate with the CPU over PCIe. The firmware settings for PCIe
control lane allocation, generation negotiation, power management,
and memory mapping — all of which affect device compatibility and
performance.

## PCIe fundamentals

### Lanes and links

A PCIe connection consists of one or more **lanes.** Each lane is
an independent, full-duplex serial link. Lanes are grouped into
**links** of 1, 2, 4, 8, or 16 lanes (written as x1, x2, x4, x8,
x16). More lanes means more bandwidth.

A device physically wired with x16 lanes can negotiate down to a
narrower link if the device does not need the full bandwidth. A GPU
in an x16 slot may operate at x8 if the firmware or platform
restricts the available lanes. The negotiated link width is visible
in `lspci`:

```bash
# Show link width and speed for all PCIe devices
sudo lspci -vv | grep -E "LnkCap|LnkSta"

# LnkCap = what the device and slot are capable of
# LnkSta = what was actually negotiated
# Example:
#   LnkCap: Port #0, Speed 16GT/s, Width x16
#   LnkSta: Speed 16GT/s, Width x16
```

### Generations

Each PCIe generation doubles the per-lane bandwidth:

| Generation | Per-lane bandwidth | x4 total | x16 total | Encoding |
|-----------|-------------------|----------|-----------|----------|
| PCIe 1.0 | 250 MB/s | 1 GB/s | 4 GB/s | 8b/10b |
| PCIe 2.0 | 500 MB/s | 2 GB/s | 8 GB/s | 8b/10b |
| PCIe 3.0 | ~1 GB/s | ~3.9 GB/s | ~15.8 GB/s | 128b/130b |
| PCIe 4.0 | ~2 GB/s | ~7.9 GB/s | ~31.5 GB/s | 128b/130b |
| PCIe 5.0 | ~4 GB/s | ~15.8 GB/s | ~63 GB/s | 128b/130b |

PCIe is backward-compatible: a PCIe 3.0 device works in a PCIe 5.0
slot (at PCIe 3.0 speeds), and a PCIe 5.0 device works in a PCIe
3.0 slot (at PCIe 3.0 speeds). The negotiated generation is always
the minimum of the device and slot capabilities.

## Firmware PCIe settings

### PCIe generation / link speed

Some firmware allows restricting the PCIe generation for specific
slots or globally. Settings like "PCIe Speed" or "Link Speed" with
options "Auto," "Gen 3," "Gen 4," "Gen 5."

**Recommendation:** Leave at "Auto." The device and slot negotiate
the highest mutually supported generation. The only reason to force
a lower generation is to work around device compatibility issues —
rare with modern hardware. If a PCIe device is unstable (crashes,
disappears from `lspci` under load), downgrading the link speed
one generation is a valid diagnostic step.

### Lane allocation and bifurcation

**Bifurcation** is the firmware's ability to split a single
physical PCIe slot into multiple logical links. A physical x16 slot
can be bifurcated into:

- x16 (default — one link, 16 lanes)
- x8/x8 (two links, 8 lanes each)
- x4/x4/x4/x4 (four links, 4 lanes each)

Bifurcation is used when multiple devices share a single physical
slot — most commonly, M.2 expansion cards that put 2-4 NVMe drives
in one x16 slot, with each drive getting an x4 link.

**Firmware setting name:** "PCIe Bifurcation," "Slot
Configuration," or listed per-slot as "x16 / x8x8 / x4x4x4x4."
Not all motherboards support bifurcation, and those that do may
support it only on specific slots.

**Recommendation:** Leave at x16 unless using an M.2 expansion
card or a device that explicitly requires bifurcation. Incorrect
bifurcation settings will cause the device in the slot to not be
detected.

### Above 4G Decoding

PCIe devices map their memory (BARs — Base Address Registers)
into the system's address space. Devices with large memory regions
— primarily GPUs with 8GB+ VRAM — need addresses above the 4GB
boundary. If "Above 4G Decoding" is disabled, the firmware
restricts BAR mapping to the 32-bit address space (below 4GB),
which may not have enough room for the device's full memory.

**Firmware setting name:** "Above 4G Decoding," "Above 4G Memory,"
or "Large BAR Support."

**Recommendation:** **Enable** on any system with a discrete GPU
or other high-memory PCIe device. Disabling it can cause GPUs to
fail initialization, report reduced VRAM, or produce errors in
`dmesg` about failed BAR allocation.

### Resizable BAR (ReBAR) / Smart Access Memory (SAM)

Resizable BAR is a PCIe capability that allows the CPU to access
the full VRAM of a GPU through a single, large BAR mapping instead
of a small window. Without ReBAR, the CPU accesses GPU VRAM through
a 256MB window, requiring multiple mapping operations for large
transfers. With ReBAR, the entire VRAM (8GB, 16GB, 24GB) is mapped
at once.

**AMD markets this as Smart Access Memory (SAM).** It is the same
PCIe standard feature with a marketing name.

**Firmware setting name:** "Resizable BAR," "Re-Size BAR Support,"
or "Smart Access Memory."

**Prerequisites:**

- Above 4G Decoding must be enabled (ReBAR requires 64-bit BAR
  addresses)
- UEFI boot (not CSM/legacy)
- GPU firmware support (most GPUs from 2020+ support ReBAR)
- GPU driver support (NVIDIA 470+, AMD Mesa/AMDGPU, Intel i915)

**Recommendation:** Enable if the GPU supports it. The performance
benefit varies by workload (primarily benefits GPU-compute and
gaming; minimal impact on typical development workstation use),
but there is no downside to enabling it on supported hardware.

```bash
# Check if ReBAR is active
sudo dmesg | grep -i "bar"
sudo lspci -vv -s <gpu-pci-address> | grep -i "resize"

# Check GPU BAR size
sudo lspci -vv -s <gpu-pci-address> | grep "Memory at"
```

### ASPM (Active State Power Management)

ASPM is a PCIe power management feature that puts idle PCIe links
into low-power states. When a device is not actively transferring
data, ASPM transitions the link to a reduced-power state (L0s or
L1), saving power at the cost of a small latency penalty when the
link resumes.

| State | Description | Exit latency | Power savings |
|-------|-------------|-------------|---------------|
| L0 | Active | 0 | None |
| L0s | Standby | < 1μs | Low |
| L1 | Low power | 2-10μs | Medium |
| L1.1 | L1 sub-state | 32μs | High |
| L1.2 | L1 sub-state | 32-64μs | Higher |

**Firmware setting name:** "ASPM," "PCIe ASPM," "Active State
Power Management," or "L0s/L1 Support."

Options are typically:

- **Disabled:** No PCIe power management. Links stay active at all
  times. Maximum responsiveness, highest power consumption.
- **L0s Only:** Minimal power savings, minimal latency impact.
- **L1 Only:** Moderate power savings, moderate latency.
- **L0s and L1:** Both sub-states enabled. Maximum power savings.
- **Auto:** Let the OS decide (Linux uses the `pcie_aspm` kernel
  parameter and per-device policy).

**Recommendation for desktops:** "Disabled" or "Auto." Desktop
workstations are plugged in; power savings from ASPM are negligible,
and the latency penalty can cause subtle performance issues with
sensitive devices (audio interfaces, some NVMe controllers).

**Recommendation for laptops:** "Auto" or "L0s and L1." Battery
life benefits from ASPM. If a specific device misbehaves (audio
crackling, NVMe latency spikes), disable ASPM for that device
via the kernel parameter rather than globally:

```bash
# Disable ASPM globally (kernel parameter)
pcie_aspm=off

# Set ASPM policy to performance
pcie_aspm.policy=performance

# Set ASPM policy to powersave
pcie_aspm.policy=powersupersave
```

### PCIe AER (Advanced Error Reporting)

AER is a PCIe error reporting mechanism that logs correctable and
uncorrectable errors from PCIe devices. AER messages appear in
`dmesg` and can be useful for diagnosing hardware issues:

```bash
# Check for PCIe AER errors
dmesg | grep -i aer

# Common AER messages:
# "Corrected error" — transient error, hardware recovered, no action needed
# "Uncorrectable error" — device or link failure, investigate
```

Firmware may have an AER setting (enable/disable). Keep it enabled
— the error reports are diagnostic information, not problems
themselves. If AER messages are flooding the log from a specific
device (common with some WiFi cards and budget NVMe controllers),
the kernel parameter `pci=noaer` disables reporting globally, or
specific device quirks can suppress individual devices.

## Viewing PCIe topology

```bash
# Full PCIe device tree
sudo lspci -tv

# Detailed information for a specific device
sudo lspci -vvv -s <bus:device.function>

# Link speed and width for all devices
sudo lspci -vv | grep -E "LnkCap|LnkSta|LnkCtl"

# IOMMU groups (relevant for device passthrough)
for d in /sys/kernel/iommu_groups/*/devices/*; do
  n=$(basename $(dirname $(dirname $d)))
  echo "IOMMU Group $n: $(lspci -nns $(basename $d))"
done | sort -t: -k1 -n
```

## Questions to ask

1. Is Above 4G Decoding enabled? If a discrete GPU is installed,
   this should be on.
2. Is the GPU's PCIe link negotiating at the expected width and
   speed? Check `lspci -vv` — if LnkSta shows x8 when LnkCap shows
   x16, investigate whether bifurcation is misconfigured or the
   slot is physically x8.
3. Is ASPM causing device issues? Audio crackling, NVMe latency
   spikes, and WiFi instability can all be ASPM-related.
   Test with `pcie_aspm=off` as a kernel parameter.
4. Are there PCIe AER errors in `dmesg`? Uncorrectable errors
   indicate a hardware or slot problem. Correctable errors in small
   numbers are normal.
5. If using an M.2 expansion card: is PCIe bifurcation configured
   correctly for the number of drives?
