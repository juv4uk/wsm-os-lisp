#!/usr/bin/env python3
"""Canonicalize only GPT identity metadata in a disk image.

The bootloader/gpt stack creates fresh UUIDv4 values for the GPT disk and
partition identities on each image build. This tool removes exactly that
allowed variance, then recomputes the dependent GPT CRC32 fields. All other
bytes remain part of the reproducibility witness.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import struct
import sys
import zlib
from pathlib import Path

SECTOR_SIZE = 512
GPT_SIGNATURE = b"EFI PART"
ZERO_GUID = b"\x00" * 16


class CanonicalizationError(RuntimeError):
    pass


def sha256_bytes(data: bytes | bytearray) -> str:
    return hashlib.sha256(data).hexdigest()


def u32(data: bytes | bytearray, offset: int) -> int:
    return struct.unpack_from("<I", data, offset)[0]


def u64(data: bytes | bytearray, offset: int) -> int:
    return struct.unpack_from("<Q", data, offset)[0]


def put_u32(data: bytearray, offset: int, value: int) -> None:
    struct.pack_into("<I", data, offset, value)


def parse_header(data: bytes | bytearray, lba: int) -> dict[str, int | bytes]:
    offset = lba * SECTOR_SIZE
    if offset + SECTOR_SIZE > len(data):
        raise CanonicalizationError(f"GPT header LBA {lba} is outside image")
    if bytes(data[offset : offset + 8]) != GPT_SIGNATURE:
        raise CanonicalizationError(f"missing GPT signature at LBA {lba}")

    header_size = u32(data, offset + 12)
    if not 92 <= header_size <= SECTOR_SIZE:
        raise CanonicalizationError(f"invalid GPT header size {header_size} at LBA {lba}")

    current_lba = u64(data, offset + 24)
    backup_lba = u64(data, offset + 32)
    if current_lba != lba:
        raise CanonicalizationError(
            f"GPT current_lba={current_lba} does not match header location {lba}"
        )

    entry_lba = u64(data, offset + 72)
    entry_count = u32(data, offset + 80)
    entry_size = u32(data, offset + 84)
    if entry_count == 0 or entry_size < 128 or entry_size % 8 != 0:
        raise CanonicalizationError(
            f"invalid GPT partition table shape count={entry_count} size={entry_size}"
        )
    table_offset = entry_lba * SECTOR_SIZE
    table_length = entry_count * entry_size
    if table_offset + table_length > len(data):
        raise CanonicalizationError("GPT partition table extends beyond image")

    return {
        "offset": offset,
        "header_size": header_size,
        "current_lba": current_lba,
        "backup_lba": backup_lba,
        "entry_lba": entry_lba,
        "entry_count": entry_count,
        "entry_size": entry_size,
        "table_offset": table_offset,
        "table_length": table_length,
        "disk_guid": bytes(data[offset + 56 : offset + 72]),
        "first_usable_lba": u64(data, offset + 40),
        "last_usable_lba": u64(data, offset + 48),
    }


def verify_gpt_pair(data: bytes | bytearray, primary: dict, backup: dict) -> None:
    if primary["backup_lba"] != backup["current_lba"]:
        raise CanonicalizationError("primary GPT does not point to backup GPT")
    if backup["backup_lba"] != primary["current_lba"]:
        raise CanonicalizationError("backup GPT does not point back to primary GPT")
    for key in ("entry_count", "entry_size", "first_usable_lba", "last_usable_lba"):
        if primary[key] != backup[key]:
            raise CanonicalizationError(f"primary/backup GPT disagree on {key}")
    if primary["disk_guid"] != backup["disk_guid"]:
        raise CanonicalizationError("primary/backup GPT disk GUIDs differ within one image")

    p0 = int(primary["table_offset"])
    b0 = int(backup["table_offset"])
    length = int(primary["table_length"])
    if bytes(data[p0 : p0 + length]) != bytes(data[b0 : b0 + length]):
        raise CanonicalizationError("primary/backup GPT partition arrays differ within one image")


def normalize_table(data: bytearray, header: dict) -> tuple[int, int]:
    table_offset = int(header["table_offset"])
    entry_count = int(header["entry_count"])
    entry_size = int(header["entry_size"])
    used = 0
    changed_guid_bytes = 0

    for index in range(entry_count):
        entry = table_offset + index * entry_size
        type_guid = bytes(data[entry : entry + 16])
        if type_guid != ZERO_GUID:
            used += 1
        unique_start = entry + 16
        unique_end = unique_start + 16
        before = bytes(data[unique_start:unique_end])
        changed_guid_bytes += sum(a != b for a, b in zip(before, ZERO_GUID))
        data[unique_start:unique_end] = ZERO_GUID

    table_length = int(header["table_length"])
    crc = zlib.crc32(data[table_offset : table_offset + table_length]) & 0xFFFF_FFFF
    return used, crc


def normalize_header(data: bytearray, header: dict, table_crc: int) -> int:
    offset = int(header["offset"])
    header_size = int(header["header_size"])
    data[offset + 56 : offset + 72] = ZERO_GUID
    put_u32(data, offset + 88, table_crc)
    put_u32(data, offset + 16, 0)
    header_crc = zlib.crc32(data[offset : offset + header_size]) & 0xFFFF_FFFF
    put_u32(data, offset + 16, header_crc)
    return header_crc


def canonicalize(raw: bytes) -> tuple[bytes, dict]:
    data = bytearray(raw)
    primary = parse_header(data, 1)
    backup = parse_header(data, int(primary["backup_lba"]))
    verify_gpt_pair(data, primary, backup)

    raw_guid = bytes(primary["disk_guid"]).hex()
    p_used, p_crc = normalize_table(data, primary)
    b_used, b_crc = normalize_table(data, backup)
    if p_used != b_used or p_crc != b_crc:
        raise CanonicalizationError("canonical primary/backup partition arrays diverged")

    p_header_crc = normalize_header(data, primary, p_crc)
    b_header_crc = normalize_header(data, backup, b_crc)

    # Reparse the canonical image so structural errors in our own rewrite fail closed.
    p2 = parse_header(data, 1)
    b2 = parse_header(data, int(p2["backup_lba"]))
    verify_gpt_pair(data, p2, b2)
    if p2["disk_guid"] != ZERO_GUID or b2["disk_guid"] != ZERO_GUID:
        raise CanonicalizationError("canonical GPT disk GUID was not cleared")

    first_partition_lba = None
    table_offset = int(p2["table_offset"])
    entry_size = int(p2["entry_size"])
    for index in range(int(p2["entry_count"])):
        entry = table_offset + index * entry_size
        if bytes(data[entry : entry + 16]) != ZERO_GUID:
            first_partition_lba = u64(data, entry + 32)
            break
    if first_partition_lba is None:
        raise CanonicalizationError("GPT image has no used partition")

    report = {
        "schema": "wsm-os-lisp-gpt-canonicalization",
        "schema_version": 1,
        "sector_size": SECTOR_SIZE,
        "raw_sha256": sha256_bytes(raw),
        "canonical_sha256": sha256_bytes(data),
        "raw_disk_guid_hex": raw_guid,
        "used_partition_count": p_used,
        "first_partition_lba": first_partition_lba,
        "primary_header_lba": 1,
        "backup_header_lba": int(primary["backup_lba"]),
        "primary_partition_array_lba": int(primary["entry_lba"]),
        "backup_partition_array_lba": int(backup["entry_lba"]),
        "partition_entry_count": int(primary["entry_count"]),
        "partition_entry_size": int(primary["entry_size"]),
        "canonical_partition_array_crc32": f"{p_crc:08x}",
        "canonical_primary_header_crc32": f"{p_header_crc:08x}",
        "canonical_backup_header_crc32": f"{b_header_crc:08x}",
        "allowed_variance": [
            "gpt.disk_guid",
            "gpt.partition_unique_guid",
            "gpt.partition_array_crc32",
            "gpt.header_crc32",
        ],
    }
    return bytes(data), report


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()

    try:
        raw = args.input.read_bytes()
        canonical, report = canonicalize(raw)
    except (OSError, CanonicalizationError) as exc:
        print(f"GPT-CANONICALIZATION-FAIL: {exc}", file=sys.stderr)
        return 1

    args.output.write_bytes(canonical)
    if args.report is not None:
        args.report.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(
        "GPT-CANONICALIZATION-PASS: "
        f"raw={report['raw_sha256']} canonical={report['canonical_sha256']} "
        f"partitions={report['used_partition_count']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
