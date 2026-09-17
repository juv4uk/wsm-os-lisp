(def poll-ready
  (lambda (mmio ignored n)
    (cond
      ((eq n 0) ())
      ((eq (mmio-read32 mmio 20) 4) t)
      (t (poll-ready mmio ignored (- n 1))))))
(poll-ready (mmio-capability)
            (mmio-write32 (mmio-capability) 20 1)
            64)
