#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <raw-disk-path>" >&2
  exit 2
fi

disk=$1
case "$disk" in
  /tmp/*) ;;
  *) echo "refusing non-disposable path (use /tmp)" >&2; exit 2 ;;
esac

if [[ -e "$disk" ]]; then
  echo "refusing to overwrite existing disk: $disk" >&2
  exit 2
fi

# Q6b starts with one 512-byte logical block and one 4 KiB sector.
truncate -s 4096 "$disk"
chmod 600 "$disk"
echo "created disposable QEMU data disk: path=$disk bytes=4096 block-size=512"
