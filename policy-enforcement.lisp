; policy-enforcement.lisp — the enforceable-policy registry for wsm-os-lisp.
;
; Purpose (ADR-005, D2): a policy may be cited as a property of this system only
; when all three parts exist — an enforcement point in the mechanism layer, a
; witness where the policy actually refused something, and a gate that runs in
; CI. This file is that registry. It is deliberately small: it holds only
; policies that are already proved.
;
; Rules enforced by scripts/check-policy-enforcement.sh:
;   - every record needs id, claim, enforcement, witness, gate and status;
;   - status must be `proved`; intentions belong in docs/VISION.md, not here;
;   - `(enforcement literal <file> "<text>")`  -> <file> must contain "<text>";
;   - `(enforcement absent <glob> ...)`        -> no tracked file may match;
;   - `(witness transcript <file> "<text>")`   -> <file> must contain "<text>";
;   - `(witness runtime)`                      -> the gate itself produces it;
;   - `(gate <script>)`                        -> script exists and is wired into
;                                                 some workflow under .github/workflows;
;   - `(gate manual)` + `(gate-gap "<why>")`   -> declared gap, reported as WARN,
;                                                 never silently counted as gated.
;
; Nothing here authorises new mechanisms. A record is added only after the
; enforcement point and the witness already exist in main.

(policy-enforcement-registry
 (schema 1)
 (authority "ADR-005 D2 — enforceability rule")
 (gate-script "scripts/check-policy-enforcement.sh")

 (reserved-mechanism-codes
  ; Constants defined in the mechanism layer that no instruction path emits.
  ; Declaring them keeps the closed vocabulary honest in both directions:
  ; an unlisted unemitted constant fails the gate, and a listed constant that
  ; becomes emitted also fails, so this list cannot rot.
  (code ERR_OVERFLOW "Declared in the closed error vocabulary (value 5); no current path returns it.")
  (code GC_STATE_INVALID "Collector state constant; the collector never reports an invalid state, so nothing emits it.")
  (code MMIO_ERR_DECODE_READ "Pre-ADR-004 capability-decode refusal; the live path reports every capability failure as MMIO_ERR_PROVISIONING.")
  (code MMIO_ERR_DECODE_WRITE "Pre-ADR-004 capability-decode refusal; same collapse into MMIO_ERR_PROVISIONING as the read side.")
  (code MMIO_ERR_MAPPING_READ "Pre-ADR-004 mapping-unavailable refusal; a missing physical mapping is reported as MMIO_ERR_PROVISIONING.")
  (code MMIO_ERR_MAPPING_WRITE "Pre-ADR-004 mapping-unavailable refusal; same collapse into MMIO_ERR_PROVISIONING as the read side.")
  (code WSM_TAG_NIL "Tag constant kept for documentation; no instruction path compares against it. Wire or delete — decision pending."))

 (ungated-check-scripts
  ; check-* scripts that no workflow references. Declaring them turns an
  ; anonymous warning into a reviewed list: a new ungated script fails the
  ; gate until someone says why it is ungated, and a declared script that
  ; becomes gated fails too, so the list cannot drift.
  (script "scripts/check-mmio-abi-bounded.sh"
   "Live witness that the pure-assembly target exports the MMIO ABI symbols. Needs the pinned CML toolchain, so it was never run in this sandbox and has never been wired into a workflow."
   "Wire it after the CML toolchain step in ci.yml — but only after one green local run, not on faith.")
  (script "scripts/check-shared-oracle-corpus.sh"
   "Pre-ADR-004 script: drives removed cargo crates to build a kernel and an image. Cannot run under ADR-004. Header marked LEGACY 2026-11-26."
   "Delete, or rewrite against the current build path if the corpus check still has value.")
  (script "scripts/check-shared-oracle-provenance.sh"
   "Pre-ADR-004 script: same cargo path as check-shared-oracle-corpus.sh, plus an image-determinism comparison. Header marked LEGACY 2026-11-26."
   "Fold the still-useful determinism check into a runnable witness, then delete.")
  (script "scripts/check-uefi-image-reproducibility.sh"
   "Pre-ADR-004 script: consumes a provenance bundle produced by the cargo-based oracle scripts, so it cannot run either. Header marked LEGACY 2026-11-26."
   "Image determinism is currently unproven in CI. Rewrite against the current build path, then gate it."))

 (policies

  (policy
   (id mmio-capability-read)
   (claim "An MMIO read whose capability descriptor does not decode is refused, not attempted.")
   (enforcement literal "src/runtime.s" "MMIO_ERR_CAPABILITY_READ,      0x4D494F02")
   (witness transcript "artifacts/d4-mmio-bounds-read-fixture-qemu-serial-transcript.txt" "source=1296649986")
   (gate "scripts/check-condition-distinguishability.sh")
   (status proved))

  (policy
   (id mmio-capability-write)
   (claim "An MMIO write through a wrong capability descriptor is refused with a device condition.")
   (enforcement literal "src/runtime.s" "MMIO_ERR_CAPABILITY_WRITE,     0x4D494F05")
   (witness transcript "artifacts/d6-mmio-wrong-capability-fixture-qemu-serial-transcript.txt" "source=1296649989")
   (gate "scripts/check-mmio-mutation-fail-closed.sh")
   (status proved))

  (policy
   (id mmio-provisioning-unavailable)
   (claim "An MMIO access to a device that was never provisioned is refused with a provisioning condition.")
   (enforcement literal "src/runtime.s" "MMIO_ERR_PROVISIONING,         0x4D494F00")
   (witness transcript "artifacts/d4-mmio-bounds-read-fixture-provision-unavailable-transcript.txt" "source=1296649984")
   (gate "scripts/check-mmio-mutation-fail-closed.sh")
   (status proved))

  (policy
   (id mmio-missing-physical-mapping)
   (claim "An MMIO access attempted without a physical-memory mapping is refused before any volatile access, and produces a device/ABI condition instead of a successful read.")
   (enforcement literal "src/runtime.s" "movl $MMIO_ERR_PROVISIONING, %edx")
   (witness transcript "artifacts/d4-mmio-bounds-read-fixture-no-phys-map-transcript.txt" "source=1296649984")
   (gate "scripts/check-mmio-mutation-fail-closed.sh")
   (note "The runtime collapses five capability causes (no offset, no cap, bad BAR, not mapped, no device) into one provisioning code; the finer MMIO_ERR_MAPPING_* and MMIO_ERR_DECODE_* codes are reserved, not emitted. See docs/MMIO-PHYS-MAP-FAIL-CLOSED-EVIDENCE.md, audit 2026-11-26.")
   (status proved))

  (policy
   (id device-condition-distinguishable)
   (claim "A device or ABI refusal is distinguishable from a Lisp semantic failure by its condition kind and source.")
   (enforcement literal "src/runtime.s" "ERR_TYPE,                2")
   (witness transcript "artifacts/d9-lisp-type-failure-fixture-qemu-serial-transcript.txt" "kind=TYPE")
   (gate "scripts/check-condition-distinguishability.sh")
   (status proved))

  (policy
   (id serial-transport-failure-distinct)
   (claim "A serial transport that never becomes ready exits with a distinct code instead of hanging or reusing another failure.")
   (enforcement literal "src/entry.s" "movl $0x13, %eax")
   (witness runtime)
   (gate "scripts/rebuild-and-run-serial-timeout-qemu.sh")
   (status proved))

  (policy
   (id zero-rust-boundary)
   (claim "No Rust exists in the production target, bootstrap or runtime.")
   (enforcement absent "*.rs" "Cargo.toml" "Cargo.lock" "rust-toolchain.toml" "crates")
   (witness runtime)
   (gate "scripts/check-no-rust.sh")
   (status proved))

  (policy
   (id no-data-to-command-interpolation)
   (claim "Repository scripts never turn data into a shell command string.")
   (enforcement literal "scripts/check-shell-safety.sh" "eval is forbidden in repository scripts")
   (witness runtime)
   (gate "scripts/check-shell-safety.sh")
   (status proved))))
