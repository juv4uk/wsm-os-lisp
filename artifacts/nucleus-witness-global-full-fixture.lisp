; nucleus-witness-global-full-fixture.lisp
;
; Intended constitutional program: the global definition table is a bounded
; target arena (256 entries). Binding 257 distinct names must fail with the
; named OOM condition and must not overwrite a live definition.

(bind-names 257)
