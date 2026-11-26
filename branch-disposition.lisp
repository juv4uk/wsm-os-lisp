; branch-disposition.lisp — the machine-readable branch archive index.
;
; Why this exists: the owner directive of 2026-10-11 forbids creating new
; branches and requires integrating finished work directly into main. That rule
; had no mechanism until now. scripts/check-branch-policy.py reads this file and
; fails when a branch appears that is not listed, or when a listed branch tip
; moves (which means someone pushed to a branch that is supposed to be frozen).
;
; A listed branch that disappears is a warning, not a failure: deleting these is
; the intended end state, and the tip SHA here is the address that survives it.
; Verdicts for the eleven reviewed branches are in docs/BRANCH-INVENTORY-2026-11-26.md.

(branch-disposition
 (schema 1)
 (authority "AGENTS.md, owner directive 2026-10-11 — no new branches")
 (gate-script "scripts/check-branch-policy.py")
 (branches
  (branch "authority/error-code-admission" "75a585db6390c46101ebb56033ac4305b9feadf5")
  (branch "authority/role-boundary" "4370c994fec6a20141a1aa4b062cdcf37560181f")
  (branch "authority/semantic-guard" "3e58d433994137e2b20daefa808931f81e2314d3")
  (branch "chatgpt/bounded-serial-current-main" "f73be42caac9972216c107c72ba211feb5583a5c")
  (branch "chatgpt/target-abi-v6-consumer" "7ca34e1d9a8a13a56c3ed9234b4ab6edfb826f0b")
  (branch "chore/volnist-current-surfaces" "d324ba9a1a62d3d08a7fbaaadd77da1188cba810")
  (branch "docs/m2-ledger-sync-2026-10-08" "f8e0863cb90f9c97a8ca2879700642889952afeb")
  (branch "feat/33-target-observer-bounded" "46ccda36e90a974f4d085bebf38d4ee8e83dab89")
  (branch "fix/31-bounded-uart-poll" "9955dee4edfda674527c4d84d943cbb044f680e4")
  (branch "fix/45-boxed-rational-runtime-v9-20261126" "d7c57e6b8d52b3a880e6528cd5206508fe5eac02")
  (branch "fix/ci-sens-submodule-path" "5172bf8bb73c825acb3c9f59fc13680c272ca805")
  (branch "fix/sens-paths-lisp-current" "c762f62124a1a2af586e006da2f4c8815679b330")
  (branch "integration/neutral-target-contract" "3253c0a7174eec5ef1b1618bef1709e6c0f85672")
  (branch "issue-76-m0-m1-boot-witness-phase-a" "9e545a99610f3259010152ca3adbb309f04ec41a")
  (branch "issue-76-sens-l3-qemu-parity" "661eac2ea3b0948d7b5dd9e6b17b045f9164215a")
  (branch "issue-77-clean-restart-sector-v1" "3ac04f05d86ea0a984b0065cf1f2f0700b133e32")
  (branch "issue-77-clean-restart-sector-v2" "9343c5dc9ae7560c6b2b9c8fb1c14ac0451fe42b")
  (branch "issue-77-m2-q6b-realign" "9868ae402f76cd42f4b303f268d61972db9e7e10")
  (branch "issue-78-pit-irq-v1" "42a4cc49dfaf6ffaf71040a5ebae6ce57c158194")
  (branch "issue-82-falsifier-matrix-v1" "3b03195f2f46a67dfd474f08632db78d1e1b4655")
  (branch "issue-82-sector-roundtrip-v1" "ea0923eb278580a86b3b590ca98a1a525999afb7")
  (branch "issue-82-virtqueue-setup-v1" "7bd16538a49e67faa0fd35480174b66401131f13")
  (branch "issue-84-dma-address-proof-v1" "5312e08dc23faf7050b7fc7f3eb7ed5cb2254bb4")
  (branch "issue-84-dma-evidence-v2" "6b4503f2b5223643a5d3a63c9e544adae32809a9")
  (branch "issue-86-predicate-bit-v8-consumer" "6fcf0de50c03e8cd12f168ad9bc738dc90cc4bf6")
  (branch "issue-95-canonical-envelope-v1" "d6d8e3a3c2a192c26c18ec77220ae3d7add7c716")
  (branch "parity/bounded-oracle-observer" "c17b6d2c101f3531d8b6eb48dc58531ce544b312")
  (branch "parity/compiler-owned-symbols" "767bf05656454b745664c538c9d0cd64aa98f813")
  (branch "parity/compiler-symbol-provenance" "92880a7c6d05042e79d746a57a93cf36bca04960")
  (branch "parity/shared-oracle-corpus" "a12dc112745dcdce781b179372b2ee2e96196b74")
  (branch "parity/shared-oracle-coverage" "00cdd06ad24b131b50df594a25f09a19082021a9")
  (branch "parity/shared-oracle-t-set" "dc8e55e264de12b0a49e69d414da3456598f85af")
  (branch "provenance/gpt-canonicalization" "9b0f3c36aaffb6ee62a98a77103c77b74424a92c")
  (branch "provenance/gpt-variance-model" "362d48a346220e513cd2c99b716d556a46da4025")
  (branch "provenance/image-determinism" "245fb6f03721f376d60e2a601fb62ce15ebbd822")
  (branch "provenance/shared-oracle-chain" "b71163706cf8ea2ee159b0ea5aaf818d027f94bb")
  (branch "provenance/shared-oracle-chain-2" "c95f63042e6d6b7f8024013bf239788d5f94f762")
  (branch "rename/sens-contract-authority" "c2cebd9035f35a0352b7da47a89d3551b77985cc")
  (branch "replay/31-always-on-serial-gate-20261009" "89f4b56b5efb88422670e6157b86c68cd9532cd2")
  (branch "replay/31-qemu-never-ready-uart-20261009" "50812a63efc5e9f23dee96a37ad6b26cbe23e2a9")
  (branch "replay/31-serial-bounded-regression-20261009" "ecfa7ba23151d3be1bacbb2c45e2a7626db522cd")
  (branch "replay/31-serial-exit39-main-20261009" "4c60d020a292bf751547cfd027e7cca989dc8820")
  (branch "replay/54-sens-authority-cutover-20261009" "5bbb8b724b358d51cdcb042722113291de795bfb")
  (branch "replay/57-active-lisp-path-hygiene-20261009" "99654e1b9821e8e3ae25289d71de67624be4c2b2")
  (branch "replay/57-oracle-temp-lisp-20261009" "ac876ce076ad60e1bff7db5ca423e07e59e27199")
  (branch "research/60-mark-sweep-arena-model" "e503ef3e64d426046eb88fa95eb5ca3ca3a266d8")
  (branch "research/62-gc-root-map-abi" "6a76e5cffad4abcba027e86a5ea39d3f86c3c95b")
  (branch "research/64-closure-new-positive-control" "2dc87a8dbf8c7ff8bda2eaa3306438c04423ee61")
  (branch "research/64-root-map-wire-consumer" "431a9f4c82949c53473bd0d4a29bc225b4dbfd84")
  (branch "research/66-final-pc-binding" "8ef9c96fa9372fe2870d04fd6ff696ccb603ab73")
  (branch "research/66-final-pc-main-replay" "d42475fbca4d35459ff536929ad54c2858a5dfef")
  (branch "test/45-boxed-rational-runtime-red" "262b036ee0489c38665b6034c1a2e2b4e9294f44")
  (branch "test/64-quote-bounded-root-map-wire" "89a0008d83da05dc15bc69b1fd1dfebd2fedbb6b")
  (branch "tmp-ignore" "245fb6f03721f376d60e2a601fb62ce15ebbd822")
  (branch "main" "moving")))  ; main is the only ref allowed to move
