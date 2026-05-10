#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${CACHY_WIN_ENV:-$ROOT_DIR/env.local}"
MODE="${1:-}"
CONFIRM=0
DEFINE_ONLY=0
NO_CHECK=0
GPU_BOUND=0

usage() {
  cat <<'USAGE'
Usage: scripts/launch.sh gaming|office [--confirm] [--define-only] [--no-check] [--env FILE]

Renders the selected libvirt profile, defines it with virsh, and starts it.
Gaming mode requires --confirm before GPU binding / display-manager actions.
USAGE
}

[[ $# -gt 0 ]] && shift || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --confirm)
      CONFIRM=1
      shift
      ;;
    --define-only)
      DEFINE_ONLY=1
      shift
      ;;
    --no-check)
      NO_CHECK=1
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

if [[ "$MODE" != "gaming" && "$MODE" != "office" ]]; then
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
else
  echo "warning: env file not found, using env.example defaults: $ENV_FILE" >&2
fi
LIBVIRT_URI="${LIBVIRT_URI:-qemu:///system}"

lock_file="/tmp/cachy-win.lock"
exec 9>"$lock_file"
if ! flock -n 9; then
  echo "another cachy-win launch is already running" >&2
  exit 1
fi

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing command: $1" >&2
    exit 1
  }
}

dom_running() {
  local name="$1"
  virsh -c "$LIBVIRT_URI" domstate "$name" >/tmp/cachy-win-domstate.$$ 2>/dev/null || return 1
  grep -qi '^running' /tmp/cachy-win-domstate.$$
}

require_cmd virsh
require_cmd envsubst
require_cmd flock

if [[ "$NO_CHECK" != "1" ]]; then
  "$ROOT_DIR/check.sh" --mode "$MODE" --env "$ENV_FILE"
fi

if dom_running "${CACHY_WIN_GAMING_NAME:-cachy-win-gaming}" || dom_running "${CACHY_WIN_OFFICE_NAME:-cachy-win-office}"; then
  echo "one cachy-win profile is already running; stop it before starting another profile" >&2
  exit 1
fi
rm -f /tmp/cachy-win-domstate.$$ 2>/dev/null || true

if [[ "$MODE" == "gaming" && "$CONFIRM" != "1" ]]; then
  cat >&2 <<'EOF'
Gaming mode may bind the configured GPU to vfio-pci and may stop the display manager.
Re-run with --confirm after closing unsaved graphical applications.
EOF
  exit 2
fi

xml_path="$("$ROOT_DIR/scripts/render-domain.sh" "$MODE" --env "$ENV_FILE")"
virsh -c "$LIBVIRT_URI" define "$xml_path"

if [[ "$DEFINE_ONLY" == "1" ]]; then
  echo "defined libvirt domain from $xml_path"
  exit 0
fi

if [[ "$MODE" == "gaming" ]]; then
  "$ROOT_DIR/scripts/gpu-bind.sh" bind --env "$ENV_FILE" --confirm
  GPU_BOUND=1
fi

domain_name="$([[ "$MODE" == "gaming" ]] && printf '%s' "$CACHY_WIN_GAMING_NAME" || printf '%s' "$CACHY_WIN_OFFICE_NAME")"
cleanup_on_error() {
  if [[ "$GPU_BOUND" == "1" ]]; then
    "$ROOT_DIR/scripts/gpu-bind.sh" unbind --env "$ENV_FILE" --confirm || true
  fi
}
trap cleanup_on_error ERR
virsh -c "$LIBVIRT_URI" start "$domain_name"
trap - ERR
echo "started $domain_name"
