#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${CACHY_WIN_ENV:-$ROOT_DIR/env.local}"

if [[ -f "$ROOT_DIR/env.example" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT_DIR/env.example"
fi
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

LIBVIRT_URI="${LIBVIRT_URI:-qemu:///system}"

if command -v zenity >/dev/null 2>&1; then
  chooser="zenity"
elif command -v kdialog >/dev/null 2>&1; then
  chooser="kdialog"
else
  echo "missing GUI chooser: install zenity or kdialog" >&2
  exit 1
fi

choose_action_zenity() {
  zenity --list \
    --title="Cachy Win" \
    --width=560 \
    --height=340 \
    --column="Action" \
    --column="Profile" \
    --column="Notes" \
    "Start" "Office" "Light desktop profile" \
    "Start" "Gaming" "VFIO GPU path, requires admin" \
    "Stop" "Office" "Graceful shutdown" \
    "Stop" "Gaming" "Graceful shutdown and GPU release" \
    "Open" "Virt-Manager" "Open the VM manager" \
    "Check" "All" "Run host readiness check"
}

choose_action_kdialog() {
  kdialog --menu "Cachy Win" \
    start-office "Start Office" \
    start-gaming "Start Gaming" \
    stop-office "Stop Office" \
    stop-gaming "Stop Gaming" \
    virt-manager "Open Virt-Manager" \
    check-all "Run Checks"
}

if [[ "$chooser" == "zenity" ]]; then
  selection="$(choose_action_zenity || true)"
  [[ -n "${selection:-}" ]] || exit 0
  action="$(printf '%s' "$selection" | cut -d'|' -f1 | tr '[:upper:]' '[:lower:]')"
  profile="$(printf '%s' "$selection" | cut -d'|' -f2 | tr '[:upper:]' '[:lower:]')"
else
  selection="$(choose_action_kdialog || true)"
  [[ -n "${selection:-}" ]] || exit 0
  case "$selection" in
    start-office) action="start"; profile="office" ;;
    start-gaming) action="start"; profile="gaming" ;;
    stop-office) action="stop"; profile="office" ;;
    stop-gaming) action="stop"; profile="gaming" ;;
    virt-manager) action="open"; profile="virt-manager" ;;
    check-all) action="check"; profile="all" ;;
    *) exit 0 ;;
  esac
fi

case "$action" in
  start)
    if [[ "$profile" == "gaming" ]]; then
      exec pkexec env "CACHY_WIN_ENV=$ENV_FILE" "LIBVIRT_URI=$LIBVIRT_URI" "$ROOT_DIR/scripts/launch.sh" gaming --confirm
    fi
    exec env "CACHY_WIN_ENV=$ENV_FILE" "LIBVIRT_URI=$LIBVIRT_URI" "$ROOT_DIR/scripts/launch.sh" office
    ;;
  stop)
    if [[ "$profile" == "gaming" ]]; then
      exec pkexec env "CACHY_WIN_ENV=$ENV_FILE" "LIBVIRT_URI=$LIBVIRT_URI" "$ROOT_DIR/scripts/stop.sh" gaming
    fi
    exec env "CACHY_WIN_ENV=$ENV_FILE" "LIBVIRT_URI=$LIBVIRT_URI" "$ROOT_DIR/scripts/stop.sh" office
    ;;
  open)
    exec virt-manager
    ;;
  check)
    exec "$ROOT_DIR/check.sh" --mode all --env "$ENV_FILE"
    ;;
  *)
    echo "unknown action: $action" >&2
    exit 1
    ;;
esac
