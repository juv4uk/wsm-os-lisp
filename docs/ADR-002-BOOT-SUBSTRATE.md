# ADR-002: Boot Substrate Selection

**Status:** REVISED
**Date:** 2026-08-29

## Context
Task M3A required choosing a maintained x86_64 boot substrate for `wsm-os`. The initial decision falsely claimed migration to v0.11 UEFI while the codebase actually implemented v0.9.35 legacy BIOS with `bootimage`. We must resolve this discrepancy and document the actual executable evidence.

## Decision
We select the **`bootloader` crate at `v0.9.35` and the legacy `bootimage` tool**
(by Philipp Oppermann) as the primary legacy BIOS boot substrate for Phase 1.

## Rationale & Toolchain Alignment

1. **Licensing:**
   - `bootloader` is licensed under **MIT / Apache-2.0**.
   - This complies strictly with the ecosystem `LICENSE-MATRIX.md` (MIT repos only).

2. **Rust Target Requirements:**
   - The OS kernel compiles to a custom JSON target (`x86_64-wsm-os.json`) as required by v0.9 legacy tooling, rather than the pure `x86_64-unknown-none` target used in v0.11.

3. **Deterministic Serial Test Path:**
   - The build system relies on `bootimage` (which bundles the legacy BIOS bootloader).
   - QEMU invocation, `isa-debug-exit`, serial capture and timeout remain explicit `wsm-os` test-harness responsibilities.
   - We implement our own minimal UART serial writer (COM1 at `0x3F8`) using `x86_64` crate instructions to emit canonical parity format (`WSM-OS RESULT schema=1 ...`).

4. **Comparison with v0.11 UEFI:**
   - Transitioning to v0.11 UEFI would require writing a custom Rust build script to invoke `bootloader::UefiBoot` and fundamentally changing the kernel entry point to use `bootloader_api`. While this is the modern standard, our current CI and codebase successfully prove execution using the legacy v0.9 BIOS path. Upgrading to v0.11 is deferred to a future task.

## Consequences
- The kernel depends on `bootloader = "0.9.35"`.
- We require nightly Rust with `llvm-tools-preview` and `bootimage` installed via `cargo install`.
- The generated CML `fixture.s` object will link directly into this kernel without OS modifications.

## Primary implementation evidence
- `crates/wsm-os-kernel/Cargo.toml` specifies `bootloader = "0.9.35"`.
- GitHub Actions CI uses `cargo bootimage` to build the legacy BIOS image.
