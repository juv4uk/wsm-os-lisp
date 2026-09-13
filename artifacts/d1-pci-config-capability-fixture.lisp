((lambda (pci)
   (((lambda (vendor)
       (lambda (device)
         (cond
           ((eq vendor 6900) (eq device 4162))
           (t ()))))
     (pci-config-read16 pci 0 5 0 0))
    (pci-config-read16 pci 0 5 0 2)))
 (pci-config-capability))
