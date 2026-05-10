#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${CACHY_WIN_ENV:-$ROOT_DIR/env.local}"
MODE="${1:-}"
TIMEOUT=90

usage() {
  cat <<'USAGE'
Usage: scripts/stop.sh gaming|office [--timeout SECONDS] [--env FILE]

Requests a graceful shutdown, waits until the VM stops, then releases the GPU
for gaming mode.
USAGE
}

[[ $# -gt 0 ]] && shift || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --timeout)
      TIMEOUT="${2:-}"
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
fi
LIBVIRT_URI="${LIBVIRT_URI:-qemu:///system}"

domain_name="$([[ "$MODE" == "gaming" ]] && printf '%s' "$CACHY_WIN_GAMING_NAME" || printf '%s' "$CACHY_WIN_OFFICE_NAME")"

if ! virsh -c "$LIBVIRT_URI" domstate "$domain_name" >/dev/null 2>&1; then
  echo "$domain_name is not defined"
  exit 0
fi

if virsh -c "$LIBVIRT_URI" domstate "$domain_name" 2>/dev/null | grep -qi '^running'; then
  virsh -c "$LIBVIRT_URI" shutdown "$domain_name"
  deadline=$((SECONDS + TIMEOUT))
  while [[ "$SECONDS" -lt "$deadline" ]]; do
    if ! virsh -c "$LIBVIRT_URI" domstate "$domain_name" 2>/dev/null | grep -qi '^running'; then
      break
    fi
    sleep 2
  done
fi

if virsh -c "$LIBVIRT_URI" domstate "$domain_name" 2>/dev/null | grep -qi '^running'; then
  echo "$domain_name is still running; not releasing GPU" >&2
  exit 1
fi

if [[ "$MODE" == "gaming" ]]; then
  "$ROOT_DIR/scripts/gpu-bind.sh" unbind --env "$ENV_FILE" --confirm
fi

echo "stopped $domain_name"
