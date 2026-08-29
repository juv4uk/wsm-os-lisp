use cml::x86_freestanding::X86FreestandingBackend;
use sha2::{Digest, Sha256};
use std::fs;
use std::path::Path;
use std::process::Command;

fn file_sha(path: &Path) -> String {
    let data = fs::read(path).unwrap();
    let mut hasher = Sha256::new();
    hasher.update(&data);
    hex::encode(hasher.finalize())
}

fn data_sha(data: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(data);
    hex::encode(hasher.finalize())
}

fn main() {
    let artifacts_dir = Path::new("artifacts");
    fs::create_dir_all(artifacts_dir).unwrap();

    let source = wsm_os_target::FIRST_FIXTURE_SOURCE;
    let source_digest = data_sha(source.as_bytes());

    let exprs = cml::parser::parse(source).unwrap();
    let program = cml::lower::lower_program(&exprs).unwrap();
    let assembly_str = X86FreestandingBackend::new()
        .compile_program(&program)
        .unwrap();

    let asm_path = artifacts_dir.join("fixture.s");
    fs::write(&asm_path, &assembly_str).unwrap();

    // CML revision comes from the target contract constant, which is always
    // equal to the Cargo dependency pin in Cargo.toml. This makes the
    // generator self-contained: no dependency on a sibling ../cml checkout.
    let cml_sha = wsm_os_target::CML_SHA.to_string();

    let target_contract_sha = {
        let output = Command::new("git")
            .arg("hash-object")
            .arg("target-contract.wsm")
            .output()
            .unwrap();
        String::from_utf8_lossy(&output.stdout).trim().to_string()
    };

    let obj_path = artifacts_dir.join("fixture.o");

    let status = Command::new("as")
        .arg("-o")
        .arg(&obj_path)
        .arg(&asm_path)
        .status()
        .unwrap();
    assert!(status.success(), "assembler failed");

    let obj_digest = file_sha(&obj_path);
    let asm_digest = file_sha(&asm_path);

    let nm_output = Command::new("nm").arg(&obj_path).output().unwrap();
    assert!(nm_output.status.success());
    let nm_str = String::from_utf8_lossy(&nm_output.stdout);

    let mut exports = Vec::new();
    let mut imports = Vec::new();

    for line in nm_str.lines() {
        let parts: Vec<&str> = line.split_whitespace().collect();
        if parts.len() == 3 {
            let symbol_type = parts[1];
            let name = parts[2];
            if symbol_type == "T" {
                exports.push(name.to_string());
            }
        } else if parts.len() == 2 {
            let symbol_type = parts[0];
            let name = parts[1];
            if symbol_type == "U" {
                imports.push(name.to_string());
            }
        }
    }

    assert_eq!(exports, vec!["wsm_entry"]);

    // Enforce exact membership in the ratified runtime import allowlist.
    // A prefix-only check (starts_with "wsm_") would admit stray symbols
    // like `wsm_destroy_os` without failing the gate. The allowlist is the
    // canonical source of truth from wsm_os_target::RUNTIME_IMPORTS.
    let allowlist = wsm_os_target::RUNTIME_IMPORTS;
    for imp in &imports {
        assert!(
            allowlist.contains(&imp.as_str()),
            "import `{imp}` is not in the ratified RUNTIME_IMPORTS allowlist; \
             add it to wsm_os_target if this is intentional"
        );
    }

    // Sort imports for determinism
    imports.sort();

    let manifest = serde_json::json!({
        "source_digest": source_digest,
        "cml_sha": cml_sha,
        "target_contract_sha": target_contract_sha,
        "assembly_digest": asm_digest,
        "object_digest": obj_digest,
        "exported": exports,
        "imports": imports
    });

    let manifest_path = artifacts_dir.join("manifest.json");
    fs::write(
        &manifest_path,
        serde_json::to_string_pretty(&manifest).unwrap(),
    )
    .unwrap();

    println!("Artifact bundle generated at artifacts/");
}
