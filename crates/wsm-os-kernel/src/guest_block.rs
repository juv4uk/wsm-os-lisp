//! Minimal guest-visible block contract for Q6a.

pub const BLOCK_BYTES: usize = 512;

pub struct GuestBlockMedium {
    block: [u8; BLOCK_BYTES],
    dirty: bool,
}

impl GuestBlockMedium {
    pub const fn new() -> Self {
        Self {
            block: [0; BLOCK_BYTES],
            dirty: false,
        }
    }

    pub fn write(&mut self, bytes: &[u8]) -> bool {
        if bytes.len() > BLOCK_BYTES {
            return false;
        }
        let mut index = 0;
        while index < bytes.len() {
            self.block[index] = bytes[index];
            index += 1;
        }
        self.dirty = true;
        true
    }

    pub fn read_matches(&self, bytes: &[u8]) -> bool {
        bytes.len() <= BLOCK_BYTES && self.block[..bytes.len()] == *bytes
    }

    pub fn flush(&mut self) -> bool {
        let was_dirty = self.dirty;
        self.dirty = false;
        was_dirty
    }
}
