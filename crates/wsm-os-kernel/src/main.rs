#![no_std]
#![no_main]

use core::panic::PanicInfo;
use bootloader::entry_point;

entry_point!(kernel_main);

fn kernel_main(_boot_info: &'static bootloader::BootInfo) -> ! {
    loop {}
}

#[panic_handler]
fn panic(_info: &PanicInfo) -> ! {
    loop {}
}
