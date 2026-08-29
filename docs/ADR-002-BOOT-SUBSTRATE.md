# ADR-002: Boot Substrate Selection

**Status:** ACCEPTED
**Date:** 2026-08-29

## Context
Task M3A requires choosing the smallest maintained x86_64 UEFI/QEMU boot substrate for `wsm-os` that works on the target Gigabyte H170-Gaming 3 (UEFI) and WSL/QEMU build environments. We must verify exact license/NOTICE obligations, Rust target/tool requirements, deterministic serial test path, and test-only QEMU exit.

## Decision
We select the **`bootloader` crate** (v0.11 or latest stable, by Philipp Oppermann) as the primary boot substrate for Phase 1. 

## Rationale & Toolchain Alignment

1. **Licensing:**
   - `bootloader` is licensed under **MIT / Apache-2.0**.
   - This complies strictly with the ecosystem `LICENSE-MATRIX.md` (MIT repos only, no GPL or copyleft leakage into the bootloader layer).

2. **Rust Target Requirements:**
   - The OS kernel will compile to `x86_64-unknown-none`.
   - No custom target JSON files are needed; we rely on the standard Rust `x86_64-unknown-none` target which guarantees deterministic GNU assembly and calling conventions, matching our M1 CML emitter.

3. **Deterministic Serial Test Path:**
   - `bootloader` is natively integrated with QEMU via its `bootimage` or `cargo build` integration.
   - It seamlessly maps the `isa-debug-exit` QEMU device, which allows us to exit QEMU deterministically with a success/failure code for CI testing without full hardware shutdown routines.
   - We will implement our own minimal UART serial writer (COM1 at `0x3F8`) using `x86_64` crate instructions (`outb`/`inb`) to emit our canonical parity format (`WSM-OS RESULT schema=1 ...`).

4. **Comparison with Alternatives:**
   - `uefi-rs` (MPL-2.0): Requires custom `x86_64-unknown-uefi` target, requires manual boot-services exit, and the MPL-2.0 license is slightly more complex than MIT, although permissive.
   - `Limine` (BSD-2-Clause): Excellent protocol, but requires fetching external C-compiled binaries to embed the bootloader, violating the goal of a minimal, pure Rust `no_std` toolchain.

## Consequences
- We add `bootloader` and `x86_64` to `crates/wsm-os-runtime/Cargo.toml` (or a dedicated boot crate).
- We require `rustup target add x86_64-unknown-none` in CI and local setups (already satisfied by M1/M2).
- The generated CML `fixture.s` object will link directly into this kernel without OS modifications.
