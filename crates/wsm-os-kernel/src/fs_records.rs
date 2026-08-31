//! Bounded parser for the data-only WSM FS record stream used by the guest.
//! This deliberately validates structure, not execution semantics.

#![allow(dead_code)]

pub const MAX_RECORD_BYTES: usize = 16 * 1024;
pub const MAX_RECORDS: usize = 64;

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum RecordKind {
    Root,
    Object,
}

#[derive(Clone, Copy)]
pub struct Record<'a> {
    pub kind: RecordKind,
    pub bytes: &'a [u8],
}

pub struct Stream<'a> {
    pub records: [Option<Record<'a>>; MAX_RECORDS],
    pub count: usize,
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum ParseError {
    Empty,
    TooLarge,
    TooManyRecords,
    UnterminatedRecord,
    InvalidRecord,
    UnsupportedVersion,
}

pub fn parse(bytes: &[u8]) -> Result<Stream<'_>, ParseError> {
    if bytes.is_empty() {
        return Err(ParseError::Empty);
    }
    if bytes.len() > MAX_RECORD_BYTES {
        return Err(ParseError::TooLarge);
    }
    let mut records = [None; MAX_RECORDS];
    let mut count = 0;
    let mut start = 0;
    while start < bytes.len() {
        let Some(relative_end) = bytes[start..].iter().position(|byte| *byte == b'\n') else {
            return Err(ParseError::UnterminatedRecord);
        };
        let end = start + relative_end;
        let record = &bytes[start..end];
        if record.is_empty() || count == MAX_RECORDS {
            return Err(if count == MAX_RECORDS {
                ParseError::TooManyRecords
            } else {
                ParseError::InvalidRecord
            });
        }
        let kind = classify(record)?;
        records[count] = Some(Record {
            kind,
            bytes: record,
        });
        count += 1;
        start = end + 1;
    }
    Ok(Stream { records, count })
}

/// Check the minimal cross-record reference invariant for the F6 envelope:
/// the root's object reference must be present as an object address. This is
/// deliberately content-level validation; cryptographic addressing is Q3.
pub fn validate_references(stream: &Stream<'_>) -> Result<(), ParseError> {
    if stream.count < 2 {
        return Err(ParseError::InvalidRecord);
    }
    let root = stream.records[0].ok_or(ParseError::InvalidRecord)?;
    let object = stream.records[1].ok_or(ParseError::InvalidRecord)?;
    if root.kind != RecordKind::Root || object.kind != RecordKind::Object {
        return Err(ParseError::InvalidRecord);
    }
    let root_ref = quoted_after(root.bytes, b"(objects ").ok_or(ParseError::InvalidRecord)?;
    let object_address =
        quoted_after(object.bytes, b"(address . ").ok_or(ParseError::InvalidRecord)?;
    if root_ref != object_address {
        return Err(ParseError::InvalidRecord);
    }
    Ok(())
}

fn classify(record: &[u8]) -> Result<RecordKind, ParseError> {
    // Envelope grammar is intentionally narrow and data-only at this stage.
    // Every accepted record must declare the same version tuple.
    if !record.starts_with(b"((format . wsm-fs-")
        || !record
            .windows(b"(version 0 1)".len())
            .any(|window| window == b"(version 0 1)")
        || !record.ends_with(b"))")
    {
        return Err(ParseError::InvalidRecord);
    }
    if record.starts_with(b"((format . wsm-fs-root)") {
        if !contains(record, b"(revision . ")
            || !contains(record, b"(bindings ")
            || !contains(record, b"(objects ")
        {
            return Err(ParseError::InvalidRecord);
        }
        Ok(RecordKind::Root)
    } else if record.starts_with(b"((format . wsm-fs-object)") {
        if !contains(record, b"(address . ") || !contains(record, b"(value ") {
            return Err(ParseError::InvalidRecord);
        }
        Ok(RecordKind::Object)
    } else {
        Err(ParseError::InvalidRecord)
    }
}

fn contains(haystack: &[u8], needle: &[u8]) -> bool {
    haystack
        .windows(needle.len())
        .any(|window| window == needle)
}

fn quoted_after<'a>(record: &'a [u8], marker: &[u8]) -> Option<&'a [u8]> {
    let offset = record
        .windows(marker.len())
        .position(|window| window == marker)?
        + marker.len();
    let rest = &record[offset..];
    if rest.first().copied()? != b'"' {
        return None;
    }
    let end = rest[1..].iter().position(|byte| *byte == b'"')? + 1;
    Some(&rest[1..end])
}

#[cfg(test)]
mod tests {
    use super::*;

    const VALID: &[u8] = b"((format . wsm-fs-root) (version 0 1) (revision . 1) (bindings (\"code\" . \"(hello world)\")) (objects \"(hello world)\"))\n((format . wsm-fs-object) (version 0 1) (address . \"(hello world)\") (value hello world))\n";

    #[test]
    fn accepts_bounded_data_only_stream() {
        let stream = parse(VALID).unwrap();
        assert_eq!(stream.count, 2);
        assert_eq!(stream.records[0].unwrap().kind, RecordKind::Root);
        assert_eq!(stream.records[1].unwrap().kind, RecordKind::Object);
        validate_references(&stream).unwrap();
    }

    #[test]
    fn rejects_unknown_format_and_truncation() {
        assert_eq!(
            parse(b"((format . wsm-fs-code) (version 0 1))\n"),
            Err(ParseError::InvalidRecord)
        );
        assert_eq!(
            parse(&VALID[..VALID.len() - 1]),
            Err(ParseError::UnterminatedRecord)
        );
    }

    #[test]
    fn rejects_dangling_object_reference() {
        let text = core::str::from_utf8(VALID)
            .unwrap()
            .replace("(address . \"(hello world)\")", "(address . \"other\")");
        let stream = parse(text.as_bytes()).unwrap();
        assert_eq!(validate_references(&stream), Err(ParseError::InvalidRecord));
    }
}
