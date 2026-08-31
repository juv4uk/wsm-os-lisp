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
}
