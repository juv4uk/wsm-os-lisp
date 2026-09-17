(def poll-ack
  (lambda (mmio ignored n)
    (cond
      ((eq n 0) ())
      ((eq (mmio-read32 mmio 20) 1) t)
      (t (poll-ack mmio ignored (- n 1))))))
(poll-ack (mmio-capability)
          (mmio-write32 (mmio-capability) 20 1)
          64)
