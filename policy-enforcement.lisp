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
   "Image determinism is currently unproven in CI. Rewrite against the current build path, then gate it.")
  (script "scripts/check-fpc-parity.sh"
   "Legacy FPC 3.2.2 Linux-target W3 runner. Active acceptance moved to pinned FPC 3.3.1 x86_64-embedded via scripts/check-fpc-embedded-parity.sh; historical Linux measurements are retained in docs/FPC-PARITY-P2.md."
   "Keep only as a historical reproducer while the embedded gate gains three-repeat and physical-host evidence; then remove.")
))

 (arbiter-budget
  ; ADR-005 W5: the arbiter's share of hand-written code is a published number
  ; with a ceiling, not an adjective. The owner may change max-share; an agent
  ; may not. Crossing the ceiling fails the build, so growth needs a decision.
  ;
  ; The arbiter is everything under src/ in any admitted production language, not
  ; "the .s files". Naming the language here would have let a language change
  ; (ADR-006) silently move the mechanism out from under the ceiling while the
  ; gate kept reporting a comfortable number.
  (max-share 0.40)
  (arbiter-root "src/")
  (arbiter-extensions ".s" ".pas" ".pp" ".lpr" ".c" ".h")
  (code-extensions ".s" ".lisp" ".sh" ".py" ".pas" ".pp" ".lpr" ".c" ".h")
  (excluded-prefix "artifacts/"))

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
   (id gate-suite-budget)
   (claim "The static gate suite stays inside a wall-clock ceiling, so the feedback loop cannot quietly rot into something people skip.")
   (enforcement literal "scripts/check-gate-budget.sh" "above the")
   (witness runtime)
   (gate "scripts/check-gate-budget.sh")
   (note "A tripwire, not a target: the ceiling is 10 s against a measured ~2.9 s, so it fires on a tenfold regression and not on a slow runner. One run is enough for a tripwire; publishing a number still needs the median of twenty from measure-gate-suite.sh.")
   (status proved))

  (policy
   (id fpc-parity-witness)
   (claim "The Pascal entry produces a RESULT line byte-identical to the hand-written assembly fixture, with zero undefined symbols in the linked kernel.")
   (enforcement literal "scripts/check-fpc-kernel-skeleton.sh" "parity broken:")
   (witness transcript "artifacts/nucleus-witness-pascal-entry-qemu-serial-transcript.txt" "WSM-OS RESULT schema=1 value=(sym1 . sym2) status=ok")
   (gate "scripts/check-fpc-kernel-skeleton.sh")
   (note "Compiled with -Tlinux -Cn, so this proves an x86-64 object from FPC links against our linker and calls our ABI; it does not prove the embedded RTL is usable. The comparison itself was added on 2026-11-27: before that the claim lived in the script header while the script only printed the last line.")
   (status proved))

  (policy
   (id adr-ratification-provenance)
   (claim "An ADR is marked ACCEPTED only by an owner-authored commit or by an owner-authored confirmation in docs/decisions/OWNER-CONFIRMATIONS.lisp.")
   (enforcement literal "scripts/check-adr-ratification.sh" "An ADR marked ACCEPTED without the owner is an agent ratifying architecture.")
   (witness runtime)
   (gate "scripts/check-adr-ratification.sh")
   (note "Limitation, stated so nobody over-claims: git identity is not authentication. The gate raises the cost of a silent self-ratification and makes the difference between owner and agent visible in the record; it cannot prove who typed the commit. It currently fails on ADR-006, which was moved to ACCEPTED by an agent identity on 2026-11-26.")
   (status proved))

  (policy
   (id task-format)
   (claim "Every task not declared legacy carries its level, a user journey, an evidence plan and fail-safely triggers, so a task that cannot state them is not worked on.")
   (enforcement literal "scripts/check-task-format.py" "A task without level, user journey, evidence plan and")
   (witness runtime)
   (gate "scripts/check-task-format.py")
   (note "Definition of Done items 1-3 from the owner's agent prompt, enforced on new tasks only. 55 tasks predate the rule and are listed in task-format-disposition.lisp; the list is checked both ways, so a legacy task that gains the fields must leave it.")
   (status proved))

  (policy
   (id docs-in-change)
   (claim "A push that changes src/ or scripts/ also changes documentation, unless a commit in the range declares DOCS-NOT-REQUIRED: <reason>.")
   (enforcement literal "scripts/check-docs-in-change.sh" "DOCS-NOT-REQUIRED:")
   (witness runtime)
   (gate "scripts/check-docs-in-change.sh")
   (note "Definition of Done item 5 from the owner's agent prompt, the first of its eight items to get teeth. Scope is the push range only. Verified against a real code-only commit in this repository (1aff7f3) which the gate rejects, and against the marker path which it accepts.")
   (status proved))

  (policy
   (id no-new-branches)
   (claim "No branch is created outside the recorded disposition, and no frozen branch tip moves: finished work lands in main.")
   (enforcement literal "AGENTS.md" "Заборонено створювати будь-які нові гілки")
   (witness runtime)
   (gate "scripts/check-branch-policy.py")
   (note "Detective, not preventive. Prevention needs repository admin rights: contracts/github-ruleset-no-new-branches.json is the importable ruleset with the Restrict creations rule, and only the owner can apply it. A listed branch that disappears is a warning, because deleting them is the intended end state.")
   (status proved))

  (policy
   (id documentation-authority-gate-always-runs)
   (claim "The workflow that polices documentation runs on every commit and is never narrowed by a paths filter, so a docs-only change cannot pass unread.")
   (enforcement literal ".github/workflows/ci.yml" "bash scripts/check-role-authority.sh")
   (witness runtime)
   (gate "scripts/check-policy-enforcement.py")
   (note "The gate asserts both halves: ci.yml runs the documentation gates and has no paths/paths-ignore under on:. Removing either fails the build.")
   (status proved))

  (policy
   (id image-build-variance-pinned)
   (claim "Every known source of variance in the UEFI image builder is explicitly pinned: both GPT identities, the FAT volume identity and the FAT timestamps, with no generated UUID, shell randomness or wall-clock time in the builder.")
   (enforcement literal "scripts/build-uefi-image.sh" "mkfs.vfat --invariant -F 12")
   (witness runtime)
   (gate "scripts/check-build-variance.sh")
   (note "Pins present is not reproducibility: the byte-identical rebuild witness is still legacy, so this policy must not be quoted as proof that the image is reproducible. See ADR-005 5.1.1.")
   (status proved))

  (policy
   (id open-language-policy)
   (claim "No programming language is prohibited by name or source directory.")
   (enforcement literal "docs/ADR-009-OPEN-LANGUAGE-AND-CODE-REUSE.md" "No blanket language bans")
   (witness runtime)
   (gate "scripts/check-language-policy.sh")
   (status proved))

  (policy
   (id no-data-to-command-interpolation)
   (claim "Repository scripts never turn data into a shell command string: no eval, no interpolated -c string, no command substitution as a command name, no shell=True.")
   (enforcement literal "scripts/check-shell-safety.sh" "eval is forbidden in repository scripts")
   (witness runtime)
   (gate "scripts/check-shell-safety.sh")
   (note "Syntactic guard, not a data-flow witness. It proves the dangerous constructs are absent; it does not prove that no untrusted value reaches a privileged action by some other route. A gate must reproduce the actual threat and cover the whole data path, not just the syntax — see ADR-005 section 6.")
   (status proved))))
