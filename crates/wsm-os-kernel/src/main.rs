#![no_std]
#![no_main]

use bootloader_api::{entry_point, BootInfo};
use core::arch::asm;
use core::panic::PanicInfo;

entry_point!(kernel_main);

fn kernel_main(_boot_info: &'static mut BootInfo) -> ! {
    serial_init();
    serial_write(b"WSM-OS BOOT schema=1 arch=x86_64 status=ok\n");
    qemu_exit(0x10)
}

#[panic_handler]
fn panic(_info: &PanicInfo) -> ! {
    serial_init();
    serial_write(b"WSM-OS PANIC schema=1 arch=x86_64 status=panic\n");
    qemu_exit(0x11)
}

const COM1: u16 = 0x3f8;

fn serial_init() {
    unsafe {
        outb(COM1 + 1, 0x00);
        outb(COM1 + 3, 0x80);
        outb(COM1, 0x03);
        outb(COM1 + 1, 0x00);
        outb(COM1 + 3, 0x03);
        outb(COM1 + 2, 0xc7);
        outb(COM1 + 4, 0x0b);
    }
}

fn serial_write(bytes: &[u8]) {
    for &byte in bytes {
        unsafe { outb(COM1, byte) };
    }
}

fn qemu_exit(code: u32) -> ! {
    unsafe {
        asm!("out dx, eax", in("dx") 0xf4_u16, in("eax") code, options(nomem, nostack));
    }
    loop {
        core::hint::spin_loop();
    }
}

unsafe fn outb(port: u16, value: u8) {
    asm!("out dx, al", in("dx") port, in("al") value, options(nomem, nostack));
}
