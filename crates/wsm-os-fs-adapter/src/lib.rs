//! Read-only image adapter for the F6 filesystem witness.
//!
//! This layer extracts one opaque image record per validated block. It does
//! not parse, evaluate, or assign meaning to WSM values. Callers provide the
//! validator/reconstruction boundary.

use wsm_os_block::{BlockError, BlockMedium};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ImageError {
    Block(BlockError),
    EmptyImage,
    InvalidRecord { index: u64, reason: String },
}

impl From<BlockError> for ImageError {
    fn from(error: BlockError) -> Self {
        Self::Block(error)
    }
}

/// Read all non-empty image records without interpreting their payloads.
///
/// The validator is the explicit handoff to a higher-level WSM envelope
/// checker. A rejected record prevents any partial image from being returned.
pub fn read_validated_image<M, F>(
    medium: &mut M,
    mut validate_record: F,
) -> Result<Vec<Vec<u8>>, ImageError>
where
    M: BlockMedium,
    F: FnMut(u64, &[u8]) -> Result<(), String>,
{
    let mut records = Vec::new();
    for index in 0..medium.block_count() {
        match medium.read_block(index) {
            Ok(record) => {
                validate_record(index, &record)
                    .map_err(|reason| ImageError::InvalidRecord { index, reason })?;
                records.push(record);
            }
            Err(BlockError::UnwrittenBlock { .. }) => continue,
            Err(error) => return Err(error.into()),
        }
    }
    if records.is_empty() {
        return Err(ImageError::EmptyImage);
    }
    Ok(records)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::path::PathBuf;
    use wsm_os_block::{BlockMedium, FileBlockMedium};

    fn temp_path(name: &str) -> PathBuf {
        std::env::temp_dir().join(format!("wsm-os-fs-adapter-{name}-{}", std::process::id()))
    }

    #[test]
    fn reads_validated_records_after_reopen() {
        let path = temp_path("round-trip");
        {
            let mut medium = FileBlockMedium::create(&path, 64, 2).unwrap();
            medium.write_block(0, b"root-envelope").unwrap();
            medium.write_block(1, b"object-envelope").unwrap();
            medium.flush().unwrap();
        }
        let mut medium = FileBlockMedium::open(&path, 64, 2).unwrap();
        let records = read_validated_image(&mut medium, |_, bytes| {
            if bytes.ends_with(b"-envelope") {
                Ok(())
            } else {
                Err("not an envelope".into())
            }
        })
        .unwrap();
        assert_eq!(
            records,
            vec![b"root-envelope".to_vec(), b"object-envelope".to_vec()]
        );
        fs::remove_file(path).unwrap();
    }

    #[test]
    fn validator_rejection_is_atomic() {
        let path = temp_path("reject");
        let mut medium = FileBlockMedium::create(&path, 64, 2).unwrap();
        medium.write_block(0, b"valid-envelope").unwrap();
        medium.write_block(1, b"bad").unwrap();
        let result = read_validated_image(&mut medium, |_, bytes| {
            if bytes.ends_with(b"-envelope") {
                Ok(())
            } else {
                Err("invalid envelope".into())
            }
        });
        assert!(matches!(
            result,
            Err(ImageError::InvalidRecord { index: 1, .. })
        ));
        fs::remove_file(path).unwrap();
    }
}
