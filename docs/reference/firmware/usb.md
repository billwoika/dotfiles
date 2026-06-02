# USB and Thunderbolt

USB and Thunderbolt are the primary peripheral connectivity
standards on modern workstations. Both are managed by the PCH (see
[Hardware Topology](hardware-topology.md)) and configured through
firmware settings that affect device detection, power delivery,
security, and boot capability.

The confusion in this space comes from the naming. USB has been
rebranded so many times that the version numbers are effectively
meaningless to anyone who has not tracked the changes. Thunderbolt
has merged with USB-C at the connector level while remaining a
distinct protocol. This page cuts through the naming and explains
what matters for a Linux development workstation.

## USB versions and naming

The USB Implementers Forum has repeatedly renamed USB versions,
making the version landscape nearly impenetrable. The current
state:

| Marketing name | Technical name | Max speed | Connector |
|---------------|---------------|-----------|-----------|
| USB 2.0 | USB 2.0 | 480 Mbps | Type-A, Type-C, Micro-B |
| USB 3.0 | USB 3.2 Gen 1 | 5 Gbps | Type-A, Type-C |
| USB 3.1 | USB 3.2 Gen 2 | 10 Gbps | Type-A, Type-C |
| USB 3.2 | USB 3.2 Gen 2x2 | 20 Gbps | Type-C only |
| USB4 | USB4 Gen 2x2 / 3x2 | 20 / 40 Gbps | Type-C only |

The practical advice: ignore the marketing names. What matters is
the speed (5/10/20/40 Gbps) and the connector (Type-A or Type-C).
Firmware settings typically reference the technical or original
name (USB 3.0, USB 3.1) rather than the rebranded versions.

## Firmware USB settings

### USB legacy support

**Legacy USB Support** or **USB Keyboard/Mouse Support** enables
USB input devices during the pre-boot environment — firmware
setup, boot menu, bootloader (GRUB). Without this setting, USB
keyboards and mice do not work until the OS loads its own USB
drivers.

Modern firmware typically enables this by default, but the setting
exists and should be verified if a USB keyboard does not respond
at the firmware setup screen.

Legacy USB support works by having the firmware emulate PS/2
keyboard and mouse input for USB devices. This emulation is active
during POST, firmware setup, and the early stages of OS boot. Once
the OS loads its own USB stack, the firmware's emulation is
deactivated.

**Recommendation:** Enable. There is no performance or security
cost, and the alternative — a keyboard that does not work in
firmware setup — is a debugging nightmare.

### USB port power

Firmware controls whether USB ports provide power when the system
is in sleep or powered off states. Settings include:

**USB Wake Support / Wake on USB.** Whether a USB device
(typically a keyboard or mouse) can wake the system from sleep.
Enable for development workstations that should wake on keyboard
press; disable if the machine wakes unexpectedly from sleep (a
common Linux laptop issue where an external USB device sends
spurious wake signals).

**USB Charging in Sleep / Always On USB.** Whether specific USB
ports provide power when the system is in S3/S4/S5 (sleep,
hibernate, soft-off). Lenovo ThinkPads have a dedicated "Always On
USB" port (typically the yellow USB-A port) with a firmware setting
to control its behavior.

**USB Power Share / Charging.** Some machines expose per-port power
delivery settings. The typical options are "Auto" (port powers
down with the system), "Enabled" (port always provides power), and
"Disabled" (port never provides power when the system is off).

### XHCI Hand-off

**XHCI Hand-off** controls the transition of USB controller
ownership from firmware to the operating system. When the OS loads
its USB stack, it must take ownership of the xHCI (USB 3.x)
controller from the firmware. If the hand-off fails, USB devices
may stop working after the OS boots or behave erratically.

**Recommendation:** Enable. Modern Linux kernels handle the
hand-off correctly, but some firmware implementations require this
setting to be explicitly enabled for the hand-off to occur cleanly.
If USB devices work in firmware setup but fail after the OS boots,
XHCI Hand-off is the first setting to check.

### USB mass storage boot

Whether the firmware allows booting from USB storage devices (flash
drives, external SSDs). This is essential for OS installation and
recovery.

**Recommendation:** Enable. Disabling USB boot is a security
measure for kiosk or shared machines. A development workstation
needs USB boot for installation, recovery, and live environments.

## Thunderbolt

Thunderbolt is a high-bandwidth connectivity standard developed by
Intel and Apple. Thunderbolt 3 and later use the USB-C connector
and coexist with USB on the same port — a Thunderbolt port is also
a USB-C port, but a USB-C port is not necessarily a Thunderbolt
port.

Thunderbolt provides:

| Version | Max bandwidth | PCIe lanes | DisplayPort | USB |
|---------|-------------|-----------|-------------|-----|
| Thunderbolt 3 | 40 Gbps | PCIe 3.0 x4 | DP 1.2 | USB 3.1 |
| Thunderbolt 4 | 40 Gbps | PCIe 3.0 x4 (guaranteed) | DP 1.4 (HBR3) | USB4 |
| Thunderbolt 5 | 80/120 Gbps | PCIe 4.0 x4 | DP 2.1 | USB4 |

The critical feature for firmware configuration is that Thunderbolt
tunnels PCIe traffic. A Thunderbolt device has direct memory access
(DMA) to the host system's memory through the PCIe tunnel. This is
what makes Thunderbolt docks, eGPUs, and high-speed storage work —
and it is also the security concern that firmware's Thunderbolt
settings address.

### Thunderbolt security levels

Firmware exposes a Thunderbolt security level that controls how
Thunderbolt devices are authorized:

| Level | Name | Behavior |
|-------|------|----------|
| 0 | None / Legacy | All Thunderbolt devices are trusted immediately. No authorization required. Full DMA access. |
| 1 | User Authorization | The OS prompts the user to authorize each new Thunderbolt device. Once authorized, the device is trusted on future connections. |
| 2 | Secure Connect | Like User Authorization, but the device is cryptographically authenticated — the host and device exchange a key on first connection. |
| 3 | No PCIe Tunneling | Thunderbolt operates in USB/DisplayPort mode only. PCIe tunneling is disabled. This blocks DMA-based attacks but also disables eGPUs, Thunderbolt storage, and Thunderbolt networking. |

**Recommendation for a development workstation:** Level 1 (User
Authorization) or Level 2 (Secure Connect). Level 0 provides no
protection against DMA attacks — a malicious Thunderbolt device
plugged into the machine has unrestricted memory access. Level 3
is too restrictive for most development use cases (it disables
Thunderbolt docks' PCIe functionality).

### Thunderbolt on Linux

Linux has supported Thunderbolt authorization since kernel 4.13 (the
in-kernel security-level sysfs interface that `bolt`/`boltctl` rely on)
via the `bolt` daemon and `boltctl` utility:

```bash
# List connected Thunderbolt devices
boltctl list

# Authorize a device
boltctl authorize <device-uuid>

# Permanently enroll a device (trusted on future connections)
boltctl enroll <device-uuid>

# Check the security level
boltctl domains
```

GNOME's Settings panel provides a GUI for Thunderbolt device
authorization (under "Privacy" or "Thunderbolt"). KDE has similar
support in System Settings.

### Thunderbolt and IOMMU

IOMMU (see [Virtualization](virtualization.md)) provides an
additional security layer for Thunderbolt. When IOMMU is enabled,
DMA transactions from Thunderbolt devices are remapped through the
IOMMU, restricting them to allocated memory regions. This mitigates
DMA attacks even if the Thunderbolt security level is set to None.

For a development workstation with Thunderbolt ports, enabling both
VT-d/AMD-Vi (IOMMU) and Thunderbolt security level 1+ provides
defense-in-depth against DMA attacks from malicious peripherals.

## USB-C Power Delivery

USB-C Power Delivery (USB PD) is the standard for power
negotiation over USB-C. A USB-C port with PD support can both
charge the machine and power peripherals, negotiating voltage and
current between the charger, the machine, and connected devices.

Firmware settings for USB PD are primarily found on laptops:

**Charging source priority.** When both a USB-C PD charger and a
traditional barrel-jack charger are connected, which takes
priority. Lenovo ThinkPads expose this as "USB-C Always On /
Charging Priority."

**Minimum wattage.** Some laptop firmware will refuse to boot on
USB-C PD power if the charger provides less than a minimum wattage
(typically 45W or 65W). This prevents the machine from running on
a phone charger that cannot sustain the power draw, but it also
means some lower-wattage USB-C chargers will not work even for
light workloads.

**Pre-boot charging.** Whether the machine will charge from USB-C
when powered off. Usually enabled by default.

## Questions to ask

1. Is USB legacy support enabled? If the keyboard does not work in
   firmware setup, this is the most likely cause.
2. Is XHCI Hand-off enabled? If USB devices work in firmware but
   fail after the OS boots, this is the first setting to check.
3. What is the Thunderbolt security level? `boltctl domains` shows
   the current level. Level 0 means any Thunderbolt device has
   unrestricted DMA access to the machine's memory.
4. Is IOMMU enabled alongside Thunderbolt? If not, Thunderbolt
   devices have direct, unfiltered memory access regardless of the
   Thunderbolt security level.
5. Does the machine wake unexpectedly from sleep? If so, check USB
   Wake Support and identify which device is sending the wake
   signal: `cat /proc/acpi/wakeup`.
