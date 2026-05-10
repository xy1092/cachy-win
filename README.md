# cachy-win

High-performance Windows VM profiles for CachyOS/Arch Linux using libvirt,
QEMU/KVM, VirtIO, and optional VFIO GPU passthrough.

The repository provides two launch paths:

- `office`: light CPU/RAM profile, VirtIO graphics, SPICE display, suited for
  office apps and quick Windows-only tools.
- `gaming`: larger CPU/RAM profile, host-passthrough CPU, optional hugepages,
  and a dedicated GPU passed through with VFIO.

## Result of the Claude Debate

Claude and Codex converged on this boundary:

- Use libvirt/QEMU/KVM as the base.
- Keep two explicit profiles instead of hiding everything behind one opaque VM.
- Default to a normal qcow2/raw Windows disk.
- Support existing physical Windows disks only as an advanced path.
- Do not automatically change firmware, bootloader, initramfs, ACS override,
  Windows BCD, BitLocker, or GPU BIOS state.
- Use checks, locks, templates, and clear confirmation for risky operations.

## Files

```text
env.example                         host-specific settings template
check.sh                            host readiness and safety checks
xml/*.xml.in                        libvirt XML templates
scripts/render-domain.sh            renders XML into build/
scripts/launch.sh                   starts office or gaming profile
scripts/stop.sh                     stops a profile and releases gaming GPU
scripts/gpu-bind.sh                 binds/unbinds the GPU to vfio-pci
systemd/cachy-win-gaming.service    optional root-managed gaming lifecycle
desktop/*.desktop                   optional launchers
docs/physical-disk.md               existing Windows disk notes
```

## Install Host Packages

On CachyOS/Arch:

```bash
sudo pacman -S --needed qemu-full libvirt virt-manager edk2-ovmf dnsmasq virtio-win
sudo systemctl enable --now libvirtd
sudo usermod -aG libvirt,kvm "$USER"
```

Log out and back in after changing groups.

## Configure

```bash
cp env.example env.local
$EDITOR env.local
```

Set at least:

- `WINDOWS_DISK_IMAGE` for the default qcow2/raw VM disk.
- `GAMING_GPU_VIDEO_PCI` and `GAMING_GPU_AUDIO_PCI` for GPU passthrough.
- `GAMING_MEMORY_MIB`, `GAMING_VCPUS`, `OFFICE_MEMORY_MIB`, and `OFFICE_VCPUS`.

Find GPU addresses:

```bash
lspci -nn | grep -Ei 'vga|3d|audio'
```

Run checks:

```bash
./check.sh --mode all
```

## Start Profiles

Office:

```bash
./scripts/launch.sh office
```

Gaming:

```bash
sudo ./scripts/launch.sh gaming --confirm
```

Gaming mode may bind the configured GPU to `vfio-pci` and stop the display
manager if `STOP_DISPLAY_MANAGER=1`. Close graphical apps first.

The launcher uses `flock` and libvirt domain state checks so the office and
gaming profiles do not run at the same time against the same Windows disk.

## Existing Windows Install

Yes, an already-installed Windows system can sometimes be booted as a VM. There
are two cases:

- Windows on its own physical disk: reasonable advanced path.
- Windows partition on the same disk as Linux: do not pass the whole disk;
  partition passthrough is possible but needs manual EFI/BCD work.

See [docs/physical-disk.md](docs/physical-disk.md).

## What This Does Not Automate

- BIOS/UEFI settings such as SVM, VT-x, IOMMU, or dGPU mux mode.
- Bootloader kernel parameters.
- initramfs generation.
- ACS override.
- Windows installation, activation, BitLocker, or BCD repair.
- GPU VBIOS dumping or flashing.

Those steps are too machine-specific and too risky for an automatic script.
