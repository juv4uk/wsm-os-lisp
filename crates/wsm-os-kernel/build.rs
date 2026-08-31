use std::env;
use std::path::PathBuf;

fn main() {
    let manifest_dir = PathBuf::from(env::var_os("CARGO_MANIFEST_DIR").unwrap());
    let fixture = env::var("WSM_FIXTURE").unwrap_or_else(|_| "fixture".to_string());
    let object_name = if fixture == "fs-fixture" {
        "fixture.o".to_string()
    } else {
        format!("{fixture}.o")
    };
    let object = manifest_dir.join("../../artifacts").join(object_name);

    println!("cargo:rustc-env=WSM_FIXTURE={}", fixture);
    println!("cargo:rerun-if-env-changed=WSM_FIXTURE");
    println!("cargo:rerun-if-changed={}", object.display());
    println!("cargo:rustc-link-arg={}", object.display());
}
