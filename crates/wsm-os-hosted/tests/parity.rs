use std::process::Command;
use std::fs;
use std::path::Path;

#[test]
fn frozen_fixture_matches_pinned_oracle_value() {
    let output = Command::new(env!("CARGO_BIN_EXE_wsm-os-hosted"))
        .output()
        .expect("run hosted harness");
    assert!(
        output.status.success(),
        "hosted harness failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    
    // Check against independent pinned oracle evidence instead of target-contract constant
    let manifest_dir = env!("CARGO_MANIFEST_DIR");
    let workspace_dir = Path::new(manifest_dir).parent().unwrap().parent().unwrap();
    let oracle_path = workspace_dir.join("artifacts/oracle-transcript.txt");
    
    let oracle_expected = fs::read_to_string(&oracle_path)
        .expect("failed to read oracle transcript")
        .trim()
        .to_string();

    assert_eq!(
        String::from_utf8(output.stdout).unwrap().trim(),
        oracle_expected
    );
}
