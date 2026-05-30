# Power and Thermal

Firmware controls the machine's power states, sleep behavior,
thermal management, and — on laptops — battery charge policy.
These settings have a disproportionate impact on the Linux
experience because power management is the area where firmware
behavior diverges most between Windows and Linux.

A machine that sleeps, wakes, and manages its fans flawlessly
under Windows may drain its battery in sleep, hang on wake, or run
its fans at full speed under Linux — not because Linux handles
power poorly, but because the firmware's power management tables
and methods were written for and tested against Windows exclusively.

## Sleep states

The [ACPI page](acpi.md) introduces sleep states (S-states) in
the context of the ACPI specification. This section covers the
practical firmware configuration.

### S3: Suspend to RAM (traditional)

S3 powers off nearly everything except RAM. The system state
(running processes, open files, kernel state) is preserved in
memory. Everything else — CPU, GPU, storage, USB controllers,
display — is powered off. Wake time is approximately 1-2 seconds.
Power draw in S3 is very low (typically < 1W for a laptop).

S3 is well-understood, well-supported on Linux, and predictable.
When a Linux machine supports S3, suspend and resume work reliably
in nearly all cases.

**Firmware setting name:** "Sleep State," "ACPI Sleep State,"
"Suspend Mode," or "S3" — sometimes buried under "Advanced" →
"Power Management" or "ACPI Configuration."

### S0ix: Modern Standby (connected standby)

S0ix is Intel and AMD's replacement for S3. Instead of powering
off the CPU and preserving state only in RAM, S0ix puts the CPU
into its deepest idle state while keeping select subsystems
powered — WiFi (for incoming notifications), USB (for wake
events), and sometimes the display controller (for ambient display
features).

The advantages of S0ix over S3:

- **Instant wake.** No 1-2 second resume delay — the machine
  transitions from idle to active instantly.
- **Connected standby.** The machine can receive network traffic,
  process push notifications, and update state while "asleep."
  This is the model that phones use.

The disadvantages of S0ix on Linux:

- **Higher power draw.** S0ix keeps more subsystems active than S3.
  On platforms where S0ix is not well-tuned for Linux, the power
  draw in "sleep" can be 5-10x higher than S3 — enough to drain a
  laptop battery overnight.
- **Firmware dependency.** S0ix requires firmware to correctly
  describe the constraints for each subsystem's low-power state.
  If the firmware's S0ix tables are wrong (common on platforms
  tested only against Windows), the CPU may not enter its deepest
  idle state, and power draw stays high.
- **Peripheral wakes.** Because S0ix keeps subsystems active, a
  buggy USB device, WiFi card, or Thunderbolt controller can
  prevent the system from entering a deep idle state or wake it
  immediately after suspension.

### The S3 vs S0ix problem

The industry is moving away from S3. Intel's platforms since 11th
generation (Tiger Lake, 2020) increasingly support only S0ix —
the firmware does not advertise S3 at all. AMD's mobile platforms
(Ryzen 6000+) similarly default to S0ix.

The practical impact for Linux users:

```bash
# Check which sleep states are available
cat /sys/power/mem_sleep
# Possible outputs:
#   s2idle [deep]     → both S0ix and S3 are available; S3 is default
#   [s2idle] deep     → both available; S0ix is default
#   [s2idle]          → only S0ix is available; S3 is not offered
```

If only `s2idle` appears, the firmware does not expose S3. The
options are:

1. **Use S0ix and tune it.** Monitor power draw in sleep with
   `powertop` or `turbostat`. Identify subsystems that are not
   entering low-power states. The kernel parameter
   `acpi.ec_no_wakeup=1` prevents the embedded controller from
   waking the system spuriously. The parameter
   `mem_sleep_default=s2idle` ensures S0ix is used (though it is
   the only option if S3 is absent).

2. **Force S3 via firmware modification.** Some platforms have a
   hidden firmware setting that re-enables S3. Lenovo ThinkPads in
   particular often have a "Linux Sleep" or "Windows and Linux"
   sleep mode option that switches from S0ix-only to S3. This
   setting is in the firmware's "Config" → "Power" menu on ThinkPads.

3. **Accept S0ix with its limitations.** On platforms where S0ix
   power draw is acceptable (modern AMD Ryzen 7000+ laptops tend to
   do better than Intel in this regard), S0ix's instant wake is a
   genuine usability improvement.

### Hibernate (S4)

Hibernate writes the full system state to the swap partition (or
swap file), then powers the machine off completely. Resume loads the
saved state from disk. Hibernate uses zero power during sleep but
has a slow resume time (proportional to RAM size and storage speed).

Hibernate requires:

- A swap partition or swap file at least as large as the system's
  RAM
- The `resume=` kernel parameter pointing to the swap device
- UEFI firmware that does not reset USB or PCIe state in a way
  that prevents the kernel from resuming cleanly

```bash
# Check if hibernate is available
cat /sys/power/state
# Should include "disk"

# Test hibernate
sudo systemctl hibernate
```

Hibernate is the most reliable sleep mode on Linux in terms of
power consumption (zero) and state preservation (everything saved
to disk). Its disadvantage is resume time — 10-30 seconds depending
on RAM and storage.

## Fan control

Firmware manages fans through one of two mechanisms:

### ACPI thermal zones

The firmware's DSDT defines thermal zones with temperature trip
points and cooling policies (see [ACPI](acpi.md)). The kernel reads
these definitions and manages fan speed through the `thermal`
subsystem.

```bash
# View thermal zones
ls /sys/class/thermal/
cat /sys/class/thermal/thermal_zone0/type
cat /sys/class/thermal/thermal_zone0/temp

# View cooling devices (fans, frequency limiters)
ls /sys/class/thermal/cooling_device*/
cat /sys/class/thermal/cooling_device0/type
cat /sys/class/thermal/cooling_device0/cur_state
```

If the ACPI thermal zone definitions are correct, Linux fan control
works automatically. If they are not (common — see the ACPI page's
discussion of firmware tested only against Windows), the symptoms
are fans stuck at full speed, fans not spinning up under load, or
fans oscillating rapidly between speeds.

### Embedded controller (EC) fan control

Some platforms — ThinkPads in particular — manage fans through the
embedded controller rather than ACPI thermal zones. The EC runs its
own fan control algorithm independently of the operating system. The
kernel can read the fan speed but cannot control it through ACPI.

On ThinkPads, the `thinkpad_acpi` kernel module provides an
interface to the EC's fan control:

```bash
# Read current fan speed (ThinkPad)
cat /proc/acpi/ibm/fan

# Set fan level manually (ThinkPad)
# Requires thinkpad_acpi module loaded with fan_control=1
echo "level 7" | sudo tee /proc/acpi/ibm/fan
echo "level auto" | sudo tee /proc/acpi/ibm/fan

# Load thinkpad_acpi with fan control enabled
sudo modprobe thinkpad_acpi fan_control=1
# Persist: echo "options thinkpad_acpi fan_control=1" | sudo tee /etc/modprobe.d/thinkpad.conf
```

`thinkfan` is a daemon that provides configurable fan curves for
ThinkPads, reading temperature sensors and setting fan levels via
the EC interface. It is the recommended approach for ThinkPad fan
management on Linux when the default EC algorithm is too
aggressive or too conservative.

### Firmware fan curve settings

Some firmware — primarily on desktops with AMI Aptio or enthusiast
motherboard firmware — exposes fan curve configuration directly:

- **Fan headers:** Which physical fan connector each setting
  controls (CPU_FAN, CHA_FAN, SYS_FAN).
- **Fan mode:** DC (voltage control, for 3-pin fans) or PWM
  (pulse-width modulation, for 4-pin fans).
- **Temperature source:** Which sensor drives the fan curve (CPU
  package temp, motherboard temp, VRM temp).
- **Curve points:** Temperature/fan-speed pairs that define the
  curve.
- **Minimum duty cycle:** The lowest speed the fan will spin at.
  Setting this too low can stall some fans.

These settings work identically under Linux and Windows because
they are implemented in firmware or the fan controller chip, not
the OS.

## Battery management (laptops)

### Charge thresholds

Some laptop firmware — most notably Lenovo ThinkPads — allows
setting battery charge start and stop thresholds. When the battery
reaches the stop threshold, charging halts. Charging resumes when
the battery drops to the start threshold.

Setting conservative thresholds (e.g., start 75%, stop 80%)
significantly extends battery longevity for machines that spend
most of their time plugged in. Lithium-ion batteries degrade faster
when kept at 100% charge continuously.

On ThinkPads, charge thresholds can be set from firmware (BIOS
Setup → Config → Power → Battery Charge Thresholds) or from Linux
via the `thinkpad_acpi` module:

```bash
# Read current thresholds (ThinkPad)
cat /sys/class/power_supply/BAT0/charge_control_start_threshold
cat /sys/class/power_supply/BAT0/charge_control_end_threshold

# Set thresholds
echo 75 | sudo tee /sys/class/power_supply/BAT0/charge_control_start_threshold
echo 80 | sudo tee /sys/class/power_supply/BAT0/charge_control_end_threshold

# Persist with tlp or a systemd service
```

`tlp` is a Linux power management tool that provides a
configuration file for charge thresholds and other power settings:

```bash
# /etc/tlp.conf (excerpt)
START_CHARGE_THRESH_BAT0=75
STOP_CHARGE_THRESH_BAT0=80
```

### Power profiles

Modern Linux distributions integrate with `power-profiles-daemon`
(GNOME) or `tuned` (Fedora server/workstation) to provide
system-wide power profiles:

```bash
# List available profiles
powerprofilesctl list

# Set profile
powerprofilesctl set balanced
powerprofilesctl set power-saver
powerprofilesctl set performance
```

These profiles adjust CPU governor, PCIe ASPM policy, disk APM,
and other power settings. They work in conjunction with (not in
place of) firmware power settings.

## Wake-on-LAN

Wake-on-LAN (WOL) allows the machine to be powered on remotely by
receiving a "magic packet" on its network interface. The network
controller remains powered in S3/S4/S5 states and monitors for the
magic packet.

Firmware settings for WOL:

| Setting | Description | Recommendation |
|---------|-------------|----------------|
| Wake on LAN | Enable the feature | Enable if remote wake is needed |
| WOL from S3/S4/S5 | Which power states allow WOL | S3 and S5 for most use cases |
| PXE Boot | Network boot (related but distinct) | Disable unless using network boot |

```bash
# Check WOL status on Linux
sudo ethtool <interface> | grep Wake-on
# g = magic packet enabled
# d = disabled

# Enable WOL
sudo ethtool -s <interface> wol g

# Persist (varies by distribution — NetworkManager or systemd-networkd)
```

## CPU power limits (PL1/PL2)

Some firmware exposes CPU power limits that affect sustained and
burst performance:

**PL1 (Power Limit 1):** The sustained power limit — the wattage
the CPU can draw continuously. At or above PL1, the CPU throttles
to maintain the power budget.

**PL2 (Power Limit 2):** The burst power limit — the wattage the
CPU can draw for short bursts (typically 28-56 seconds) before
falling back to PL1. Higher PL2 allows more aggressive turbo boost
at the cost of higher peak temperatures.

**Tau:** The duration the CPU can sustain PL2 before throttling to
PL1.

On desktops with enthusiast firmware, these are directly
configurable. On laptops, they are usually fixed or hidden behind
manufacturer settings (Lenovo's "Intelligent Cooling" or Dell's
"Thermal Management"). On Linux, Intel CPUs expose power limits
through `intel_rapl`:

```bash
# Read current power limits
sudo cat /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw  # PL1
sudo cat /sys/class/powercap/intel-rapl:0/constraint_1_power_limit_uw  # PL2
# Values are in microwatts
```

## Questions to ask

1. Does the machine support S3 (deep sleep)? `cat /sys/power/mem_sleep`
   — if only `s2idle` appears, investigate whether the firmware has
   a hidden S3 option (ThinkPads: Config → Power → Sleep State).
2. Is battery drain in sleep acceptable? If the machine loses more
   than 5% overnight, S0ix is not entering deep idle. Check
   `turbostat` or `powertop` for subsystems blocking low-power
   states.
3. Are fans behaving correctly? Full speed at idle or no spin-up
   under load both indicate firmware thermal table issues.
   `sensors` (from `lm-sensors`) shows current temperatures.
4. Are battery charge thresholds set? For machines that spend most
   of their time plugged in, setting 75/80 thresholds extends
   battery longevity significantly.
5. Is Wake-on-LAN needed? If so, is it enabled in both firmware and
   the OS? Both must agree for WOL to work.
