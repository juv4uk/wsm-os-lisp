use std::env;
use std::fs;
use std::path::PathBuf;

fn main() {
    let manifest_dir = PathBuf::from(env::var_os("CARGO_MANIFEST_DIR").expect("manifest dir"));
    let fixture = env::var("WSM_FIXTURE").unwrap_or_else(|_| "fixture".to_string());
    let assembly = manifest_dir.join(format!("../../artifacts/{}.s", fixture));
    let output = PathBuf::from(env::var_os("OUT_DIR").expect("OUT_DIR is set"));
    
    println!("cargo:rerun-if-env-changed=WSM_FIXTURE");
    println!("cargo:rerun-if-changed={}", assembly.display());
    fs::copy(&assembly, output.join("fixture.s")).expect("copy committed fixture assembly");
}
