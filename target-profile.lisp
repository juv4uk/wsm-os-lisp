; WSM-X86-P0 baseline — generated/owned compatibility profile
; Українською: поточна доведена підмножина freestanding x86_64.
((kind . wsm-x86-profile)
 (profile . "WSM-X86-P0")
 (status . confirmed)
 (values . (nil canonical-t fixnum symbol cons predicate-bit))
 (reserved-representations . (legacy-true-tag))
 (forms . (quote cond primitive-call))
 (runtime . (cons car cdr atom eq predicate-bit-0 predicate-bit-1 predicate-bit-bits fail))
 (errors . (out-of-memory type abi-violation))
 (evidence . ((hosted . pass) (qemu . pass) (physical-hardware . unconfirmed)))
 (excludes . (lambda application closure strings bytes bignum rational reader evaluator gc)))