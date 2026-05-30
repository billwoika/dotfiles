# ACPI

The Advanced Configuration and Power Interface (ACPI) is the
specification that defines how the operating system and firmware
communicate about hardware configuration, power management, and
device enumeration. If firmware is the first code that runs on the
machine, ACPI is the contract between that firmware and every
operating system that boots after it.

ACPI is not a single setting in firmware. It is a subsystem —
a set of tables, methods, and state machines that the firmware
publishes and the kernel consumes. Understanding ACPI matters for
Linux workstation users because it is the source of the most
confusing class of hardware problems: machines that work perfectly
under Windows and exhibit subtle failures under Linux. Sleep that
does not work. Fans that run at full speed. Batteries that report
incorrect capacity. USB ports that do not wake the machine. Thermal
throttling that triggers too aggressively or not at all.

These failures are almost always ACPI failures — not kernel bugs,
not driver bugs, but firmware that publishes ACPI tables written
for Windows and tested only against Windows.

## What ACPI provides

### Device enumeration

When the kernel boots, it does not independently discover every
device on the system. For devices that are not on self-enumerating
buses (PCIe and USB enumerate their own devices), the kernel relies
on ACPI tables to describe what exists, where it is, and how to
talk to it. The embedded controller for battery management, the
platform sensors for thermal data, the GPIO pins for the laptop lid
switch — these are described in ACPI, and if the description is
wrong or missing, the kernel does not know the device exists.

### Power state management

ACPI defines a hierarchy of power states that the OS uses to manage
power consumption:

**Global states (G-states):**

| State | Name | Description |
|-------|------|-------------|
| G0 | Working | System is on, OS is running |
| G1 | Sleeping | System is suspended; sub-states S1–S4 |
| G2 | Soft Off | System is off but power supply is on (can wake via WOL, power button) |
| G3 | Mechanical Off | Power supply is off; no wake sources |

**Sleep states (S-states, sub-states of G1):**

| State | Name | Description | Power | Wake time |
|-------|------|-------------|-------|-----------|
| S0 | Working | Not sleeping | Full | N/A |
| S0ix | Modern Standby | CPU in low-power idle, peripherals selectively powered | Very low | Instant |
| S1 | Power on Suspend | CPU stops executing; cache and context retained | Medium-high | Fast |
| S2 | (Rarely used) | CPU powered off; cache lost | Medium | Fast |
| S3 | Suspend to RAM | All state in RAM; everything else powered off | Low | ~2 seconds |
| S4 | Hibernate | State written to disk; system powered off | Zero (except RTC) | Slow (disk read) |

The S0ix vs S3 distinction is the single most impactful ACPI
decision for Linux laptop users and is covered in detail in the
[Power and Thermal](power-thermal.md) page. The short version:
modern Intel and AMD laptops increasingly support only S0ix (Modern
Standby) and not S3 (traditional suspend-to-RAM). S0ix works well
on Windows because Intel and AMD work directly with Microsoft to
validate it. On Linux, S0ix support is improving but still produces
higher idle drain than S3 on many platforms.

**Device power states (D-states):**

| State | Description |
|-------|-------------|
| D0 | Fully on |
| D1 | Light sleep (device-specific) |
| D2 | Deeper sleep (device-specific) |
| D3 | Off (device may lose context) |

Individual devices transition through D-states independently. A USB
controller can be in D3 (off) while the GPU is in D0 (fully on).
The OS manages these transitions based on device activity and power
policy. Firmware's role is to declare which D-states each device
supports and the methods for transitioning between them.

**Processor power states (C-states):**

| State | Description | Typical latency |
|-------|-------------|-----------------|
| C0 | Active — executing instructions | 0 |
| C1 | Halt — clock stopped, instant resume | ~1μs |
| C2 | Stop-Clock — lower power, slower resume | ~100μs |
| C3 | Sleep — caches may be flushed | ~1ms |
| C6+ | Deep sleep — voltage reduced, state saved | ~1-10ms |

Deeper C-states save more power but take longer to resume. The OS
continuously transitions cores between C-states based on workload.
Firmware settings like "C-State Control" or "Package C-State Limit"
determine the deepest C-state the firmware will expose to the OS.
Disabling deep C-states can reduce latency jitter at the cost of
higher idle power consumption — relevant for real-time workloads
but not for typical development.

### Thermal management

ACPI defines thermal zones — regions of the system (CPU, GPU,
battery, ambient) with associated temperature sensors, trip points,
and cooling policies. The kernel reads these definitions and manages
fan speed, throttling, and shutdown based on the firmware-declared
thresholds.

Firmware typically defines two cooling modes:

- **Active cooling:** The OS increases fan speed as temperature
  rises. Trip points define the temperature thresholds at which each
  fan speed level activates.
- **Passive cooling:** The OS reduces CPU frequency (throttling)
  to limit heat generation. This is the fallback when active cooling
  is insufficient or unavailable (fanless designs).

When a Linux machine's fans behave erratically — running at full
speed at idle, or not spinning up under load — the problem is
usually one of:

1. **The ACPI thermal zone tables are wrong.** The firmware declares
   trip points or fan speed curves that were tuned for the Windows
   thermal driver, not the Linux `thermal` subsystem.
2. **The kernel is not using ACPI thermal management.** Some
   platforms use vendor-specific thermal drivers (e.g., Intel DPTF)
   that have better Linux support than the generic ACPI thermal
   path.
3. **The embedded controller manages fans independently of ACPI.**
   Some laptops (particularly ThinkPads) use the embedded controller
   for fan control, bypassing ACPI entirely. Tools like
   `thinkfan` interface with the EC directly.

## ACPI tables

ACPI's contract is encoded in a set of tables that the firmware
writes to memory and the kernel reads at boot. The most important
for Linux workstation users:

| Table | Name | Contains |
|-------|------|----------|
| **DSDT** | Differentiated System Description Table | The main table — device definitions, methods, thermal zones, power management logic. Written in AML (ACPI Machine Language), compiled from ASL (ACPI Source Language). |
| **SSDT** | Secondary System Description Table | Supplemental device definitions. A system can have multiple SSDTs that extend the DSDT. |
| **FADT** | Fixed ACPI Description Table | Hardware register addresses, power management profile, flags (e.g., whether S3 is supported). |
| **MADT** | Multiple APIC Description Table | Interrupt controller descriptions — how many CPUs, which interrupt model (APIC, x2APIC). |
| **MCFG** | Memory-mapped Configuration | PCIe configuration space base address. Required for PCIe MMIO access. |
| **DMAR** | DMA Remapping Table | Intel VT-d IOMMU configuration. Relevant for virtualization and device passthrough. |
| **IVRS** | I/O Virtualization Reporting Structure | AMD IOMMU configuration. The AMD equivalent of DMAR. |
| **BGRT** | Boot Graphics Resource Table | The OEM logo displayed during boot. (Occasionally overridden by Linux bootloaders.) |

### Reading ACPI tables

```bash
# List all ACPI tables
ls /sys/firmware/acpi/tables/

# Dump a specific table (requires root)
sudo cat /sys/firmware/acpi/tables/DSDT > dsdt.dat

# Decompile to readable ASL (requires iasl from acpica-tools)
iasl -d dsdt.dat
# Produces dsdt.dsl — human-readable ACPI source

# View parsed ACPI information
sudo acpidump    # Raw hex dump
sudo acpidump -b # Binary dump (for decompilation)
```

The decompiled DSDT is the definitive source of truth for what the
firmware tells the OS about the hardware. When diagnosing a
hardware issue on Linux — a device that is not detected, a power
state that does not work, a thermal zone that behaves incorrectly —
the DSDT is where the investigation starts.

## The `_OSI` problem

ACPI includes a method called `_OSI` (Operating System Interface)
that allows firmware to ask "which OS am I running under?" and
change its behavior accordingly. In theory, this enables firmware
to work around OS-specific bugs. In practice, it is the primary
mechanism by which firmware behaves differently under Linux than
under Windows.

A typical DSDT contains code like:

```
If (_OSI ("Windows 2022"))
{
    // Enable feature X, use code path Y
}
```

When Linux boots, the kernel responds to `_OSI` queries by claiming
compatibility with Windows versions. As of kernel 6.x, Linux
reports compatibility with Windows versions up to "Windows 2022."
This causes most firmware to execute the Windows-intended code
paths.

When this does not work — when the firmware's Windows code path
produces incorrect behavior under Linux — the kernel provides boot
parameters to override `_OSI` behavior:

```bash
# Tell firmware that no Windows version is running
acpi_osi=!  acpi_osi="Linux"

# Tell firmware a specific Windows version
acpi_osi=!  acpi_osi="Windows 2019"

# Multiple overrides
acpi_osi=!  acpi_osi="Linux"  acpi_osi="Windows 2015"
```

These are added to the kernel command line via the bootloader
configuration (see [Boot Management](boot-management.md)). The
`acpi_osi=!` clears the default list; subsequent `acpi_osi=`
entries add specific strings.

Common scenarios where `_OSI` overrides fix Linux issues:

- **Backlight control not working.** Firmware routes backlight
  control through a Windows-specific ACPI method. Adding
  `acpi_osi=!  acpi_osi="Windows 2009"` forces the firmware to
  use an older code path that the Linux kernel handles correctly.
- **Sleep/wake failures.** Firmware enables S0ix Modern Standby
  because it detects a "modern" Windows version. The Linux S0ix
  implementation does not work correctly on this platform. Forcing
  an older Windows version string causes the firmware to expose S3
  instead.
- **Missing devices.** Firmware hides devices from non-Windows OSes
  — intentionally or through code paths that only execute under
  `_OSI("Windows ...")`.

## Common ACPI kernel parameters

Beyond `_OSI` overrides, the kernel accepts several ACPI-related
boot parameters for diagnosing and working around firmware issues:

| Parameter | Effect |
|-----------|--------|
| `acpi=off` | Disable ACPI entirely. Last resort — most modern hardware will not function correctly without ACPI. No power management, no thermal management, no device enumeration beyond PCI. |
| `acpi=noirq` | Do not use ACPI for interrupt routing. Useful when ACPI interrupt tables are broken. |
| `acpi=strict` | Enforce strict ACPI compliance. Causes the kernel to reject tables with known errors rather than attempting to work around them. |
| `acpi_backlight=vendor` | Use the vendor-specific backlight driver instead of the ACPI backlight interface. Common fix for laptop backlight issues. |
| `acpi_backlight=native` | Use the GPU driver's native backlight control. |
| `acpi_enforce_resources=lax` | Allow the kernel to access hardware resources that ACPI has declared as owned by firmware. Required by some hardware monitoring tools (e.g., `lm-sensors` on certain platforms). |
| `acpi.ec_no_wakeup=1` | Prevent the embedded controller from waking the system from sleep. Fixes "laptop wakes immediately after suspend" on some platforms. |

These parameters are diagnostic tools, not permanent solutions.
If a parameter is required for the machine to function, document it
(in the bootloader configuration and in the machine's setup notes)
and check whether newer firmware or kernel versions resolve the
underlying issue.

## ACPI and the embedded controller

The Embedded Controller (EC) is a small microcontroller on the
motherboard — separate from the CPU and firmware — that manages
low-level hardware functions: battery charging, fan control,
keyboard backlight, lid switch, power button, and LED indicators.
The EC runs its own firmware and operates independently of the
main CPU and operating system.

ACPI provides an interface between the OS and the EC. The DSDT
defines EC-backed devices and methods that allow the OS to read
battery status, request fan speed changes, and respond to events
(lid close, power button press). When this interface works, the OS
and EC cooperate seamlessly. When it does not — because the DSDT's
EC definitions are wrong, incomplete, or Windows-specific — the
symptoms are some of the most puzzling Linux laptop issues:

- Battery capacity reported incorrectly or not at all
- Fan speed stuck at maximum or minimum regardless of temperature
- Lid close not triggering suspend
- Keyboard backlight not controllable
- Charging indicator LED not reflecting actual charging state

On ThinkPads specifically, the EC is well-documented by the
community. Tools like `thinkfan` bypass the ACPI thermal interface
and communicate with the EC directly to control fan speed. The
`thinkpad_acpi` kernel module provides a Linux-specific interface
to ThinkPad EC features that ACPI does not expose.

## Diagnosing ACPI issues

A structured approach to diagnosing ACPI-related problems on a
Linux workstation:

1. **Identify the symptom.** Is it power management (sleep, wake,
   battery)? Thermal (fans, throttling)? Device detection (missing
   hardware)? Input (lid switch, keyboard, backlight)?

2. **Check `dmesg` for ACPI errors.**
   ```bash
   dmesg | grep -i acpi
   dmesg | grep -i "firmware bug"
   # The kernel tags firmware problems explicitly
   ```

3. **Check which ACPI features are active.**
   ```bash
   cat /sys/firmware/acpi/pm_profile  # Power management profile
   ls /sys/bus/acpi/devices/          # ACPI-enumerated devices
   cat /sys/power/mem_sleep           # Available sleep states
   ```

4. **Compare with a working OS.** If the hardware works under
   Windows on the same machine, the problem is in how Linux
   interprets the ACPI tables, not in the hardware. The `_OSI`
   overrides described above are the first tool.

5. **Dump and decompile the DSDT.** Search for the device or method
   that corresponds to the failing feature. Look for `_OSI`
   conditionals that change behavior based on the detected OS.

6. **Search for existing kernel workarounds.** Many ACPI firmware
   bugs have known kernel patches or boot parameters. The
   Arch Wiki, the kernel mailing list, and vendor-specific Linux
   communities (e.g., the ThinkPad community) are the best sources.

7. **Report upstream.** If the firmware bug affects a commonly used
   platform and has no known workaround, reporting it to the kernel
   ACPI maintainers (via the kernel bugzilla or mailing list) is
   the path to a permanent fix. Include `acpidump` output, `dmesg`
   output, and a description of the expected vs actual behavior.
