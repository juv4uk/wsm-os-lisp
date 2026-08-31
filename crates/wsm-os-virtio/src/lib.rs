#![no_std]

//! Bounded virtio contract constants. PCI probing and MMIO are intentionally
//! kept out until a platform access layer is ratified.

pub const VENDOR_ID: u16 = 0x1af4;
pub const DEVICE_ID_BLOCK: u16 = 0x1042;
pub const STATUS_ACKNOWLEDGE: u8 = 1;
pub const STATUS_DRIVER: u8 = 2;
pub const STATUS_DRIVER_OK: u8 = 4;
pub const STATUS_FAILED: u8 = 128;
pub const SECTOR_BYTES: usize = 512;
pub const PCI_VENDOR_ID_OFFSET: u8 = 0x00;
pub const PCI_DEVICE_ID_OFFSET: u8 = 0x02;
pub const PCI_BAR0_OFFSET: u8 = 0x10;
pub const PCI_INTERRUPT_LINE_OFFSET: u8 = 0x3c;
pub const COMMON_CFG_DEVICE_FEATURE_SELECT: u16 = 0x00;
pub const COMMON_CFG_DEVICE_FEATURE: u16 = 0x04;
pub const COMMON_CFG_DRIVER_FEATURE_SELECT: u16 = 0x08;
pub const COMMON_CFG_DRIVER_FEATURE: u16 = 0x0c;
pub const COMMON_CFG_STATUS: u16 = 0x14;
pub const COMMON_CFG_QUEUE_SELECT: u16 = 0x16;
pub const COMMON_CFG_QUEUE_SIZE: u16 = 0x18;
pub const COMMON_CFG_QUEUE_ENABLE: u16 = 0x1c;
pub const COMMON_CFG_QUEUE_NOTIFY_OFF: u16 = 0x1e;
pub const MAX_QUEUE_SIZE: u16 = 8;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct DeviceStatus(u8);

impl DeviceStatus {
    pub const fn new() -> Self {
        Self(0)
    }
    pub const fn bits(self) -> u8 {
        self.0
    }

    pub fn acknowledge(self) -> Option<Self> {
        if self.0 == 0 {
            Some(Self(STATUS_ACKNOWLEDGE))
        } else {
            None
        }
    }
    pub fn driver(self) -> Option<Self> {
        if self.0 == STATUS_ACKNOWLEDGE {
            Some(Self(STATUS_ACKNOWLEDGE | STATUS_DRIVER))
        } else {
            None
        }
    }
    pub fn driver_ok(self) -> Option<Self> {
        if self.0 == (STATUS_ACKNOWLEDGE | STATUS_DRIVER) {
            Some(Self(self.0 | STATUS_DRIVER_OK))
        } else {
            None
        }
    }
    pub const fn failed(self) -> Self {
        Self(self.0 | STATUS_FAILED)
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct DeviceIdentity {
    pub vendor_id: u16,
    pub device_id: u16,
}

impl DeviceIdentity {
    pub const fn is_virtio_block(self) -> bool {
        self.vendor_id == VENDOR_ID && self.device_id == DEVICE_ID_BLOCK
    }
}

/// Decode the only PCI fields needed by the first probe from a bounded config
/// snapshot. No MMIO or unchecked pointer access belongs in this layer.
pub fn probe_identity(config: &[u8]) -> Option<DeviceIdentity> {
    let vendor = read_u16(config, PCI_VENDOR_ID_OFFSET as usize)?;
    let device = read_u16(config, PCI_DEVICE_ID_OFFSET as usize)?;
    Some(DeviceIdentity {
        vendor_id: vendor,
        device_id: device,
    })
}

pub trait PciConfigAccess {
    fn read_u16(&self, offset: u8) -> Option<u16>;
}

pub trait MmioAccess {
    fn read_u32(&self, offset: u16) -> Option<u32>;
    fn write_u32(&mut self, offset: u16, value: u32) -> bool;
}

pub fn negotiate_status<M: MmioAccess>(mmio: &mut M) -> bool {
    let mut status = DeviceStatus::new();
    status = match status.acknowledge() {
        Some(next) => next,
        None => return false,
    };
    if !mmio.write_u32(COMMON_CFG_STATUS, status.bits() as u32) {
        return false;
    }
    status = match status.driver() {
        Some(next) => next,
        None => return false,
    };
    if !mmio.write_u32(COMMON_CFG_STATUS, status.bits() as u32) {
        return false;
    }
    status = match status.driver_ok() {
        Some(next) => next,
        None => return false,
    };
    mmio.write_u32(COMMON_CFG_STATUS, status.bits() as u32)
}

pub fn probe_identity_from<A: PciConfigAccess>(access: &A) -> Option<DeviceIdentity> {
    Some(DeviceIdentity {
        vendor_id: access.read_u16(PCI_VENDOR_ID_OFFSET)?,
        device_id: access.read_u16(PCI_DEVICE_ID_OFFSET)?,
    })
}

fn read_u16(bytes: &[u8], offset: usize) -> Option<u16> {
    let low = *bytes.get(offset)? as u16;
    let high = *bytes.get(offset + 1)? as u16;
    Some(low | (high << 8))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn identifies_only_virtio_block_device() {
        assert!(DeviceIdentity {
            vendor_id: VENDOR_ID,
            device_id: DEVICE_ID_BLOCK
        }
        .is_virtio_block());
        assert!(!DeviceIdentity {
            vendor_id: VENDOR_ID,
            device_id: 0x1041
        }
        .is_virtio_block());
        assert!(!DeviceIdentity {
            vendor_id: 0x1234,
            device_id: DEVICE_ID_BLOCK
        }
        .is_virtio_block());
    }

    #[test]
    fn probe_contract_is_bounded() {
        assert_eq!(PCI_BAR0_OFFSET, 0x10);
        assert_eq!(COMMON_CFG_STATUS, 0x14);
        assert!(MAX_QUEUE_SIZE.is_power_of_two());
        assert!(MAX_QUEUE_SIZE <= 256);
    }

    #[test]
    fn probe_reads_little_endian_identity_and_rejects_short_config() {
        let mut config = [0_u8; 64];
        config[PCI_VENDOR_ID_OFFSET as usize..][..2].copy_from_slice(&VENDOR_ID.to_le_bytes());
        config[PCI_DEVICE_ID_OFFSET as usize..][..2]
            .copy_from_slice(&DEVICE_ID_BLOCK.to_le_bytes());
        assert_eq!(
            probe_identity(&config),
            Some(DeviceIdentity {
                vendor_id: VENDOR_ID,
                device_id: DEVICE_ID_BLOCK
            })
        );
        assert_eq!(probe_identity(&config[..1]), None);
    }

    struct MockConfig([u16; 2]);
    impl PciConfigAccess for MockConfig {
        fn read_u16(&self, offset: u8) -> Option<u16> {
            match offset {
                PCI_VENDOR_ID_OFFSET => Some(self.0[0]),
                PCI_DEVICE_ID_OFFSET => Some(self.0[1]),
                _ => None,
            }
        }
    }

    #[test]
    fn injected_config_access_keeps_probe_platform_neutral() {
        let config = MockConfig([VENDOR_ID, DEVICE_ID_BLOCK]);
        assert_eq!(
            probe_identity_from(&config),
            Some(DeviceIdentity {
                vendor_id: VENDOR_ID,
                device_id: DEVICE_ID_BLOCK
            })
        );
    }

    #[test]
    fn status_progression_is_monotonic_and_fail_closed() {
        let initial = DeviceStatus::new();
        let acknowledged = initial.acknowledge().unwrap();
        let driver = acknowledged.driver().unwrap();
        let ready = driver.driver_ok().unwrap();
        assert_eq!(ready.bits(), 7);
        assert!(initial.driver().is_none());
        assert!(ready.driver_ok().is_none());
        assert_eq!(ready.failed().bits(), 0x87);
    }

    struct MockMmio {
        status: u32,
    }
    impl MmioAccess for MockMmio {
        fn read_u32(&self, offset: u16) -> Option<u32> {
            (offset == COMMON_CFG_STATUS).then_some(self.status)
        }
        fn write_u32(&mut self, offset: u16, value: u32) -> bool {
            if offset == COMMON_CFG_STATUS {
                self.status = value;
                true
            } else {
                false
            }
        }
    }

    #[test]
    fn status_negotiation_uses_only_declared_mmio_register() {
        let mut mmio = MockMmio { status: 0 };
        assert!(negotiate_status(&mut mmio));
        assert_eq!(mmio.read_u32(COMMON_CFG_STATUS), Some(7));
    }
}
