use std::process::Command;

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
    assert_eq!(
        String::from_utf8(output.stdout).unwrap().trim(),
        wsm_os_target::FIRST_FIXTURE_EXPECTED
    );
}
