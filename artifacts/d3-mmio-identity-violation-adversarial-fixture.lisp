((lambda (pci)
   (mmio-write32 pci 20 1))
 (pci-config-capability))