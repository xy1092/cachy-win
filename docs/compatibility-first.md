# Compatibility First

This project is meant to keep Windows stable inside libvirt, not to evade
software checks.

Use this checklist when a Windows app is picky about running inside a VM:

1. Prefer the `office` profile first. It uses the smallest set of VM features.
2. Keep `host-passthrough` CPU mode and a fixed vCPU topology.
3. Use a normal qcow2/raw disk before trying physical disk passthrough.
4. Keep the Windows install on a VM-owned EFI disk when possible.
5. Install the VirtIO drivers in Windows, then reboot before changing the disk
   bus from SATA to VirtIO.
6. For gaming, pass through the real GPU and its audio function together.
7. Keep Windows Fast Startup and hibernation disabled.
8. Avoid changing SMBIOS values after the VM is already installed unless you
   need to reset a broken profile.

What not to do:

- Do not add stealth or anti-detection settings.
- Do not rely on ACS override unless you understand the hardware tradeoff.
- Do not mix the same Windows disk between multiple concurrent VM definitions.
- Do not pass the entire Linux/Windows shared disk into the VM.

If a game or protected app still refuses to run, the reliable fallback is to
boot Windows natively.
