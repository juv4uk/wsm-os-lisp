use std::fs;
use std::path::Path;
use std::process::Command;

#[test]
fn frozen_fixture_matches_pinned_oracle_value() {
    let output = Command::new(env!("CARGO_BIN_EXE_wsm-os-hosted"))
        .output()
        .expect("run hosted harness");

    let manifest_dir = env!("CARGO_MANIFEST_DIR");
    let workspace_dir = Path::new(manifest_dir).parent().unwrap().parent().unwrap();
    let transcript_path = std::env::var("WSM_ORACLE_TRANSCRIPT")
        .unwrap_or_else(|_| "artifacts/oracle-transcript.txt".to_string());
    let oracle_path = workspace_dir.join(transcript_path);

    let oracle_expected = fs::read_to_string(&oracle_path)
        .expect("failed to read oracle transcript")
        .trim()
        .to_string();

    let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();

    if !output.status.success() {
        assert_eq!(
            stderr, oracle_expected,
            "stderr should match oracle transcript on failure"
        );
    } else {
        assert_eq!(
            stdout, oracle_expected,
            "stdout should match oracle transcript on success"
        );
    }
}
