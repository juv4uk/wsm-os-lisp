//! Bounded byte-level medium for WSM filesystem experiments.
//!
//! This crate knows nothing about WSM values, names, roots, journals, or
//! evaluation. It provides fixed-size blocks with a versioned data header,
//! checksum validation, and explicit flush.
//!
//! Це лише механізм байтового сховища. Семантика WSM FS лишається в
//! `my-lisp`; цей crate не знає про імена, roots, journal або виконання.

use std::collections::BTreeMap;
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

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CapabilityError {
    UnknownMedium(String),
    GeometryExceedsGrant,
    PathOutsideBrokerRoot,
}

/// A broker-issued grant. Callers cannot construct one without the broker.
#[derive(Debug, Clone)]
pub struct BlockCapability {
    logical_id: String,
    path: PathBuf,
    block_size: usize,
    block_count: u64,
}

impl BlockCapability {
    pub fn logical_id(&self) -> &str {
        &self.logical_id
    }

    pub fn block_size(&self) -> usize {
        self.block_size
    }

    pub fn block_count(&self) -> u64 {
        self.block_count
    }
}

/// Minimal hosted capability broker. It issues bounded grants for registered
/// logical media; it does not interpret WSM payloads.
#[derive(Debug, Clone)]
pub struct BlockCapabilityBroker {
    root: PathBuf,
    media: BTreeMap<String, PathBuf>,
}

impl BlockCapabilityBroker {
    pub fn new(root: impl AsRef<Path>) -> Self {
        Self {
            root: root.as_ref().to_path_buf(),
            media: BTreeMap::new(),
        }
    }

    pub fn register(&mut self, logical_id: impl Into<String>, relative_path: impl AsRef<Path>) {
        self.media
            .insert(logical_id.into(), self.root.join(relative_path.as_ref()));
    }

    pub fn issue(
        &self,
        logical_id: &str,
        block_size: usize,
        block_count: u64,
    ) -> Result<BlockCapability, CapabilityError> {
        let path = self
            .media
            .get(logical_id)
            .ok_or_else(|| CapabilityError::UnknownMedium(logical_id.to_string()))?;
        if !safe_child_path(&self.root, path) {
            return Err(CapabilityError::PathOutsideBrokerRoot);
        }
        if block_size < HEADER_BYTES
            || block_size > MAX_BLOCK_SIZE
            || block_count == 0
            || block_count > usize::MAX as u64
        {
            return Err(CapabilityError::GeometryExceedsGrant);
        }
        Ok(BlockCapability {
            logical_id: logical_id.to_string(),
            path: path.clone(),
            block_size,
            block_count,
        })
    }

    pub fn open(&self, capability: &BlockCapability) -> Result<FileBlockMedium, BlockError> {
        if !safe_child_path(&self.root, &capability.path)
            || capability.block_size < HEADER_BYTES
            || capability.block_size > MAX_BLOCK_SIZE
            || capability.block_count == 0
        {
            return Err(BlockError::InvalidGeometry);
        }
        FileBlockMedium::open(
            &capability.path,
            capability.block_size,
            capability.block_count,
        )
    }
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
    #[cfg(test)]
    injected_partial_write: Option<usize>,
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
            #[cfg(test)]
            injected_partial_write: None,
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
            #[cfg(test)]
            injected_partial_write: None,
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

    #[cfg(test)]
    fn inject_partial_write_for_test(&mut self, bytes: usize) {
        self.injected_partial_write = Some(bytes);
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
        #[cfg(test)]
        if let Some(prefix_bytes) = self.injected_partial_write.take() {
            let written = prefix_bytes.min(raw.len());
            self.file_mut()?.write_all(&raw[..written])?;
            return Err(BlockError::Io("injected partial write".to_string()));
        }
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

fn safe_child_path(root: &Path, path: &Path) -> bool {
    path.strip_prefix(root)
        .map(|relative| {
            !relative.is_absolute()
                && relative
                    .components()
                    .all(|component| !matches!(component, std::path::Component::ParentDir))
        })
        .unwrap_or(false)
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
    fn flushed_block_survives_reopen() {
        let path = temp_path("reopen");
        {
            let mut medium = FileBlockMedium::create(&path, 64, 1).unwrap();
            medium.write_block(0, b"reopen-me").unwrap();
            medium.flush().unwrap();
        }
        let mut reopened = FileBlockMedium::open(&path, 64, 1).unwrap();
        assert_eq!(reopened.read_block(0).unwrap(), b"reopen-me");
        fs::remove_file(path).unwrap();
    }

    #[test]
    fn partially_persisted_block_is_rejected() {
        let path = temp_path("partial");
        let medium = FileBlockMedium::create(&path, 64, 1).unwrap();
        drop(medium);
        let mut file = OpenOptions::new().write(true).open(&path).unwrap();
        file.seek(SeekFrom::Start(0)).unwrap();
        file.write_all(&MAGIC[..2]).unwrap();
        file.sync_data().unwrap();
        drop(file);

        let mut reopened = FileBlockMedium::open(&path, 64, 1).unwrap();
        assert!(matches!(
            reopened.read_block(0),
            Err(BlockError::InvalidHeader { index: 0 })
        ));
        fs::remove_file(path).unwrap();
    }

    #[test]
    fn injected_partial_write_is_explicit_and_rejected_on_reopen() {
        let path = temp_path("injected-partial");
        let mut medium = FileBlockMedium::create(&path, 64, 1).unwrap();
        medium.inject_partial_write_for_test(2);
        assert!(matches!(
            medium.write_block(0, b"fault"),
            Err(BlockError::Io(message)) if message == "injected partial write"
        ));
        drop(medium);

        let mut reopened = FileBlockMedium::open(&path, 64, 1).unwrap();
        assert!(matches!(
            reopened.read_block(0),
            Err(BlockError::InvalidHeader { index: 0 })
        ));
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

    #[test]
    fn capability_broker_rejects_unknown_medium_and_bad_geometry() {
        let root = std::env::temp_dir().join(format!("wsm-os-capability-{}", std::process::id()));
        let mut broker = BlockCapabilityBroker::new(&root);
        broker.register("oracle", "oracle.blocks");
        assert!(matches!(
            broker.issue("missing", 64, 1),
            Err(CapabilityError::UnknownMedium(name)) if name == "missing"
        ));
        assert!(matches!(
            broker.issue("oracle", HEADER_BYTES - 1, 1),
            Err(CapabilityError::GeometryExceedsGrant)
        ));
    }

    #[test]
    fn capability_broker_issues_bounded_grant_and_opens_registered_medium() {
        let root =
            std::env::temp_dir().join(format!("wsm-os-capability-open-{}", std::process::id()));
        fs::create_dir_all(&root).unwrap();
        let path = root.join("oracle.blocks");
        let _created = FileBlockMedium::create(&path, 64, 1).unwrap();
        let mut broker = BlockCapabilityBroker::new(&root);
        broker.register("oracle", "oracle.blocks");
        let grant = broker.issue("oracle", 64, 1).unwrap();
        assert_eq!(grant.logical_id(), "oracle");
        let mut medium = broker.open(&grant).unwrap();
        medium.write_block(0, b"granted").unwrap();
        medium.flush().unwrap();
        assert_eq!(medium.read_block(0).unwrap(), b"granted");
        fs::remove_file(path).unwrap();
        fs::remove_dir(root).unwrap();
    }

    #[test]
    fn capability_broker_rejects_path_escape_registration() {
        let root =
            std::env::temp_dir().join(format!("wsm-os-capability-escape-{}", std::process::id()));
        let mut broker = BlockCapabilityBroker::new(&root);
        broker.register("escape", "../outside.blocks");
        assert!(matches!(
            broker.issue("escape", 64, 1),
            Err(CapabilityError::PathOutsideBrokerRoot)
        ));
    }
}
