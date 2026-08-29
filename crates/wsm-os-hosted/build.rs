use std::env;
use std::fs;
use std::path::PathBuf;

use cml::x86_freestanding::X86FreestandingBackend;

fn main() {
    let expressions = cml::parser::parse(wsm_os_target::FIRST_FIXTURE_SOURCE)
        .expect("frozen fixture must parse");
    let program = cml::lower::lower_program(&expressions).expect("frozen fixture must be admitted");
    let assembly = X86FreestandingBackend::new()
        .compile_program(&program)
        .expect("frozen fixture must compile for wsm-os");
    let output = PathBuf::from(env::var_os("OUT_DIR").expect("OUT_DIR is set"));
    fs::write(output.join("fixture.s"), assembly).expect("write generated fixture assembly");
}
