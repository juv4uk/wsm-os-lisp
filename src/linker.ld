ENTRY(_start)

SECTIONS {
    . = 0x100000; /* 1MB load address */

    .text : ALIGN(4K) {
        *(.text .text.*)
    }

    .rodata : ALIGN(4K) {
        *(.rodata .rodata.*)
    }

    .bootloader-config : ALIGN(1) {
        KEEP(*(.bootloader-config))
    }

    .data : ALIGN(4K) {
        *(.data .data.*)
    }

    .bss : ALIGN(4K) {
        *(COMMON)
        *(.bss .bss.*)
    }

    /DISCARD/ : {
        *(.comment)
        *(.note.*)
    }
}
