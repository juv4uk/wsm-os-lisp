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
pub struct DeviceIdentity {
    pub vendor_id: u16,
    pub device_id: u16,
}

impl DeviceIdentity {
    pub const fn is_virtio_block(self) -> bool {
        self.vendor_id == VENDOR_ID && self.device_id == DEVICE_ID_BLOCK
    }
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
}
