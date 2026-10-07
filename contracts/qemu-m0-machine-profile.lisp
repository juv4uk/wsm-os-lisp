; Canonical automated machine profile for wsm-os-lisp M0/M1.
; This is machine/test-harness data, not SENS semantic authority.
(wsm-os-qemu-machine-profile
  (schema 1)
  (architecture x86_64)
  (machine q35)
  (memory-mib 128)
  (firmware OVMF)
  (console
    (kind com1)
    (baud 115200)
    (format 8n1))
  (debug-exit
    (iobase #x00f4)
    (iosize #x0004))
  (display none)
  (reboot disabled)
  (guest-timeout-seconds 30))
