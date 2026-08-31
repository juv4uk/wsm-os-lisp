//! Bounded byte-level medium for WSM filesystem experiments.
//!
//! This crate knows nothing about WSM values, names, roots, journals, or
//! evaluation. It provides fixed-size blocks with a versioned data header,
//! checksum validation, and explicit flush.
//!
//! Це лише механізм байтового сховища. Семантика WSM FS лишається в
//! `my-lisp`; цей crate не знає про імена, roots, journal або виконання.

use std::fs::{File, OpenOptions};
use std::io::{self, Read, Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};

pub const HEADER_BYTES: usize = 16;
pub const MAX_BLOCK_SIZE: usize = 1024 * 1024;
pub const MAGIC: [u8; 4] = *b"WSMB";
pub const FORMAT_VERSION: u8 = 1;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BlockError {
    InvalidGeometry,
    IndexOutOfRange {
        index: u64,
        block_count: u64,
    },
    PayloadTooLarge {
        actual: usize,
        maximum: usize,
    },
    UnwrittenBlock {
        index: u64,
    },
    TruncatedBlock {
        index: u64,
        actual: usize,
        expected: usize,
    },
    InvalidHeader {
        index: u64,
    },
    ChecksumMismatch {
        index: u64,
    },
    Io(String),
}

impl From<io::Error> for BlockError {
    fn from(error: io::Error) -> Self {
        Self::Io(error.to_string())
    }
}

/// Mechanism-only interface. Implementations must not interpret payload bytes.
pub trait BlockMedium {
    fn block_size(&self) -> usize;
    fn block_count(&self) -> u64;
    fn read_block(&mut self, index: u64) -> Result<Vec<u8>, BlockError>;
    fn write_block(&mut self, index: u64, bytes: &[u8]) -> Result<(), BlockError>;
    fn flush(&mut self) -> Result<(), BlockError>;
}

/// Deterministic fixed-geometry file-backed medium for hosted evidence.
pub struct FileBlockMedium {
    file: Option<File>,
    path: PathBuf,
    block_size: usize,
    block_count: u64,
}

impl FileBlockMedium {
    pub fn create(
        path: impl AsRef<Path>,
        block_size: usize,
        block_count: u64,
    ) -> Result<Self, BlockError> {
        validate_geometry(block_size, block_count)?;
        let path = path.as_ref().to_path_buf();
        let file = OpenOptions::new()
            .create(true)
            .truncate(true)
            .read(true)
            .write(true)
            .open(&path)?;
        file.set_len(total_bytes(block_size, block_count)?)?;
        Ok(Self {
            file: Some(file),
            path,
            block_size,
            block_count,
        })
    }

    pub fn open(
        path: impl AsRef<Path>,
        block_size: usize,
        block_count: u64,
    ) -> Result<Self, BlockError> {
        validate_geometry(block_size, block_count)?;
        let path = path.as_ref().to_path_buf();
        let file = OpenOptions::new().read(true).write(true).open(&path)?;
        if file.metadata()?.len() != total_bytes(block_size, block_count)? {
            return Err(BlockError::InvalidGeometry);
        }
        Ok(Self {
            file: Some(file),
            path,
            block_size,
            block_count,
        })
    }

    pub fn path(&self) -> &Path {
        &self.path
    }

    fn seek_block(&mut self, index: u64) -> Result<(), BlockError> {
        check_index(index, self.block_count)?;
        let offset = block_offset(index, self.block_size)?;
        self.file_mut()?.seek(SeekFrom::Start(offset))?;
        Ok(())
    }

    fn file_mut(&mut self) -> Result<&mut File, BlockError> {
        self.file
            .as_mut()
            .ok_or_else(|| BlockError::Io("medium is closed".to_string()))
    }

    #[cfg(test)]
    fn close_for_test(&mut self) {
        self.file = None;
    }
}

impl BlockMedium for FileBlockMedium {
    fn block_size(&self) -> usize {
        self.block_size
    }
    fn block_count(&self) -> u64 {
        self.block_count
    }

    fn read_block(&mut self, index: u64) -> Result<Vec<u8>, BlockError> {
        self.seek_block(index)?;
        let mut raw = vec![0_u8; self.block_size];
        let mut read = 0;
        while read < raw.len() {
            let n = self.file_mut()?.read(&mut raw[read..])?;
            if n == 0 {
                break;
            }
            read += n;
        }
        if read != raw.len() {
            return Err(BlockError::TruncatedBlock {
                index,
                actual: read,
                expected: raw.len(),
            });
        }
        if raw.iter().all(|byte| *byte == 0) {
            return Err(BlockError::UnwrittenBlock { index });
        }
        if raw[..4] != MAGIC || raw[4] != FORMAT_VERSION || raw[5..8] != [0, 0, 0] {
            return Err(BlockError::InvalidHeader { index });
        }
        let payload_len = u32::from_le_bytes(raw[8..12].try_into().unwrap()) as usize;
        let maximum = self.block_size - HEADER_BYTES;
        if payload_len > maximum {
            return Err(BlockError::InvalidHeader { index });
        }
        let expected_checksum = u32::from_le_bytes(raw[12..16].try_into().unwrap());
        let payload = &raw[HEADER_BYTES..HEADER_BYTES + payload_len];
        if checksum(payload) != expected_checksum {
            return Err(BlockError::ChecksumMismatch { index });
        }
        Ok(payload.to_vec())
    }

    fn write_block(&mut self, index: u64, bytes: &[u8]) -> Result<(), BlockError> {
        self.seek_block(index)?;
        let maximum = self.block_size - HEADER_BYTES;
        if bytes.len() > maximum {
            return Err(BlockError::PayloadTooLarge {
                actual: bytes.len(),
                maximum,
            });
        }
        let mut raw = vec![0_u8; self.block_size];
        raw[..4].copy_from_slice(&MAGIC);
        raw[4] = FORMAT_VERSION;
        raw[8..12].copy_from_slice(&(bytes.len() as u32).to_le_bytes());
        raw[12..16].copy_from_slice(&checksum(bytes).to_le_bytes());
        raw[HEADER_BYTES..HEADER_BYTES + bytes.len()].copy_from_slice(bytes);
        self.file_mut()?.write_all(&raw)?;
        Ok(())
    }

    fn flush(&mut self) -> Result<(), BlockError> {
        self.file_mut()?.sync_data()?;
        Ok(())
    }
}

fn validate_geometry(block_size: usize, block_count: u64) -> Result<(), BlockError> {
    if block_size < HEADER_BYTES
        || block_size > MAX_BLOCK_SIZE
        || block_count == 0
        || block_count > usize::MAX as u64
    {
        Err(BlockError::InvalidGeometry)
    } else {
        total_bytes(block_size, block_count).map(|_| ())
    }
}

fn total_bytes(block_size: usize, block_count: u64) -> Result<u64, BlockError> {
    (block_size as u64)
        .checked_mul(block_count)
        .ok_or(BlockError::InvalidGeometry)
}

fn block_offset(index: u64, block_size: usize) -> Result<u64, BlockError> {
    (block_size as u64)
        .checked_mul(index)
        .ok_or(BlockError::InvalidGeometry)
}

fn check_index(index: u64, block_count: u64) -> Result<(), BlockError> {
    if index < block_count {
        Ok(())
    } else {
        Err(BlockError::IndexOutOfRange { index, block_count })
    }
}

/// FNV-1a integrity checksum. Authenticity is not claimed.
pub fn checksum(bytes: &[u8]) -> u32 {
    bytes.iter().fold(0x811c9dc5_u32, |hash, byte| {
        hash.wrapping_mul(0x01000193) ^ u32::from(*byte)
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    fn temp_path(name: &str) -> PathBuf {
        std::env::temp_dir().join(format!("wsm-os-block-{name}-{}", std::process::id()))
    }

    #[test]
    fn round_trip_and_flush() {
        let path = temp_path("round-trip");
        let mut medium = FileBlockMedium::create(&path, 64, 2).unwrap();
        medium.write_block(1, b"hello").unwrap();
        medium.flush().unwrap();
        assert_eq!(medium.read_block(1).unwrap(), b"hello");
        fs::remove_file(path).unwrap();
    }

    #[test]
    fn bounds_and_payload_limit_fail_closed() {
        let path = temp_path("bounds");
        let mut medium = FileBlockMedium::create(&path, 32, 1).unwrap();
        assert!(matches!(
            medium.read_block(1),
            Err(BlockError::IndexOutOfRange { .. })
        ));
        assert!(matches!(
            medium.write_block(0, &[0; 17]),
            Err(BlockError::PayloadTooLarge { .. })
        ));
        fs::remove_file(path).unwrap();
    }

    #[test]
    fn oversized_geometry_is_rejected_before_allocation() {
        let path = temp_path("oversized-geometry");
        assert!(matches!(
            FileBlockMedium::create(&path, MAX_BLOCK_SIZE + 1, 1),
            Err(BlockError::InvalidGeometry)
        ));
        assert!(!path.exists());
    }

    #[test]
    fn unwritten_and_corrupt_blocks_are_distinct() {
        let path = temp_path("corrupt");
        let mut medium = FileBlockMedium::create(&path, 64, 2).unwrap();
        assert!(matches!(
            medium.read_block(0),
            Err(BlockError::UnwrittenBlock { .. })
        ));
        medium.write_block(0, b"value").unwrap();
        medium.flush().unwrap();
        let mut file = OpenOptions::new()
            .read(true)
            .write(true)
            .open(&path)
            .unwrap();
        file.seek(SeekFrom::Start((HEADER_BYTES + 1) as u64))
            .unwrap();
        file.write_all(b"X").unwrap();
        drop(file);
        assert!(matches!(
            medium.read_block(0),
            Err(BlockError::ChecksumMismatch { .. })
        ));
        fs::remove_file(path).unwrap();
    }

    #[test]
    fn malformed_header_is_rejected_before_payload_interpretation() {
        let path = temp_path("header");
        let mut medium = FileBlockMedium::create(&path, 64, 1).unwrap();
        medium.write_block(0, b"value").unwrap();
        medium.flush().unwrap();
        let mut file = OpenOptions::new()
            .read(true)
            .write(true)
            .open(&path)
            .unwrap();
        file.seek(SeekFrom::Start(0)).unwrap();
        file.write_all(b"NOPE").unwrap();
        drop(file);
        assert!(matches!(
            medium.read_block(0),
            Err(BlockError::InvalidHeader { index: 0 })
        ));
        fs::remove_file(path).unwrap();
    }

    #[test]
    fn truncated_block_is_rejected_as_io_shape_failure() {
        let path = temp_path("truncated");
        let mut medium = FileBlockMedium::create(&path, 64, 1).unwrap();
        medium.write_block(0, b"value").unwrap();
        medium.flush().unwrap();
        medium.file_mut().unwrap().set_len(8).unwrap();
        assert!(matches!(
            medium.read_block(0),
            Err(BlockError::TruncatedBlock {
                index: 0,
                actual: 8,
                expected: 64
            })
        ));
        fs::remove_file(path).unwrap();
    }

    #[test]
    fn identical_writes_have_identical_images() {
        let left = temp_path("left");
        let right = temp_path("right");
        for path in [&left, &right] {
            let mut medium = FileBlockMedium::create(path, 64, 2).unwrap();
            medium.write_block(0, b"A").unwrap();
            medium.write_block(1, b"B").unwrap();
            medium.flush().unwrap();
        }
        assert_eq!(fs::read(&left).unwrap(), fs::read(&right).unwrap());
        fs::remove_file(left).unwrap();
        fs::remove_file(right).unwrap();
    }

    #[test]
    fn flush_failure_is_explicit_and_not_silently_ignored() {
        let path = temp_path("flush-failure");
        let mut medium = FileBlockMedium::create(&path, 64, 1).unwrap();
        medium.write_block(0, b"value").unwrap();
        medium.close_for_test();
        assert!(matches!(
            medium.flush(),
            Err(BlockError::Io(message)) if message == "medium is closed"
        ));
        fs::remove_file(path).unwrap();
    }

    #[test]
    fn write_failure_is_explicit_and_not_silently_ignored() {
        let path = temp_path("write-failure");
        let mut medium = FileBlockMedium::create(&path, 64, 1).unwrap();
        medium.close_for_test();
        assert!(matches!(
            medium.write_block(0, b"value"),
            Err(BlockError::Io(message)) if message == "medium is closed"
        ));
        fs::remove_file(path).unwrap();
    }
}
