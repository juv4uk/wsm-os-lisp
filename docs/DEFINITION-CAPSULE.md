# Definition capsule v1

`artifacts/definition-capsule.json` is inspectable metadata for the first
compiled WSM definition. It identifies evidence; it is not a loader, world
image, or authorization for hot replacement.

## Stable identity

`definition_id` is `sha256:` plus the SHA-256 of compact JSON containing, in
serde_json's deterministic key order:

```text
schema + schema_version
source semantic SHA-256
entry symbol
target ABI schema + version
my-lisp contract + revision
CML supported contract + revision
```

The definition ID deliberately excludes machine-code bytes. Recompiling the
same admitted definition for the same semantic contracts preserves identity;
assembly and object digests still detect implementation drift.

## Digest boundary

All capsule and manifest digests are SHA-256. Source has two distinct digests:

- `file_digest` covers the committed `fixture.wsm` bytes, including its final
  newline;
- `semantic_digest` covers the exact source admitted by CML, without that
  repository formatting newline.

Code ranges are object-relative `.text` offsets, not runtime addresses. The
literal and symbol-table digests cover compact JSON encodings of their
committed entries.

## Verification

`scripts/check-definition-capsule.sh`:

1. regenerates the complete bundle twice from pinned CML;
2. requires byte-identical source, assembly, object, manifest and capsule;
3. compares all regenerated files with the committed bundle;
4. independently recomputes capsule sections and artifact digests;
5. proves that a deliberately altered capsule is rejected.

The hosted harness copies the committed assembly while the kernel links the
committed object. The regeneration gate proves both belong to the same
definition bundle.
