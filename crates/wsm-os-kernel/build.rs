use std::env;
use std::path::PathBuf;

fn main() {
    let manifest_dir = PathBuf::from(env::var_os("CARGO_MANIFEST_DIR").unwrap());
    let object = manifest_dir.join("../../artifacts/fixture.o");

    println!("cargo:rerun-if-changed={}", object.display());
    println!("cargo:rustc-link-arg={}", object.display());
}
