#!/usr/bin/env bash
set -euo pipefail

# #77 clean-restart witness:
# boot A writes+flushes the admitted 512-byte payload;
# boot B is a distinct QEMU boot using the exact same raw disk path/image and
# must recover the same bytes through a fresh runtime/virtqueue.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d /tmp/wsm-m2-restart.XXXXXX)"
trap 'rm -rf "$work"' EXIT
out="$ROOT_DIR/target/m2-clean-restart"
mkdir -p "$out"

as --64 "$ROOT_DIR/artifacts/m2-persist-boot-a-probe.s" -o "$work/boot-a.o"
as --64 "$ROOT_DIR/artifacts/m2-persist-boot-b-probe.s" -o "$work/boot-b.o"

bash "$ROOT_DIR/scripts/build-uefi-image.sh" "$work/boot-a.o" "$work/boot-a.img" >/dev/null
bash "$ROOT_DIR/scripts/build-uefi-image.sh" "$work/boot-b.o" "$work/boot-b.img" >/dev/null

cat >"$work/expected.txt" <<'EOF'
WSM-OS BOOT schema=1 arch=x86_64 status=ok
WSM-OS RESULT schema=1 value=1 status=ok
EOF

disk="$work/persist.raw"
truncate -s 1M "$disk"
disk_path_before="$disk"

initial_sha="$(sha256sum "$disk" | awk '{print $1}')"
initial_sector_sha="$(dd if="$disk" bs=512 count=1 status=none | sha256sum | awk '{print $1}')"
boot_a_sha="$(sha256sum "$work/boot-a.img" | awk '{print $1}')"
boot_b_sha="$(sha256sum "$work/boot-b.img" | awk '{print $1}')"
machine_profile_sha="$(sha256sum "$ROOT_DIR/contracts/qemu-m0-machine-profile.lisp" | awk '{print $1}')"

expected_payload_sha="$(
python3 - <<'PY'
import hashlib
payload = b"SENSM2V1" * 64
assert len(payload) == 512
print(hashlib.sha256(payload).hexdigest())
PY
)"

boot_a="$(
  WSM_QEMU_TRANSCRIPT="$work/expected.txt"   WSM_QEMU_DATA_DISK="$disk"   WSM_QEMU_VIRTIO_ADDR=5   WSM_QEMU_VIRTIO_DISABLE_LEGACY=1   bash "$ROOT_DIR/scripts/run-qemu-uefi.sh" "$work/boot-a.img"
)"
printf '%s\n' "$boot_a" >"$out/boot-a-transcript.txt"

after_a_sha="$(sha256sum "$disk" | awk '{print $1}')"
after_a_sector_sha="$(dd if="$disk" bs=512 count=1 status=none | sha256sum | awk '{print $1}')"
if [[ "$after_a_sector_sha" != "$expected_payload_sha" ]]; then
  echo "boot A did not persist expected sector: expected=$expected_payload_sha actual=$after_a_sector_sha" >&2
  exit 1
fi

# Boot B must use the exact same host path and image bytes. The run-qemu helper
# creates fresh OVMF runtime state per invocation, so this is a distinct clean
# guest boot over the same persistent data medium.
[[ "$disk" == "$disk_path_before" ]]

boot_b="$(
  WSM_QEMU_TRANSCRIPT="$work/expected.txt"   WSM_QEMU_DATA_DISK="$disk"   WSM_QEMU_VIRTIO_ADDR=5   WSM_QEMU_VIRTIO_DISABLE_LEGACY=1   bash "$ROOT_DIR/scripts/run-qemu-uefi.sh" "$work/boot-b.img"
)"
printf '%s\n' "$boot_b" >"$out/boot-b-transcript.txt"

after_b_sha="$(sha256sum "$disk" | awk '{print $1}')"
after_b_sector_sha="$(dd if="$disk" bs=512 count=1 status=none | sha256sum | awk '{print $1}')"

if [[ "$after_b_sector_sha" != "$expected_payload_sha" ]]; then
  echo "boot B did not recover expected sector: expected=$expected_payload_sha actual=$after_b_sector_sha" >&2
  exit 1
fi
if [[ "$after_b_sha" != "$after_a_sha" ]]; then
  echo "boot B unexpectedly mutated the persistent image" >&2
  exit 1
fi

runtime_sha="$(sha256sum "$ROOT_DIR/src/runtime.s" | awk '{print $1}')"
cat >"$out/witness.json" <<EOF
{
  "schema": "wsm-os-m2-clean-restart/v1",
  "issue": 77,
  "status": "PASS",
  "claim": "same-disk-clean-restart-persistence",
  "power_loss_durability_claimed": false,
  "data_medium": {
    "kind": "separate-disposable-qemu-raw-disk",
    "size_bytes": 1048576,
    "same_host_path_reused_for_both_boots": true,
    "sector": 0,
    "sector_bytes": 512
  },
  "boot_a": {
    "operation": "fresh-IN-zero -> OUT-pattern -> FLUSH -> clean-exit",
    "boot_image_sha256": "$boot_a_sha",
    "data_image_sha256_before": "$initial_sha",
    "sector0_sha256_before": "$initial_sector_sha",
    "data_image_sha256_after": "$after_a_sha",
    "sector0_sha256_after": "$after_a_sector_sha"
  },
  "boot_b": {
    "operation": "fresh-runtime -> IN-sector0 -> exact-pattern-verify -> clean-exit",
    "boot_image_sha256": "$boot_b_sha",
    "data_image_sha256_after": "$after_b_sha",
    "sector0_sha256_after": "$after_b_sector_sha",
    "mutated_persistent_image": false
  },
  "persisted_payload_sha256": "$expected_payload_sha",
  "machine_profile_sha256": "$machine_profile_sha",
  "runtime_source_sha256": "$runtime_sha",
  "filesystem_required": false,
  "runtime_pointer_persisted": false
}
EOF

echo "M2-CLEAN-RESTART: PASS"
echo "bootA=write+flush bootB=fresh-read same-disk=true sector-sha=$after_b_sector_sha"
