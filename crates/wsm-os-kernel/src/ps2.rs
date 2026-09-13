// PS/2 8042 keyboard substrate for the GOP REPL console. Raw port I/O only;
// no interrupt handling. Scancodes decoded in set 1 (US layout).
//
// The 8042 is a byte-level legacy device: firmware leaves it in a working
// state after ExitBootServices, so this substrate only reads the output
// buffer and decodes scancodes; it performs no command/ack handshake.

use crate::inb;

const PS2_DATA: u16 = 0x60;
const PS2_STATUS: u16 = 0x64;

const STATUS_OUTPUT_FULL: u8 = 0x01;
const STATUS_MOUSE_DATA: u8 = 0x20;

const EXTENDED_PREFIX: u8 = 0xE0;

// Shift make codes: left 0x2A, right 0x36. Break = code | 0x80.
const SHIFT_KEY_L: u8 = 0x2A;
const SHIFT_KEY_R: u8 = 0x36;

// Scancode set 1 to ASCII, US layout, unshifted. 0 = modifier/navigation.
const SCAN_UNSHIFT: [u8; 128] = [
    0x00, 0x00, b'1', b'2', b'3', b'4', b'5', b'6', b'7', b'8', b'9', b'0', b'-', b'=', 0x08, 0x09,
    b'q', b'w', b'e', b'r', b't', b'y', b'u', b'i', b'o', b'p', b'[', b']', 0x0D, 0x00, 0x00, b'a',
    b's', b'd', b'f', b'g', b'h', b'j', b'k', b'l', b';', b'\'', b'`', 0x00, b'\\', b'z', b'x', b'c',
    b'v', b'b', b'n', b'm', b',', b'.', b'/', 0x00, 0x00, b' ', 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
];

// Scancode set 1 to ASCII, US layout, shifted.
const SCAN_SHIFT: [u8; 128] = [
    0x00, 0x00, b'!', b'@', b'#', b'$', b'%', b'^', b'&', b'*', b'(', b')', b'_', b'+', 0x08, 0x09,
    b'Q', b'W', b'E', b'R', b'T', b'Y', b'U', b'I', b'O', b'P', b'{', b'}', 0x0D, 0x00, 0x00, b'A',
    b'S', b'D', b'F', b'G', b'H', b'J', b'K', b'L', b':', b'"', b'~', 0x00, b'|', b'Z', b'X', b'C',
    b'V', b'B', b'N', b'M', b'<', b'>', b'?', 0x00, 0x00, b' ', 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
];

fn status() -> u8 {
    unsafe { inb(PS2_STATUS) }
}

/// True when the 8042 output buffer holds keyboard data (not mouse data).
pub fn keyboard_data_available() -> bool {
    let status = status();
    status & STATUS_OUTPUT_FULL != 0 && status & STATUS_MOUSE_DATA == 0
}

fn read_byte() -> u8 {
    unsafe { inb(PS2_DATA) }
}

/// Stream decoder: tracks the 0xE0 extended prefix and the shift state.
/// Text keys yield their ASCII byte; modifier and navigation keys are
/// consumed without a value.
pub struct Ps2Keyboard {
    extended: bool,
    shift: bool,
}

impl Ps2Keyboard {
    pub const fn new() -> Self {
        Ps2Keyboard { extended: false, shift: false }
    }

    pub fn poll(&mut self) -> Option<u8> {
        if !keyboard_data_available() {
            return None;
        }
        let code = read_byte();
        if code == EXTENDED_PREFIX {
            self.extended = true;
            return None;
        }
        let released = code & 0x80 != 0;
        let key = code & 0x7F;
        let extended = self.extended;
        self.extended = false;

        if key == SHIFT_KEY_L || key == SHIFT_KEY_R {
            self.shift = !released;
            return None;
        }
        if released || extended {
            return None;
        }
        let table = if self.shift { &SCAN_SHIFT } else { &SCAN_UNSHIFT };
        let ascii = table[key as usize];
        if ascii == 0 {
            return None;
        }
        Some(ascii)
    }
}
