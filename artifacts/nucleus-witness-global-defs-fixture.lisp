; nucleus-witness-global-defs-fixture.lisp
;
; Intended constitutional program for nucleus-witness-global-defs-fixture.s.
; This is the human-readable source projection of the witness; the shipped
; target assembly is hand-written (fixture-provenance = hand-written-assembly)
; and is NOT claimed to be CML-emitted. CML emission plus oracle/hosted parity
; for the same shape is the obligation of CONSTITUTION-GLOBAL-ENV-PARITY.
;
; Constitutional laws exercised:
;   * a global name binds a value (here: an escaping closure);
;   * a call resolves the callee by name at call time, so two definitions can
;     refer to each other before either body runs (mutual recursion);
;   * redefining a name changes what later lookups return, without consuming
;     definition capacity and without invalidating the identity of other names.

(define f (lambda (x) (if (atom x) (quote done) (g (cdr x)))))
(define g (lambda (x) (f x)))

(define first-result (f (cons (quote a) (cons (quote b) (quote ())))))

(define f (lambda (x) (quote redefined)))
(define second-result (f (quote ())))

(cons first-result (cons second-result (quote ())))
; => (done redefined)
