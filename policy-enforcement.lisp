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
   (id mmio-mapping-fail-closed)
   (claim "An MMIO write without a physical-memory mapping is refused instead of assuming an identity map.")
   (enforcement literal "src/runtime.s" "MMIO_ERR_MAPPING_WRITE,        0x4D494F08")
   (witness transcript "artifacts/d2-virtio-blk-status-fixture-fail-closed-phys-map-transcript.txt" "source=1296649992")
   (gate manual)
   (gate-gap "Only scripts/rebuild-and-run-mapping-fail-closed.sh exercises this path, and no workflow calls it; the witness is real but no CI gate re-proves it. Wiring it needs the QEMU image build inside an existing M2 workflow.")
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
