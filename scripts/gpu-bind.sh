#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${CACHY_WIN_ENV:-$ROOT_DIR/env.local}"
ACTION="${1:-}"
CONFIRM=0

usage() {
  cat <<'USAGE'
Usage: scripts/gpu-bind.sh bind|unbind [--confirm] [--env FILE]

Binds the configured GPU PCI functions to vfio-pci, or releases them back to host drivers.
This script requires root when it actually writes to sysfs or controls systemd.
USAGE
}

[[ $# -gt 0 ]] && shift || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --confirm)
      CONFIRM=1
      shift
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

if [[ "$ACTION" != "bind" && "$ACTION" != "unbind" ]]; then
  usage >&2
  exit 2
fi

if [[ -f "$ROOT_DIR/env.example" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT_DIR/env.example"
fi
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

devices=()
[[ -n "${GAMING_GPU_VIDEO_PCI:-}" ]] && devices+=("$GAMING_GPU_VIDEO_PCI")
[[ -n "${GAMING_GPU_AUDIO_PCI:-}" ]] && devices+=("$GAMING_GPU_AUDIO_PCI")

if [[ "${#devices[@]}" -eq 0 ]]; then
  echo "no GPU PCI devices configured" >&2
  exit 1
fi

if [[ "$CONFIRM" != "1" ]]; then
  echo "refusing to $ACTION GPU without --confirm" >&2
  exit 2
fi

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "this action needs root; run with sudo or use the systemd service" >&2
  exit 1
fi

stop_dm() {
  if [[ "${STOP_DISPLAY_MANAGER:-0}" == "1" ]]; then
    systemctl stop "${DISPLAY_MANAGER:-display-manager}"
  fi
}

start_dm() {
  if [[ "${STOP_DISPLAY_MANAGER:-0}" == "1" ]]; then
    systemctl start "${DISPLAY_MANAGER:-display-manager}"
  fi
}

unbind_current_driver() {
  local pci="$1"
  local dev="/sys/bus/pci/devices/$pci"
  [[ -d "$dev" ]] || { echo "missing PCI device: $pci" >&2; exit 1; }
  if [[ -L "$dev/driver" ]]; then
    echo "$pci" > "$dev/driver/unbind"
  fi
}

bind_vfio() {
  local pci="$1"
  local dev="/sys/bus/pci/devices/$pci"
  echo vfio-pci > "$dev/driver_override"
  echo "$pci" > /sys/bus/pci/drivers_probe
}

clear_override() {
  local pci="$1"
  local dev="/sys/bus/pci/devices/$pci"
  [[ -d "$dev" ]] || return 0
  echo "" > "$dev/driver_override"
  echo "$pci" > /sys/bus/pci/drivers_probe
}

case "$ACTION" in
  bind)
    modprobe vfio-pci
    stop_dm
    for pci in "${devices[@]}"; do
      unbind_current_driver "$pci"
      bind_vfio "$pci"
    done
    ;;
  unbind)
    for pci in "${devices[@]}"; do
      unbind_current_driver "$pci"
      clear_override "$pci"
    done
    start_dm
    ;;
esac
