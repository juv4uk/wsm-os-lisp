#!/usr/bin/env bash
set -euo pipefail

# #95 framed persistence evidence.
# Boot A writes+flushes one canonical envelope. Boot B validates it from a
# separate boot. Independent mutated copies must fail closed and remain
# unmodified by the read-only verifier.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d /tmp/wsm-m2-envelope.XXXXXX)"
trap 'rm -rf "$work"' EXIT
out="$ROOT_DIR/target/m2-envelope"
mkdir -p "$out"

as --64 "$ROOT_DIR/artifacts/m2-envelope-boot-a-probe.s" -o "$work/boot-a.o"
as --64 "$ROOT_DIR/artifacts/m2-envelope-boot-b-probe.s" -o "$work/boot-b.o"
bash "$ROOT_DIR/scripts/build-uefi-image.sh" "$work/boot-a.o" "$work/boot-a.img" >/dev/null
bash "$ROOT_DIR/scripts/build-uefi-image.sh" "$work/boot-b.o" "$work/boot-b.img" >/dev/null

cat >"$work/pass.expected" <<'EOF'
WSM-OS BOOT schema=1 arch=x86_64 status=ok
WSM-OS RESULT schema=1 value=1 status=ok
EOF
cat >"$work/fail.expected" <<'EOF'
WSM-OS BOOT schema=1 arch=x86_64 status=ok
WSM-OS RESULT schema=1 value=0 status=ok
EOF

disk="$work/envelope.raw"
truncate -s 1M "$disk"

boot_a="$(
  WSM_QEMU_TRANSCRIPT="$work/pass.expected"   WSM_QEMU_DATA_DISK="$disk"   WSM_QEMU_VIRTIO_ADDR=5   WSM_QEMU_VIRTIO_DISABLE_LEGACY=1   bash "$ROOT_DIR/scripts/run-qemu-uefi.sh" "$work/boot-a.img"
)"
printf '%s\n' "$boot_a" >"$out/boot-a-transcript.txt"

cp "$disk" "$work/valid.raw"
valid_sha="$(sha256sum "$work/valid.raw" | awk '{print $1}')"
valid_sector_sha="$(dd if="$work/valid.raw" bs=512 count=1 status=none | sha256sum | awk '{print $1}')"

# Independent host parser: prove the on-disk bytes match the canonical frame.
frame_meta="$(
python3 - "$work/valid.raw" <<'PY'
import hashlib
import json
import struct
import sys

path=sys.argv[1]
with open(path,"rb") as f:
    sector=f.read(512)
assert len(sector)==512
magic=sector[:8]
version,header_len,payload_len,checksum=struct.unpack_from("<IIII",sector,8)
reserved=struct.unpack_from("<Q",sector,24)[0]
payload=sector[32:32+payload_len]

h=0x811C9DC5
for byte in payload:
    h ^= byte
    h=(h*0x01000193)&0xffffffff

assert magic == b"WSMENV01"
assert version == 1
assert header_len == 32
assert payload_len == 16
assert reserved == 0
assert payload == b"SENS-Q6B-PAYLOAD"
assert h == checksum == 0x65744427

print(json.dumps({
  "magic": magic.decode("ascii"),
  "version": version,
  "header_len": header_len,
  "payload_len": payload_len,
  "checksum_algorithm": "fnv1a32",
  "checksum_hex": f"{checksum:08x}",
  "payload_ascii": payload.decode("ascii"),
  "payload_sha256": hashlib.sha256(payload).hexdigest(),
  "sector_sha256": hashlib.sha256(sector).hexdigest(),
}, sort_keys=True))
PY
)"
printf '%s\n' "$frame_meta" >"$out/frame.json"

before_b_sha="$(sha256sum "$disk" | awk '{print $1}')"
boot_b="$(
  WSM_QEMU_TRANSCRIPT="$work/pass.expected"   WSM_QEMU_DATA_DISK="$disk"   WSM_QEMU_VIRTIO_ADDR=5   WSM_QEMU_VIRTIO_DISABLE_LEGACY=1   bash "$ROOT_DIR/scripts/run-qemu-uefi.sh" "$work/boot-b.img"
)"
printf '%s\n' "$boot_b" >"$out/boot-b-transcript.txt"
after_b_sha="$(sha256sum "$disk" | awk '{print $1}')"
[[ "$before_b_sha" == "$after_b_sha" ]]

mutate() {
  local src=$1
  local dst=$2
  local kind=$3
  cp "$src" "$dst"
  python3 - "$dst" "$kind" <<'PY'
import struct,sys
path,kind=sys.argv[1:]
with open(path,"r+b") as f:
    sector=bytearray(f.read(512))
    if kind=="magic":
        sector[0] ^= 0x01
    elif kind=="version":
        struct.pack_into("<I",sector,8,2)
    elif kind=="header-len":
        struct.pack_into("<I",sector,12,31)
    elif kind=="truncated-length":
        struct.pack_into("<I",sector,16,481)
    elif kind=="checksum":
        sector[20] ^= 0x01
    elif kind=="payload":
        sector[32] ^= 0x01
    else:
        raise SystemExit(kind)
    f.seek(0)
    f.write(sector)
PY
}

run_negative() {
  local kind=$1
  local bad="$work/bad-$kind.raw"
  mutate "$work/valid.raw" "$bad" "$kind"
  local before after observed
  before="$(sha256sum "$bad" | awk '{print $1}')"
  observed="$(
    WSM_QEMU_TRANSCRIPT="$work/fail.expected"     WSM_QEMU_DATA_DISK="$bad"     WSM_QEMU_VIRTIO_ADDR=5     WSM_QEMU_VIRTIO_DISABLE_LEGACY=1     bash "$ROOT_DIR/scripts/run-qemu-uefi.sh" "$work/boot-b.img"
  )"
  printf '%s\n' "$observed" >"$out/$kind-transcript.txt"
  after="$(sha256sum "$bad" | awk '{print $1}')"
  if [[ "$before" != "$after" ]]; then
    echo "read-only negative verifier mutated $kind image" >&2
    exit 1
  fi
}

for kind in magic version header-len truncated-length checksum payload; do
  run_negative "$kind"
done

boot_a_sha="$(sha256sum "$work/boot-a.img" | awk '{print $1}')"
boot_b_sha="$(sha256sum "$work/boot-b.img" | awk '{print $1}')"
runtime_sha="$(sha256sum "$ROOT_DIR/src/runtime.s" | awk '{print $1}')"
profile_sha="$(sha256sum "$ROOT_DIR/contracts/qemu-m0-machine-profile.lisp" | awk '{print $1}')"
payload_sha="$(python3 - <<'PY'
import hashlib
print(hashlib.sha256(b"SENS-Q6B-PAYLOAD").hexdigest())
PY
)"

cat >"$out/witness.json" <<EOF
{
  "schema": "wsm-os-m2-envelope/v1",
  "issue": 95,
  "status": "PASS",
  "claim": "canonical-framed-sector-survives-clean-restart-and-fails-closed-on-corruption",
  "frame": {
    "magic": "WSMENV01",
    "version": 1,
    "header_len": 32,
    "payload_len": 16,
    "checksum": "FNV-1a32",
    "checksum_expected_hex": "65744427",
    "payload_sha256": "$payload_sha",
    "valid_sector_sha256": "$valid_sector_sha"
  },
  "positive": {
    "boot_a_write_flush": "PASS",
    "boot_b_read_validate": "PASS",
    "boot_b_mutated_image": false,
    "valid_data_image_sha256": "$valid_sha"
  },
  "negative_controls": {
    "wrong_magic": "PASS",
    "wrong_version": "PASS",
    "wrong_header_length": "PASS",
    "declared_payload_truncation": "PASS",
    "checksum_mismatch": "PASS",
    "payload_corruption": "PASS"
  },
  "boot_a_image_sha256": "$boot_a_sha",
  "boot_b_image_sha256": "$boot_b_sha",
  "machine_profile_sha256": "$profile_sha",
  "runtime_source_sha256": "$runtime_sha",
  "filesystem_required": false,
  "semantic_authority_assigned_to_payload": false,
  "power_loss_durability_claimed": false
}
EOF

echo "M2-ENVELOPE: PASS"
echo "positive=two-boot framed sector negatives=magic,version,header,len,checksum,payload"
