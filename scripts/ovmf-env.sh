#!/usr/bin/env bash
# Sourceable helper to resolve OVMF firmware for UEFI runs.
# Resolution order:
#   1. explicit OVMF_CODE / OVMF_VARS from environment
#   2. Guix discovery (ovmf-x86-64 package)
#   3. fail with clear diagnostic

if [[ -z "${OVMF_CODE:-}" || -z "${OVMF_VARS:-}" ]]; then
  if command -v guix >/dev/null 2>&1; then
    ovmf_pkg_dir=$(guix build ovmf-x86-64 2>/dev/null || true)
    if [[ -n "$ovmf_pkg_dir" && -d "$ovmf_pkg_dir/share/firmware" ]]; then
      ovmf_dir="$ovmf_pkg_dir/share/firmware"
      : "${OVMF_CODE:=$ovmf_dir/ovmf_code_x64.bin}"
      : "${OVMF_VARS:=$ovmf_dir/ovmf_vars_x64.bin}"
    fi
  fi
fi

if [[ -z "${OVMF_CODE:-}" || -z "${OVMF_VARS:-}" ]]; then
  for candidate in /gnu/store/*-ovmf-x86-64-*/share/firmware; do
    if [[ -f "$candidate/ovmf_code_x64.bin" && -f "$candidate/ovmf_vars_x64.bin" ]]; then
      : "${OVMF_CODE:=$candidate/ovmf_code_x64.bin}"
      : "${OVMF_VARS:=$candidate/ovmf_vars_x64.bin}"
      break
    fi
  done
fi

if [[ -z "${OVMF_CODE:-}" || -z "${OVMF_VARS:-}" ]]; then
  if [[ -f "/usr/share/OVMF/OVMF_CODE.fd" && -f "/usr/share/OVMF/OVMF_VARS.fd" ]]; then
    : "${OVMF_CODE:=/usr/share/OVMF/OVMF_CODE.fd}"
    : "${OVMF_VARS:=/usr/share/OVMF/OVMF_VARS.fd}"
  elif [[ -f "/usr/share/OVMF/OVMF_CODE_4M.fd" && -f "/usr/share/OVMF/OVMF_VARS_4M.fd" ]]; then
    : "${OVMF_CODE:=/usr/share/OVMF/OVMF_CODE_4M.fd}"
    : "${OVMF_VARS:=/usr/share/OVMF/OVMF_VARS_4M.fd}"
  elif [[ -f "/usr/share/edk2/ovmf/OVMF_CODE.fd" && -f "/usr/share/edk2/ovmf/OVMF_VARS.fd" ]]; then
    : "${OVMF_CODE:=/usr/share/edk2/ovmf/OVMF_CODE.fd}"
    : "${OVMF_VARS:=/usr/share/edk2/ovmf/OVMF_VARS.fd}"
  fi
fi

if [[ -z "${OVMF_CODE:-}" || -z "${OVMF_VARS:-}" ]]; then
  echo "ERROR: OVMF firmware not specified and Guix ovmf-x86-64 package not found." >&2
  echo "Please set OVMF_CODE=/path/to/code.bin and OVMF_VARS=/path/to/vars.bin explicitly." >&2
  exit 2
fi

if [[ ! -s "$OVMF_CODE" ]]; then
  echo "ERROR: OVMF_CODE file '$OVMF_CODE' does not exist or is empty." >&2
  exit 2
fi

if [[ ! -s "$OVMF_VARS" ]]; then
  echo "ERROR: OVMF_VARS file '$OVMF_VARS' does not exist or is empty." >&2
  exit 2
fi

export OVMF_CODE
export OVMF_VARS
