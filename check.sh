#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${CACHY_WIN_ENV:-$ROOT_DIR/env.local}"
MODE="all"

usage() {
  cat <<'USAGE'
Usage: ./check.sh [--mode gaming|office|all] [--env FILE]

Checks whether the host looks ready for the cachy-win libvirt profiles.
It does not change bootloader, initramfs, BIOS, libvirt, or GPU bindings.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
    --env)
      ENV_FILE="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$MODE" != "all" && "$MODE" != "gaming" && "$MODE" != "office" ]]; then
  echo "invalid mode: $MODE" >&2
  exit 2
fi

if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
elif [[ -f "$ROOT_DIR/env.example" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT_DIR/env.example"
fi

LIBVIRT_URI="${LIBVIRT_URI:-qemu:///system}"

fails=0
warns=0

pass() { printf 'PASS  %s\n' "$*"; }
warn() { printf 'WARN  %s\n' "$*"; warns=$((warns + 1)); }
fail() { printf 'FAIL  %s\n' "$*"; fails=$((fails + 1)); }

need_cmd() {
  if command -v "$1" >/dev/null 2>&1; then
    pass "command exists: $1"
  else
    fail "missing command: $1"
  fi
}

mounted_under_device() {
  local dev="$1"
  [[ -b "$dev" ]] || return 1
  lsblk -nr -o MOUNTPOINTS "$dev" 2>/dev/null | grep -q '[^[:space:]]'
}

device_type() {
  lsblk -ndo TYPE "$1" 2>/dev/null | head -n 1
}

print_iommu_group() {
  local pci="$1"
  local path="/sys/bus/pci/devices/$pci/iommu_group"
  if [[ -e "$path" ]]; then
    basename "$(readlink -f "$path")"
  else
    printf 'none'
  fi
}

check_group_clean() {
  local group="$1"
  shift
  local allowed=("$@")
  local group_dir="/sys/kernel/iommu_groups/$group/devices"
  local extra=()
  local dev pci ok
  [[ -d "$group_dir" ]] || return 0
  for dev in "$group_dir"/*; do
    pci="$(basename "$dev")"
    ok=0
    for allowed_pci in "${allowed[@]}"; do
      if [[ "$pci" == "$allowed_pci" ]]; then
        ok=1
        break
      fi
    done
    [[ "$ok" == "1" ]] || extra+=("$pci")
  done
  if [[ "${#extra[@]}" -gt 0 ]]; then
    fail "IOMMU group $group contains unconfigured devices: ${extra[*]}"
  else
    pass "IOMMU group $group contains only the configured passthrough functions"
  fi
}

check_pci() {
  local label="$1"
  local pci="$2"
  if [[ -z "$pci" ]]; then
    fail "$label PCI address is empty"
    return
  fi
  if [[ -d "/sys/bus/pci/devices/$pci" ]]; then
    pass "$label exists: $pci (IOMMU group $(print_iommu_group "$pci"))"
    lspci -nnk -s "$pci" 2>/dev/null | sed 's/^/      /' || true
  else
    fail "$label PCI address not found: $pci"
  fi
}

echo "== Commands =="
need_cmd bash
need_cmd envsubst
need_cmd flock
need_cmd lspci
need_cmd lsblk
need_cmd virsh
if command -v virsh >/dev/null 2>&1; then
  if virsh -c "$LIBVIRT_URI" uri >/dev/null 2>&1; then
    pass "libvirt connection works: $LIBVIRT_URI"
  else
    fail "cannot connect to libvirt URI: $LIBVIRT_URI"
  fi
fi

echo
echo "== CPU virtualization =="
if grep -Eq '(vmx|svm)' /proc/cpuinfo; then
  pass "CPU exposes VMX/SVM"
else
  fail "CPU virtualization flag not found; enable Intel VT-x or AMD-V in firmware"
fi

if [[ -d /sys/module/kvm ]]; then
  pass "kvm module is loaded"
else
  warn "kvm module is not loaded yet"
fi

echo
echo "== IOMMU =="
if [[ -d /sys/kernel/iommu_groups ]] && find /sys/kernel/iommu_groups -mindepth 1 -maxdepth 1 -type d | grep -q .; then
  pass "IOMMU groups are visible"
else
  fail "IOMMU groups are not visible; configure intel_iommu=on or amd_iommu=on manually"
fi

echo
echo "== OVMF =="
if [[ -n "${OVMF_CODE:-}" && -f "${OVMF_CODE:-}" ]]; then
  pass "OVMF code exists: $OVMF_CODE"
else
  warn "OVMF code file not found: ${OVMF_CODE:-unset}"
fi

echo
echo "== Disk backend =="
case "${DISK_BACKEND:-qcow2}" in
  qcow2)
    if [[ -n "${WINDOWS_DISK_IMAGE:-}" ]]; then
      if [[ -e "$WINDOWS_DISK_IMAGE" ]]; then
        pass "qcow2/raw image exists: $WINDOWS_DISK_IMAGE"
      else
        warn "disk image does not exist yet: $WINDOWS_DISK_IMAGE"
      fi
    else
      fail "WINDOWS_DISK_IMAGE is empty"
    fi
    ;;
  physical)
    if [[ -z "${PHYSICAL_WINDOWS_DISK:-}" ]]; then
      fail "PHYSICAL_WINDOWS_DISK is empty"
    elif [[ ! -b "$PHYSICAL_WINDOWS_DISK" ]]; then
      fail "physical device does not exist or is not a block device: $PHYSICAL_WINDOWS_DISK"
    else
      dtype="$(device_type "$PHYSICAL_WINDOWS_DISK")"
      if mounted_under_device "$PHYSICAL_WINDOWS_DISK"; then
        fail "physical device has mounted filesystems; do not pass a mounted Linux disk into Windows: $PHYSICAL_WINDOWS_DISK"
      else
        pass "physical device has no mounted filesystem according to lsblk: $PHYSICAL_WINDOWS_DISK"
      fi
      if [[ "$dtype" == "disk" ]]; then
        pass "physical backend points at a whole disk"
      elif [[ "$dtype" == "part" ]]; then
        warn "physical backend points at a partition; booting an existing bare-metal Windows partition needs manual EFI/BCD work"
      else
        warn "unknown physical backend type for $PHYSICAL_WINDOWS_DISK"
      fi
    fi
    ;;
  *)
    fail "invalid DISK_BACKEND: ${DISK_BACKEND:-unset}"
    ;;
esac

if [[ "$MODE" == "gaming" || "$MODE" == "all" ]]; then
  echo
  echo "== Gaming GPU passthrough =="
  need_cmd systemctl
  check_pci "GPU video" "${GAMING_GPU_VIDEO_PCI:-}"
  if [[ -n "${GAMING_GPU_AUDIO_PCI:-}" ]]; then
    check_pci "GPU audio" "$GAMING_GPU_AUDIO_PCI"
  else
    warn "GAMING_GPU_AUDIO_PCI is empty; many GPUs need the HDMI/DP audio function passed too"
  fi
  if [[ -n "${GAMING_GPU_VIDEO_PCI:-}" && -e "/sys/bus/pci/devices/${GAMING_GPU_VIDEO_PCI}/iommu_group" ]]; then
    gpu_group="$(print_iommu_group "$GAMING_GPU_VIDEO_PCI")"
    allowed_group_devices=("$GAMING_GPU_VIDEO_PCI")
    [[ -n "${GAMING_GPU_AUDIO_PCI:-}" ]] && allowed_group_devices+=("$GAMING_GPU_AUDIO_PCI")
    check_group_clean "$gpu_group" "${allowed_group_devices[@]}"
  fi
  gpu_count="$(lspci -nn 2>/dev/null | grep -Eic 'VGA compatible controller|3D controller|Display controller' || true)"
  if [[ "${gpu_count:-0}" -gt 1 ]]; then
    pass "multiple display adapters detected"
  else
    warn "only one display adapter detected; host needs another GPU or a headless/Looking Glass workflow"
  fi
  if [[ -d /sys/module/vfio_pci ]]; then
    pass "vfio-pci module is loaded"
  else
    warn "vfio-pci module is not loaded yet"
  fi
  if [[ "${GAMING_USE_HUGEPAGES:-0}" == "1" ]]; then
    hp_total="$(awk '/HugePages_Total/ {print $2}' /proc/meminfo)"
    if [[ "${hp_total:-0}" -gt 0 ]]; then
      pass "hugepages are reserved: $hp_total pages"
    else
      warn "GAMING_USE_HUGEPAGES=1 but no hugepages are reserved"
    fi
  fi
fi

echo
echo "== Summary =="
printf 'Failures: %d, warnings: %d\n' "$fails" "$warns"
if [[ "$fails" -gt 0 ]]; then
  exit 1
fi
