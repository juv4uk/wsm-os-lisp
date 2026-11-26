; nucleus-witness-global-unbound-fixture.lisp
;
; Intended constitutional program: reference a name that was never bound.
; The target must raise a named SYMBOL condition carrying the offending name
; word. NIL is a value, so "unbound" must never be represented as NIL.

(f)
