use cml::x86_freestanding::X86FreestandingBackend;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

const CAPSULE_SCHEMA: &str = "wsm-definition-capsule";
const CAPSULE_VERSION: u64 = 1;
const ASSEMBLER_FAMILY: &str = "gnu-as";
const OBJECT_CANONICALIZER: &str = "gnu-objcopy-remove-note-gnu-property";
const TARGET_TRIPLE: &str = "x86_64-unknown-none";
const OBJECT_FORMAT: &str = "elf64-x86-64";

fn sha256(data: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(data);
    hex::encode(hasher.finalize())
}

fn file_sha256(path: &Path) -> String {
    sha256(
        &fs::read(path)
            .unwrap_or_else(|error| panic!("failed to read {}: {error}", path.display())),
    )
}

fn compact_digest(value: &Value) -> String {
    sha256(&serde_json::to_vec(value).expect("JSON value must serialize"))
}

fn repository_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

fn canonical_source(root: &Path, fixture_name: &str) -> (PathBuf, Vec<u8>, String) {
    let path = root.join(format!("artifacts/{}.wsm", fixture_name));
    let bytes = fs::read(&path).expect("committed fixture.wsm must exist");
    let text = std::str::from_utf8(&bytes).expect("fixture.wsm must be UTF-8");
    let semantic = text.strip_suffix('\n').unwrap_or(text);
    if fixture_name == "fixture" {
        assert_eq!(
            semantic,
            wsm_os_target::FIRST_FIXTURE_SOURCE,
            "committed fixture.wsm must equal the target-contract fixture"
        );
    }
    let semantic = semantic.to_owned();
    (path, bytes, semantic)
}

fn inspect_symbols(object: &Path) -> (Vec<String>, Vec<String>, u64, u64) {
    let output = Command::new("nm")
        .args(["-S", "--defined-only"])
        .arg(object)
        .output()
        .expect("nm must be available");
    assert!(output.status.success(), "nm --defined-only failed");
    let defined = String::from_utf8(output.stdout).expect("nm output must be UTF-8");

    let mut exports = Vec::new();
    let mut entry_start = None;
    let mut entry_size = None;
    for line in defined.lines() {
        let parts: Vec<_> = line.split_whitespace().collect();
        if parts.len() != 4 || parts[2] != "T" {
            continue;
        }
        exports.push(parts[3].to_owned());
        if parts[3] == wsm_os_target::ENTRY_SYMBOL {
            entry_start = Some(u64::from_str_radix(parts[0], 16).expect("entry address is hex"));
            entry_size = Some(u64::from_str_radix(parts[1], 16).expect("entry size is hex"));
        }
    }
    exports.sort();

    let output = Command::new("nm")
        .arg(object)
        .output()
        .expect("nm must be available");
    assert!(output.status.success(), "nm failed");
    let symbols = String::from_utf8(output.stdout).expect("nm output must be UTF-8");
    let mut imports = Vec::new();
    for line in symbols.lines() {
        let parts: Vec<_> = line.split_whitespace().collect();
        if parts.len() == 2 && parts[0] == "U" {
            imports.push(parts[1].to_owned());
        }
    }
    imports.sort();

    assert_eq!(exports, [wsm_os_target::ENTRY_SYMBOL]);
    for import in &imports {
        assert!(
            wsm_os_target::RUNTIME_IMPORTS.contains(&import.as_str()),
            "import `{import}` is outside the ratified runtime allowlist"
        );
    }

    (
        exports,
        imports,
        entry_start.expect("wsm_entry must have an object-relative address"),
        entry_size.expect("wsm_entry must have a symbol size"),
    )
}

fn symbol_table() -> Value {
    json!([
        {"id": 1, "name": "A", "encoded_word": wsm_os_target::encode_symbol(1).unwrap()},
        {"id": 2, "name": "B", "encoded_word": wsm_os_target::encode_symbol(2).unwrap()}
    ])
}

fn literal_table() -> Value {
    json!([
        {"kind": "symbol", "symbol_id": 1, "encoded_word": wsm_os_target::encode_symbol(1).unwrap()},
        {"kind": "symbol", "symbol_id": 2, "encoded_word": wsm_os_target::encode_symbol(2).unwrap()}
    ])
}

fn build_metadata(
    fixture_name: &str,
    source_bytes: &[u8],
    semantic_source: &str,
    assembly: &Path,
    object: &Path,
) -> (Value, Value) {
    let root = repository_root();
    let contract_path = root.join("target-contract.wsm");
    let (exports, imports, entry_start, entry_size) = inspect_symbols(object);
    let source_file_digest = sha256(source_bytes);
    let semantic_source_digest = sha256(semantic_source.as_bytes());
    let assembly_digest = file_sha256(assembly);
    let object_digest = file_sha256(object);
    let target_contract_digest = file_sha256(&contract_path);
    let symbols = symbol_table();
    let literals = literal_table();
    let symbol_table_digest = compact_digest(&symbols);
    let literal_table_digest = compact_digest(&literals);

    let identity_material = json!({
        "schema": CAPSULE_SCHEMA,
        "schema_version": CAPSULE_VERSION,
        "source_semantic_sha256": semantic_source_digest,
        "entry": wsm_os_target::ENTRY_SYMBOL,
        "target_abi_schema": wsm_os_target::CONTRACT_SCHEMA,
        "target_abi_version": wsm_os_target::CONTRACT_VERSION,
        "my_lisp_contract": wsm_os_target::MY_LISP_CONTRACT,
        "my_lisp_revision": wsm_os_target::MY_LISP_SHA,
        "cml_supported_contract": wsm_os_target::CML_CLAIMED_CONTRACT,
        "cml_revision": wsm_os_target::CML_SHA
    });
    let definition_id = format!("sha256:{}", compact_digest(&identity_material));

    let manifest = json!({
        "schema": if fixture_name == "fixture" { "wsm-m4-artifact-manifest".to_string() } else { format!("wsm-{}-artifact-manifest", fixture_name) },
        "schema_version": 2,
        "digest_algorithm": "sha256",
        "source_semantic_digest": semantic_source_digest,
        "source_file_digest": source_file_digest,
        "cml_sha": wsm_os_target::CML_SHA,
        "target_contract_digest": target_contract_digest,
        "assembly_digest": assembly_digest,
        "object_digest": object_digest,
        "exported": exports,
        "imports": imports
    });

    let capsule = json!({
        "schema": CAPSULE_SCHEMA,
        "schema_version": CAPSULE_VERSION,
        "definition_id": definition_id,
        "digest_algorithm": "sha256",
        "source": {
            "path": format!("artifacts/{}.wsm", fixture_name),
            "file_digest": source_file_digest,
            "semantic_digest": semantic_source_digest,
            "map": [{
                "granularity": "definition",
                "source_start_byte": 0,
                "source_end_byte": semantic_source.len(),
                "generated_entry": wsm_os_target::ENTRY_SYMBOL,
                "object_start": entry_start,
                "object_end": entry_start + entry_size
            }]
        },
        "contracts": {
            "my_lisp": {
                "contract": wsm_os_target::MY_LISP_CONTRACT,
                "revision": wsm_os_target::MY_LISP_SHA
            },
            "cml": {
                "supported_contract": wsm_os_target::CML_CLAIMED_CONTRACT,
                "revision": wsm_os_target::CML_SHA
            },
            "target_abi": {
                "schema": wsm_os_target::CONTRACT_SCHEMA,
                "version": wsm_os_target::CONTRACT_VERSION,
                "digest": target_contract_digest
            }
        },
        "generator": {
            "name": env!("CARGO_PKG_NAME"),
            "version": env!("CARGO_PKG_VERSION"),
            "assembler_family": ASSEMBLER_FAMILY,
            "object_canonicalizer": OBJECT_CANONICALIZER,
            "target_triple": TARGET_TRIPLE,
            "object_format": OBJECT_FORMAT
        },
        "code": {
            "section": ".text",
            "range_kind": "object-relative",
            "start": entry_start,
            "end": entry_start + entry_size,
            "entry": wsm_os_target::ENTRY_SYMBOL,
            "exports": exports
        },
        "literal_table": {
            "digest": literal_table_digest,
            "entries": literals
        },
        "symbol_table": {
            "digest": symbol_table_digest,
            "entries": symbols
        },
        "callers": [],
        "dependencies": [],
        "imports": imports,
        "artifacts": {
            "assembly": {"path": format!("artifacts/{}.s", fixture_name), "digest": assembly_digest},
            "object": {"path": format!("artifacts/{}.o", fixture_name), "digest": object_digest}
        },
        "capabilities": {
            "inspectable_metadata": true,
            "hot_replacement": false,
            "loader": false,
            "world_image": false
        }
    });
    (manifest, capsule)
}

fn write_json(path: &Path, value: &Value) {
    let mut bytes = serde_json::to_vec_pretty(value).expect("JSON must serialize");
    bytes.push(b'\n');
    fs::write(path, bytes)
        .unwrap_or_else(|error| panic!("failed to write {}: {error}", path.display()));
}

fn generate(output_dir: &Path, fixture_name: &str) {
    fs::create_dir_all(output_dir).expect("output directory must be creatable");
    let root = repository_root();
    let (source_path, source_bytes, semantic_source) = canonical_source(&root, fixture_name);
    let output_source = output_dir.join(format!("{}.wsm", fixture_name));
    if source_path != output_source {
        fs::write(&output_source, &source_bytes).expect("fixture source copy must succeed");
    }

    let exprs = cml::parser::parse(&semantic_source).expect("fixture must parse");
    let program = cml::lower::lower_program_with_tail_calls(&exprs).expect("fixture must lower");
    let assembly_text = X86FreestandingBackend::new()
        .compile_program(&program)
        .expect("fixture must compile for x86_64-freestanding");
    let assembly = output_dir.join(format!("{}.s", fixture_name));
    fs::write(&assembly, assembly_text).expect("assembly write must succeed");

    let object = output_dir.join(format!("{}.o", fixture_name));
    let status = Command::new("as")
        .arg("-o")
        .arg(&object)
        .arg(&assembly)
        .status()
        .expect("GNU assembler must be available");
    assert!(status.success(), "assembler failed");
    let status = Command::new("objcopy")
        .arg("--remove-section=.note.gnu.property")
        .arg(&object)
        .status()
        .expect("GNU objcopy must be available");
    assert!(status.success(), "object canonicalization failed");

    let (manifest, capsule) = build_metadata(
        fixture_name,
        &source_bytes,
        &semantic_source,
        &assembly,
        &object,
    );
    write_json(
        &output_dir.join(format!("{}-manifest.json", fixture_name)),
        &manifest,
    );
    write_json(
        &output_dir.join(format!("{}-definition-capsule.json", fixture_name)),
        &capsule,
    );
}

fn verify(dir: &Path, fixture_name: &str) {
    let source_bytes =
        fs::read(dir.join(format!("{}.wsm", fixture_name))).expect("fixture source must exist");
    let source_text = std::str::from_utf8(&source_bytes).expect("fixture source must be UTF-8");
    let semantic_source = source_text.strip_suffix('\n').unwrap_or(source_text);
    if fixture_name == "fixture" {
        assert_eq!(semantic_source, wsm_os_target::FIRST_FIXTURE_SOURCE);
    }
    let (manifest, capsule) = build_metadata(
        fixture_name,
        &source_bytes,
        semantic_source,
        &dir.join(format!("{}.s", fixture_name)),
        &dir.join(format!("{}.o", fixture_name)),
    );
    let committed_manifest: Value = serde_json::from_slice(
        &fs::read(dir.join(format!("{}-manifest.json", fixture_name)))
            .expect("manifest must exist"),
    )
    .expect("manifest must be valid JSON");
    let committed_capsule: Value = serde_json::from_slice(
        &fs::read(dir.join(format!("{}-definition-capsule.json", fixture_name)))
            .expect("capsule must exist"),
    )
    .expect("capsule must be valid JSON");
    assert_eq!(committed_manifest, manifest, "artifact manifest mismatch");
    assert_eq!(committed_capsule, capsule, "definition capsule mismatch");
    println!("verified {}", dir.display());
}

fn main() {
    let fixture_name = env::var("WSM_FIXTURE").unwrap_or_else(|_| "fixture".to_string());
    let args: Vec<_> = env::args_os().skip(1).collect();
    match args.as_slice() {
        [] => generate(&repository_root().join("artifacts"), &fixture_name),
        [flag, directory] if flag == "--output-dir" => {
            generate(Path::new(directory), &fixture_name)
        }
        [flag, directory] if flag == "--verify" => verify(Path::new(directory), &fixture_name),
        _ => panic!("usage: WSM_FIXTURE=name m4-generator [--output-dir DIR | --verify DIR]"),
    }
}
