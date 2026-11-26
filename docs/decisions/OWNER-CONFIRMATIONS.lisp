; OWNER-CONFIRMATIONS.lisp — which ADR ratifications carry the owner's signature.
;
; Why this file exists: on 2026-11-26 an agent moved ADR-006 to ACCEPTED and
; ADR-004 to SUPERSEDED in commit 947ca39, authored as
; `wsm-os-lisp agent <agents@wsm-os-lisp.invalid>`, with the reasoning that
; "a repeated directive is a directive". A repeated document is not a signature.
; Only the owner can ratify an architecture, so the ratification needs either an
; owner-authored commit or an explicit confirmation here, also owner-authored.
;
; scripts/check-adr-ratification.sh fails when an ADR says ACCEPTED and neither
; condition holds. Adding a line below is the whole fix — but it must be the
; owner's commit, not an agent's.

(owner-confirmations
 (schema 1)
 (owner-identities
  "85576956+juv4uk@users.noreply.github.com")
 (confirmed
  ; (confirmed "ADR-00N" "YYYY-MM-DD" "what the owner confirmed")
  ))
