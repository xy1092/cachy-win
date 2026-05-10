#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${CACHY_WIN_ENV:-$ROOT_DIR/env.local}"

usage() {
  cat <<'USAGE'
Usage: scripts/render-domain.sh gaming|office [--env FILE]

Renders a libvirt XML profile into build/.
USAGE
}

mode="${1:-}"
[[ $# -gt 0 ]] && shift || true
while [[ $# -gt 0 ]]; do
  case "$1" in
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

if [[ "$mode" != "gaming" && "$mode" != "office" ]]; then
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

pci_parts() {
  local pci="$1"
  local prefix="$2"
  local domain bus slot function
  domain="${pci%%:*}"
  bus="${pci#*:}"
  bus="${bus%%:*}"
  slot="${pci##*:}"
  function="${slot##*.}"
  slot="${slot%%.*}"
  printf -v "${prefix}_DOMAIN" '0x%s' "$domain"
  printf -v "${prefix}_BUS" '0x%s' "$bus"
  printf -v "${prefix}_SLOT" '0x%s' "$slot"
  printf -v "${prefix}_FUNCTION" '0x%s' "$function"
  export "${prefix}_DOMAIN" "${prefix}_BUS" "${prefix}_SLOT" "${prefix}_FUNCTION"
}

disk_xml() {
  local target_dev="$1"
  case "${DISK_BACKEND:-qcow2}" in
    qcow2)
      cat <<EOF
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2' discard='unmap'/>
      <source file='${WINDOWS_DISK_IMAGE}'/>
      <target dev='${target_dev}' bus='virtio'/>
    </disk>
EOF
      ;;
    physical)
      if [[ -z "${PHYSICAL_WINDOWS_DISK:-}" ]]; then
        echo "PHYSICAL_WINDOWS_DISK is empty" >&2
        exit 1
      fi
      cat <<EOF
    <disk type='block' device='disk'>
      <driver name='qemu' type='raw' cache='none' io='native' discard='unmap'/>
      <source dev='${PHYSICAL_WINDOWS_DISK}'/>
      <target dev='${target_dev}' bus='virtio'/>
    </disk>
EOF
      ;;
    *)
      echo "invalid DISK_BACKEND: ${DISK_BACKEND:-unset}" >&2
      exit 1
      ;;
  esac
}

smbios_xml() {
  if [[ -n "${SMBIOS_MANUFACTURER:-}${SMBIOS_PRODUCT:-}${SMBIOS_SERIAL:-}" ]]; then
    cat <<EOF
  <sysinfo type='smbios'>
    <system>
      <entry name='manufacturer'>${SMBIOS_MANUFACTURER:-}</entry>
      <entry name='product'>${SMBIOS_PRODUCT:-}</entry>
      <entry name='serial'>${SMBIOS_SERIAL:-}</entry>
    </system>
  </sysinfo>
EOF
  fi
}

smbios_mode_xml() {
  if [[ -n "${SMBIOS_MANUFACTURER:-}${SMBIOS_PRODUCT:-}${SMBIOS_SERIAL:-}" ]]; then
    printf "    <smbios mode='sysinfo'/>"
  else
    printf "    <smbios mode='emulate'/>"
  fi
}

mkdir -p "$ROOT_DIR/build"

if [[ "$mode" == "gaming" ]]; then
  export VM_NAME="$CACHY_WIN_GAMING_NAME"
  export VM_UUID="$GAMING_VM_UUID"
  export MEMORY_MIB="$GAMING_MEMORY_MIB"
  export VCPUS="$GAMING_VCPUS"
  export CPUSET="$GAMING_CPUSET"
  export CPU_SOCKETS="$GAMING_CPU_SOCKETS"
  export CPU_CORES="$GAMING_CPU_CORES"
  export CPU_THREADS="$GAMING_CPU_THREADS"
  export OVMF_VARS="$OVMF_VARS_GAMING"
  export SYSTEM_DISK_XML="$(disk_xml vda)"
  export SMBIOS_XML="$(smbios_xml)"
  export SMBIOS_MODE_XML="$(smbios_mode_xml)"
  if [[ "${GAMING_USE_HUGEPAGES:-0}" == "1" ]]; then
    export MEMORY_BACKING_XML="  <memoryBacking>
    <hugepages/>
  </memoryBacking>"
  else
    export MEMORY_BACKING_XML=""
  fi
  pci_parts "$GAMING_GPU_VIDEO_PCI" GPU_VIDEO
  if [[ -n "${GAMING_GPU_AUDIO_PCI:-}" ]]; then
    pci_parts "$GAMING_GPU_AUDIO_PCI" GPU_AUDIO
    export GPU_AUDIO_XML="    <hostdev mode='subsystem' type='pci' managed='yes'>
      <driver name='vfio'/>
      <source>
        <address domain='${GPU_AUDIO_DOMAIN}' bus='${GPU_AUDIO_BUS}' slot='${GPU_AUDIO_SLOT}' function='${GPU_AUDIO_FUNCTION}'/>
      </source>
    </hostdev>"
  else
    export GPU_AUDIO_XML=""
  fi
  template="$ROOT_DIR/xml/gaming.xml.in"
  output="$ROOT_DIR/build/${CACHY_WIN_GAMING_NAME}.xml"
else
  export VM_NAME="$CACHY_WIN_OFFICE_NAME"
  export VM_UUID="$OFFICE_VM_UUID"
  export MEMORY_MIB="$OFFICE_MEMORY_MIB"
  export VCPUS="$OFFICE_VCPUS"
  export CPUSET="$OFFICE_CPUSET"
  export CPU_SOCKETS="$OFFICE_CPU_SOCKETS"
  export CPU_CORES="$OFFICE_CPU_CORES"
  export CPU_THREADS="$OFFICE_CPU_THREADS"
  export OVMF_VARS="$OVMF_VARS_OFFICE"
  export SYSTEM_DISK_XML="$(disk_xml vda)"
  export SMBIOS_XML="$(smbios_xml)"
  export SMBIOS_MODE_XML="$(smbios_mode_xml)"
  template="$ROOT_DIR/xml/office.xml.in"
  output="$ROOT_DIR/build/${CACHY_WIN_OFFICE_NAME}.xml"
fi

envsubst < "$template" > "$output"
printf '%s\n' "$output"
