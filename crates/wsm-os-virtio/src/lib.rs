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
}
