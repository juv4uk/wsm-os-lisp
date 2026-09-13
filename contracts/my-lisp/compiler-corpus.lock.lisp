; Consumer lock for juv4uk/my-lisp#67.
; This file selects upstream compiler-corpus records for the first bounded
; hosted+QEMU shared-parity set. Source and expected observations are read
; from the pinned upstream file at test time; they are not copied here.
(compiler-corpus-lock
  (source
    (repository juv4uk/my-lisp)
    (path tests/fixtures/conformance.my))
  (revision "4a5dba0d1d61103385406ef2821d76661442621c")
  ; Zero-based among records carrying (compiler-corpus . t).
  ; Records 1 and 2 return canonical t through different Canon mechanisms;
  ; record 8 proves two distinct lambda values are not eq and returns NIL.
  ; Their expr/expected fields deliberately remain only in upstream authority.
  (selector
    (compiler-corpus-ordinals (1 2 8)))
  (authority
    (issue 67)
    (role semantic-oracle)))
