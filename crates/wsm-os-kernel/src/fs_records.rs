// Bounded parser for the data-only WSM FS record stream used by the guest.
// This deliberately validates structure, not execution semantics.

pub const MAX_RECORD_BYTES: usize = 16 * 1024;
pub const MAX_RECORDS: usize = 64;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum RecordKind {
    Root,
    Object,
    Journal,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Record<'a> {
    pub kind: RecordKind,
    pub bytes: &'a [u8],
}

#[derive(Debug, PartialEq, Eq)]
pub struct Stream<'a> {
    pub records: [Option<Record<'a>>; MAX_RECORDS],
    pub count: usize,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct RootView<'a> {
    pub revision: &'a [u8],
    pub object_address: &'a [u8],
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
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
    if stream.count > 2 {
        let journal = stream.records[2].ok_or(ParseError::InvalidRecord)?;
        if journal.kind != RecordKind::Journal
            || !contains(journal.bytes, b"(from . 0)")
            || !contains(journal.bytes, b"(to . 1)")
            || !contains(journal.bytes, b"(event publish-root)")
        {
            return Err(ParseError::InvalidRecord);
        }
    }
    Ok(())
}

/// Reconstruct the bounded root view only when every referenced object is
/// present. This is the guest-side missing-object rejection boundary.
pub fn reconstruct_root<'a>(stream: &'a Stream<'a>) -> Result<RootView<'a>, ParseError> {
    validate_references(stream)?;
    let root = stream.records[0].ok_or(ParseError::InvalidRecord)?;
    let object = stream.records[1].ok_or(ParseError::InvalidRecord)?;
    let revision =
        quoted_or_atom_after(root.bytes, b"(revision . ").ok_or(ParseError::InvalidRecord)?;
    let object_address =
        quoted_after(object.bytes, b"(address . ").ok_or(ParseError::InvalidRecord)?;
    Ok(RootView {
        revision,
        object_address,
    })
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
    } else if record.starts_with(b"((format . wsm-fs-journal)") {
        if !contains(record, b"(from . ")
            || !contains(record, b"(to . ")
            || !contains(record, b"(event ")
        {
            return Err(ParseError::InvalidRecord);
        }
        Ok(RecordKind::Journal)
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

fn quoted_or_atom_after<'a>(record: &'a [u8], marker: &[u8]) -> Option<&'a [u8]> {
    let offset = record
        .windows(marker.len())
        .position(|window| window == marker)?
        + marker.len();
    let rest = &record[offset..];
    let end = rest.iter().position(|byte| *byte == b')')?;
    let value = &rest[..end];
    if value.is_empty() || value.iter().any(|byte| *byte == b'(' || *byte == b'\n') {
        None
    } else {
        Some(value)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const VALID: &[u8] = b"((format . wsm-fs-root) (version 0 1) (revision . 1) (bindings (\"code\" . \"(hello world)\")) (objects \"(hello world)\"))\n((format . wsm-fs-object) (version 0 1) (address . \"(hello world)\") (value hello world))\n((format . wsm-fs-journal) (version 0 1) (from . 0) (to . 1) (event publish-root))\n";

    #[test]
    fn accepts_bounded_data_only_stream() {
        let stream = parse(VALID).unwrap();
        assert_eq!(stream.count, 3);
        assert_eq!(stream.records[0].unwrap().kind, RecordKind::Root);
        assert_eq!(stream.records[1].unwrap().kind, RecordKind::Object);
        assert_eq!(stream.records[2].unwrap().kind, RecordKind::Journal);
        validate_references(&stream).unwrap();
        let root = reconstruct_root(&stream).unwrap();
        assert_eq!(root.revision, b"1");
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
        assert_eq!(reconstruct_root(&stream), Err(ParseError::InvalidRecord));
    }

    #[test]
    fn rejects_corrupted_journal_transition() {
        let text = core::str::from_utf8(VALID)
            .unwrap()
            .replace("(event publish-root)", "(event publish-unknown)");
        let stream = parse(text.as_bytes()).unwrap();
        assert_eq!(reconstruct_root(&stream), Err(ParseError::InvalidRecord));
    }
}
