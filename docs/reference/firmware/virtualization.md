# Virtualization

Hardware virtualization support is a firmware setting that
determines whether the CPU exposes its virtualization extensions
to the operating system. These extensions allow a hypervisor — the
software that creates and manages virtual machines — to run guest
operating systems with near-native performance by using CPU
hardware features instead of emulating them in software.

For a Linux development workstation, virtualization support is not
optional. Docker, Podman, QEMU/KVM, VirtualBox, and most container
runtimes require hardware virtualization. Without it, containers
run in degraded mode (or refuse to start), VMs fall back to slow
software emulation, and development workflows that depend on
isolated environments break.

On most desktop motherboards, virtualization is enabled by default.
On many laptops — especially consumer-grade models — it is disabled
by default. This is the first firmware setting to check on any new
Linux workstation.

## CPU virtualization extensions

### Intel VT-x

Intel's Virtualization Technology for x86 (VT-x) is the base
virtualization extension on Intel CPUs. It provides:

- **VMX root and non-root modes.** The hypervisor runs in VMX root
  mode with full hardware access. Guest operating systems run in VMX
  non-root mode, where privileged instructions trap to the
  hypervisor instead of executing directly. This allows the guest to
  run its own kernel without interfering with the host.
- **Extended Page Tables (EPT).** Hardware-assisted memory
  virtualization. Without EPT, the hypervisor must maintain shadow
  page tables — intercepting every guest page table modification and
  translating it. EPT lets the CPU handle guest-to-host address
  translation in hardware, with dramatically less overhead.
- **VPID (Virtual Processor ID).** Tags TLB entries with a VM
  identifier, avoiding full TLB flushes on VM entry/exit. Reduces
  the performance cost of context switches between VMs and the host.

**Firmware setting name:** "Intel Virtualization Technology,"
"Intel VT-x," "VMX," or simply "Virtualization Technology."
Location varies: typically under "CPU Configuration," "Advanced,"
or "Security."

### AMD-V / SVM

AMD's virtualization extensions (AMD-V, historically called SVM —
Secure Virtual Machine) provide equivalent functionality to VT-x:

- **SVM (Secure Virtual Machine).** The base extension — VMX
  root/non-root equivalent, trap-and-emulate for privileged guest
  instructions.
- **RVI (Rapid Virtualization Indexing).** AMD's equivalent of
  Intel's EPT — hardware-assisted nested page tables.
- **Tagged TLB.** AMD's equivalent of Intel's VPID.

AMD-V has been enabled by default on AMD CPUs since approximately
2015. On older systems or budget motherboards, it may need to be
enabled manually.

**Firmware setting name:** "SVM Mode," "AMD-V," "AMD Virtualization,"
or "Secure Virtual Machine." Same general location as Intel's
setting.

### Verifying virtualization support

```bash
# Check CPU flags for virtualization support
grep -E 'vmx|svm' /proc/cpuinfo

# vmx = Intel VT-x
# svm = AMD-V / SVM

# If the flag is present, the CPU supports virtualization
# If absent, either the CPU lacks support (unlikely on anything
# made after 2010) or the firmware has it disabled

# More readable check
lscpu | grep -i virtualization
# Output: "Virtualization: VT-x" or "Virtualization: AMD-V"

# Check if KVM modules are loaded (Linux hypervisor)
lsmod | grep kvm
# kvm_intel or kvm_amd should appear
```

If `grep` finds no `vmx` or `svm` flags and `lscpu` shows no
virtualization, the setting is almost certainly disabled in
firmware. Reboot, enter firmware setup, enable it, and reboot
again.

## IOMMU: I/O virtualization

IOMMU (Input/Output Memory Management Unit) extends virtualization
from the CPU to I/O devices. It provides:

- **DMA remapping.** Controls which memory regions a device can
  access via Direct Memory Access. Without IOMMU, a malicious or
  buggy device driver could use DMA to read or write arbitrary
  host memory. IOMMU restricts each device to its assigned memory
  regions.
- **Device passthrough.** Allows a physical device (GPU, NIC,
  storage controller) to be assigned directly to a VM with
  near-native performance. The IOMMU ensures the device can only
  access the VM's memory, not the host's or other VMs'.
- **Interrupt remapping.** Prevents devices from injecting
  arbitrary interrupts — a security mechanism that complements DMA
  remapping.

### Intel VT-d

Intel's Virtualization Technology for Directed I/O (VT-d) is
Intel's IOMMU implementation.

**Firmware setting name:** "Intel VT-d," "VT for Directed I/O,"
"Directed I/O," or "IOMMU." Often in a separate setting from VT-x.

**When to enable:** VT-d should be enabled on any development
workstation that runs VMs or containers. Even if device passthrough
is not needed, DMA remapping provides a security boundary that
protects against DMA attacks from compromised or buggy peripherals
(particularly relevant for Thunderbolt devices, which have direct
DMA access — see [USB and Thunderbolt](usb.md)).

### AMD-Vi / AMD IOMMU

AMD's I/O Virtualization Technology (AMD-Vi, also called AMD IOMMU)
provides the same capabilities as VT-d.

**Firmware setting name:** "IOMMU," "AMD IOMMU," or "AMD-Vi."
On some consumer-grade AMD motherboards, this setting is not exposed
in firmware because AMD-Vi is always enabled or controlled by a
different mechanism (the `iommu=on` kernel parameter).

### Kernel configuration

IOMMU is a hardware feature that also requires kernel support to
be active:

```bash
# Check if IOMMU is active
dmesg | grep -i iommu

# Check IOMMU groups (each group is an isolation boundary)
find /sys/kernel/iommu_groups/ -type l -exec basename {} \; | sort -n | head -20

# If IOMMU is not active despite being enabled in firmware,
# add the kernel parameter:
# Intel: intel_iommu=on
# AMD:   iommu=pt  (passthrough mode — recommended for desktops)
#
# Add to GRUB_CMDLINE_LINUX in /etc/default/grub
# Then: sudo grub2-mkconfig -o /boot/grub2/grub.cfg  (Fedora)
#   or: sudo update-grub  (Debian/Ubuntu)
```

The `iommu=pt` (passthrough) option is recommended for workstations
that do not use device passthrough. It enables IOMMU for security
(DMA remapping) but does not impose the translation overhead on
every DMA transaction — devices that are not explicitly assigned to
a VM access memory through a direct mapping.

## Nested virtualization

Nested virtualization allows a VM to run its own VMs — a hypervisor
inside a hypervisor. This is relevant for development workstations
when:

- Testing infrastructure automation (Terraform, Ansible) that
  provisions VMs, inside a VM
- Running a CI/CD environment locally that itself creates VMs
- Running Docker inside a VM (Docker Desktop on Linux in a VM, or
  containers inside a QEMU/KVM guest)

### CPU support

Nested virtualization is a CPU feature that must be enabled in both
firmware and the host hypervisor:

**Intel:** Supported on most CPUs since Haswell (2013). The `vmx`
flag in `/proc/cpuinfo` indicates base support; the KVM module
parameter `nested` controls whether it is exposed to guests.

**AMD:** Supported on most CPUs since Zen (2017). AMD's nested
virtualization is generally considered more mature and performant
than Intel's.

### Enabling nested virtualization

```bash
# Check if nested virtualization is currently enabled
cat /sys/module/kvm_intel/parameters/nested  # Intel
cat /sys/module/kvm_amd/parameters/nested    # AMD
# 'Y' or '1' = enabled

# Enable at runtime (does not persist across reboots)
sudo modprobe -r kvm_intel  # Unload (fails if VMs are running)
sudo modprobe kvm_intel nested=1

# Enable persistently
echo "options kvm_intel nested=1" | sudo tee /etc/modprobe.d/kvm-nested.conf
# or for AMD:
echo "options kvm_amd nested=1" | sudo tee /etc/modprobe.d/kvm-nested.conf
```

### Performance considerations

Nested virtualization adds overhead. Each VM exit in the nested
guest must trap through two layers of hypervisor. EPT/RVI
translation adds a level of indirection. For development and
testing workloads this overhead is acceptable. For performance-
sensitive workloads, nested virtualization is not a substitute for
bare-metal or single-layer virtualization.

## Firmware settings reference

| Setting | Intel name | AMD name | Recommendation |
|---------|-----------|----------|----------------|
| CPU virtualization | VT-x / VMX / Virtualization Technology | SVM / AMD-V | **Enable** |
| IOMMU | VT-d / Directed I/O | AMD IOMMU / AMD-Vi | **Enable** |
| Nested virtualization | (kernel parameter, not firmware) | (kernel parameter, not firmware) | Enable if needed |
| Execute Disable Bit | XD / Execute Disable | NX / No Execute | **Enable** (required by most OSes) |

The **Execute Disable Bit** (Intel XD, AMD NX) is related but
distinct — it marks memory pages as non-executable, preventing
code execution from data regions. It is required by modern
operating systems (Windows 8+ and all modern Linux kernels) and
should always be enabled. Some firmware lists it alongside
virtualization settings.

## Questions to ask

1. Is VT-x or AMD-V enabled? Run `lscpu | grep Virtualization` —
   if the output is empty, check firmware.
2. Is IOMMU enabled? Run `dmesg | grep -i iommu` — if no IOMMU
   group messages appear, check firmware and kernel parameters.
3. Are KVM modules loaded? `lsmod | grep kvm` should show
   `kvm_intel` or `kvm_amd`. If not, the kernel may need the
   `kvm` module installed or the firmware setting is disabled.
4. Does the development workflow require nested virtualization? If
   so, verify with `cat /sys/module/kvm_*/parameters/nested`.
5. If running Docker or Podman: does the container runtime report
   hardware virtualization as available? `docker info` and
   `podman info` both report the backing runtime and
   virtualization status.
