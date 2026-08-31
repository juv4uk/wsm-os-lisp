//! Bounded F6 producer/consumer witness.
//!
//! Reads one canonical record per stdin line, stores it in the opaque block
//! medium, reopens the medium, and validates records through the generic
//! adapter. It does not evaluate or reconstruct WSM values.

use std::io::{self, Read};
use std::path::PathBuf;
use wsm_os_block::{BlockMedium, FileBlockMedium};
use wsm_os_fs_adapter::read_validated_image;

const BLOCK_SIZE: usize = 64 * 1024;
const BLOCK_COUNT: u64 = 2;
const MAX_INPUT_BYTES: usize = BLOCK_SIZE * BLOCK_COUNT as usize;

fn main() {
    let mut input = Vec::new();
    io::stdin()
        .take((MAX_INPUT_BYTES + 1) as u64)
        .read_to_end(&mut input)
        .expect("read stdin");
    if input.len() > MAX_INPUT_BYTES {
        eprintln!("wsm-fs-image-reader: input exceeds bounded image size");
        std::process::exit(2);
    }
    let records: Vec<&[u8]> = input
        .split(|byte| *byte == b'\n')
        .filter(|record| !record.is_empty())
        .collect();
    if records.len() != BLOCK_COUNT as usize {
        eprintln!(
            "wsm-fs-image-reader: expected exactly {} records, got {}",
            BLOCK_COUNT,
            records.len()
        );
        std::process::exit(2);
    }
    let path: PathBuf =
        std::env::temp_dir().join(format!("wsm-fs-image-reader-{}.img", std::process::id()));
    {
        let mut medium =
            FileBlockMedium::create(&path, BLOCK_SIZE, BLOCK_COUNT).expect("create image");
        for (index, record) in records.iter().enumerate() {
            medium
                .write_block(index as u64, record)
                .expect("write record");
        }
        medium.flush().expect("flush image");
    }
    let mut medium = FileBlockMedium::open(&path, BLOCK_SIZE, BLOCK_COUNT).expect("reopen image");
    let validated = read_validated_image(&mut medium, |_, bytes| {
        let text = std::str::from_utf8(bytes).map_err(|_| "record is not UTF-8".to_string())?;
        if text.starts_with("((format . wsm-fs-") {
            Ok(())
        } else {
            Err("record is not a WSM FS envelope".to_string())
        }
    })
    .unwrap_or_else(|error| {
        eprintln!("wsm-fs-image-reader: validation failed: {error:?}");
        std::process::exit(1);
    });
    if validated.len() != records.len() {
        eprintln!("wsm-fs-image-reader: record count changed after reopen");
        std::process::exit(1);
    }
    println!("f6-adapter-ok records={}", validated.len());
    let _ = std::fs::remove_file(path);
}
