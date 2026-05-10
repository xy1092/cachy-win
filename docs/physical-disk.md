# Existing Windows Disk / Partition

This project defaults to a qcow2/raw virtual disk. Booting an existing bare-metal
Windows install is possible, but it is an advanced path.

## Best Case: Windows Owns a Whole Disk

The clean setup is:

- Linux is running from one disk.
- Windows is installed on another whole disk.
- No partition from the Windows disk is mounted in Linux.
- The VM receives the whole Windows disk through `DISK_BACKEND=physical`.

Example:

```bash
DISK_BACKEND=physical
PHYSICAL_WINDOWS_DISK=/dev/disk/by-id/nvme-SAMSUNG_...
```

Use `/dev/disk/by-id/...` or `/dev/disk/by-partuuid/...`, not `/dev/nvme0n1`,
because kernel device ordering can change.

Before starting the VM:

1. Boot Windows natively once.
2. Disable Fast Startup and hibernation:

   ```powershell
   powercfg /h off
   ```

3. Install VirtIO storage/network drivers in Windows.
4. Shut Windows down fully.
5. Make sure Linux did not auto-mount any Windows partition.

## Harder Case: Windows Partition Shares the Linux Disk

If Windows and Linux are on the same physical disk, do not pass the whole disk to
the VM. The VM would also see the mounted Linux root filesystem, which risks data
loss.

In the current machine layout seen during creation of this repo, the Windows OS
partition is `/dev/nvme0n1p3`, while Linux is mounted from `/dev/nvme0n1p5` on
the same disk. That means whole-disk passthrough of `/dev/nvme0n1` is not a safe
option.

Partition passthrough can be attempted:

```bash
DISK_BACKEND=physical
PHYSICAL_WINDOWS_DISK=/dev/disk/by-partuuid/<windows-os-partuuid>
```

However, a bare-metal Windows install usually expects its EFI System Partition
and BCD store. When passing only the OS partition, you may need a separate OVMF
NVRAM entry, a repair ISO, or a VM-owned EFI disk to boot `bootmgfw.efi`.

This project detects the obvious unsafe case, but it does not automatically
repair Windows boot files.

## Risks

- Windows activation may see native boot and VM boot as different hardware.
- BitLocker may ask for a recovery key after virtualized boot.
- Fast Startup or hibernation can corrupt NTFS when Linux and Windows both touch
  the same filesystem state.
- Anti-cheat systems may reject a VM even with GPU passthrough.
- Passing the wrong block device can destroy data.

The repository intentionally does not edit bootloader entries, initramfs, BCD,
BitLocker, or Windows activation state.
