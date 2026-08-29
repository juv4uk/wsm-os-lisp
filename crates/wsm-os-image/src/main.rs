use std::env;
use std::path::PathBuf;

fn main() {
    let mut args = env::args_os().skip(1);
    let kernel = args.next().map(PathBuf::from).unwrap_or_else(|| usage());
    let image = args.next().map(PathBuf::from).unwrap_or_else(|| usage());
    if args.next().is_some() {
        usage();
    }

    if !kernel.is_file() {
        panic!("kernel ELF does not exist: {}", kernel.display());
    }

    if let Some(parent) = image.parent() {
        std::fs::create_dir_all(parent).expect("failed to create image output directory");
    }

    bootloader::UefiBoot::new(&kernel)
        .create_disk_image(&image)
        .expect("failed to create UEFI disk image");

    println!("{}", image.display());
}

fn usage() -> ! {
    eprintln!("usage: wsm-os-image <kernel-elf> <uefi-image>");
    std::process::exit(2);
}
