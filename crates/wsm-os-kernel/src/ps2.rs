// PS/2 8042 Keyboard and Mouse driver substrate for WSM-OS.
//
// Hardware Characteristics (Gigabyte GA-H170-Gaming 3 & QEMU Q35):
// - Host Controller: Intel 8042 compatible (ITE IT8628E on physical board / ICH9 LPC on QEMU)
// - Ports: 0x60 (Data R/W), 0x64 (Status R, Command W)
// - Port 1: PS/2 Keyboard (Scancode Set 1, make/break codes)
// - Port 2: PS/2 Auxiliary Mouse (Standard 3-byte packet streaming)
// - Mouse packet: [flags, dx, dy] with 4 counts/mm resolution and 100 Hz sampling.

#![allow(dead_code)]

use crate::{inb, outb};

pub const PS2_DATA: u16 = 0x60;
pub const PS2_STATUS: u16 = 0x64;
pub const PS2_COMMAND: u16 = 0x64;

pub const STATUS_OUTPUT_FULL: u8 = 0x01;
pub const STATUS_INPUT_FULL: u8 = 0x02;
pub const STATUS_SYSTEM_FLAG: u8 = 0x04;
pub const STATUS_CMD_DATA: u8 = 0x08;
pub const STATUS_KEYBOARD_LOCKED: u8 = 0x10;
pub const STATUS_MOUSE_DATA: u8 = 0x20;
pub const STATUS_TIMEOUT: u8 = 0x40;
pub const STATUS_PARITY_ERROR: u8 = 0x80;

const CMD_READ_CONFIG: u8 = 0x20;
const CMD_WRITE_CONFIG: u8 = 0x60;
const CMD_DISABLE_MOUSE: u8 = 0xA7;
const CMD_ENABLE_MOUSE: u8 = 0xA8;
const CMD_TEST_MOUSE: u8 = 0xA9;
const CMD_DISABLE_KBD: u8 = 0xAD;
const CMD_ENABLE_KBD: u8 = 0xAE;
const CMD_WRITE_MOUSE: u8 = 0xD4;

const MOUSE_CMD_SET_DEFAULTS: u8 = 0xF6;
const MOUSE_CMD_ENABLE_REPORTING: u8 = 0xF4;
const MOUSE_CMD_DISABLE_REPORTING: u8 = 0xF5;
const MOUSE_ACK: u8 = 0xFA;

const EXTENDED_PREFIX: u8 = 0xE0;

// Shift make codes: left 0x2A, right 0x36. Break = code | 0x80.
const SHIFT_KEY_L: u8 = 0x2A;
const SHIFT_KEY_R: u8 = 0x36;

// Scancode set 1 to ASCII, US layout, unshifted.
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

pub fn status() -> u8 {
    unsafe { inb(PS2_STATUS) }
}

pub fn read_data() -> u8 {
    unsafe { inb(PS2_DATA) }
}

fn wait_input_empty() -> bool {
    for _ in 0..100_000 {
        if status() & STATUS_INPUT_FULL == 0 {
            return true;
        }
        core::hint::spin_loop();
    }
    false
}

fn wait_output_full() -> bool {
    for _ in 0..100_000 {
        if status() & STATUS_OUTPUT_FULL != 0 {
            return true;
        }
        core::hint::spin_loop();
    }
    false
}

pub fn mouse_write_byte(byte: u8) -> bool {
    if !wait_input_empty() {
        return false;
    }
    unsafe { outb(PS2_COMMAND, CMD_WRITE_MOUSE) };
    if !wait_input_empty() {
        return false;
    }
    unsafe { outb(PS2_DATA, byte) };
    if !wait_output_full() {
        return false;
    }
    let ack = read_data();
    ack == MOUSE_ACK
}

/// Initialize PS/2 mouse via assembly 8042 controller protocol.
pub fn mouse_init() -> bool {
    unsafe { crate::wsm_asm_mouse_init() != 0 }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Ps2RawEvent {
    Keyboard(u8),
    Mouse(u8),
}

/// Poll 8042 controller via assembly and return demultiplexed keyboard or mouse byte.
pub fn poll_raw() -> Option<Ps2RawEvent> {
    let res = unsafe { crate::wsm_asm_ps2_poll() };
    if res < 0 {
        None
    } else if (res & 0x0100) != 0 {
        Some(Ps2RawEvent::Mouse((res & 0xFF) as u8))
    } else {
        Some(Ps2RawEvent::Keyboard((res & 0xFF) as u8))
    }
}

// ---------------------------------------------------------------------------
// Keyboard Stream Decoder
// ---------------------------------------------------------------------------

pub struct Ps2Keyboard {
    extended: bool,
    shift: bool,
}

impl Ps2Keyboard {
    pub const fn new() -> Self {
        Ps2Keyboard {
            extended: false,
            shift: false,
        }
    }

    pub fn handle_byte(&mut self, code: u8) -> Option<u8> {
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

    pub fn poll(&mut self) -> Option<u8> {
        match poll_raw() {
            Some(Ps2RawEvent::Keyboard(byte)) => self.handle_byte(byte),
            _ => None,
        }
    }
}

// ---------------------------------------------------------------------------
// Mouse Packet Decoder & Position Tracker
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct MousePacket {
    pub dx: i32,
    pub dy: i32,
    pub btn_left: bool,
    pub btn_right: bool,
    pub btn_middle: bool,
}

pub struct Ps2Mouse {
    pub x: i32,
    pub y: i32,
    pub btn_left: bool,
    pub btn_right: bool,
    pub btn_middle: bool,
    phase: u8,
    buf: [u8; 3],
    max_x: i32,
    max_y: i32,
}

impl Ps2Mouse {
    pub fn new(max_x: i32, max_y: i32) -> Self {
        Self {
            x: max_x / 2,
            y: max_y / 2,
            btn_left: false,
            btn_right: false,
            btn_middle: false,
            phase: 0,
            buf: [0; 3],
            max_x,
            max_y,
        }
    }

    pub fn set_bounds(&mut self, max_x: i32, max_y: i32) {
        self.max_x = max_x;
        self.max_y = max_y;
        self.x = self.x.clamp(0, max_x);
        self.y = self.y.clamp(0, max_y);
    }

    pub fn handle_byte(&mut self, byte: u8) -> Option<MousePacket> {
        match self.phase {
            0 => {
                // Sanity bit: bit 3 must always be 1 in standard PS/2 mouse packet
                if byte & 0x08 == 0 {
                    return None;
                }
                self.buf[0] = byte;
                self.phase = 1;
                None
            }
            1 => {
                self.buf[1] = byte;
                self.phase = 2;
                None
            }
            2 => {
                self.buf[2] = byte;
                self.phase = 0;

                let flags = self.buf[0];
                let raw_dx = self.buf[1];
                let raw_dy = self.buf[2];

                let x_neg = (flags & 0x10) != 0;
                let y_neg = (flags & 0x20) != 0;

                let dx = if x_neg { (raw_dx as i8) as i32 } else { raw_dx as i32 };
                let dy = if y_neg { (raw_dy as i8) as i32 } else { raw_dy as i32 };

                self.btn_left = (flags & 0x01) != 0;
                self.btn_right = (flags & 0x02) != 0;
                self.btn_middle = (flags & 0x04) != 0;

                // Mouse delta Y in PS/2 is positive UPWARDS; screen Y is positive DOWNWARDS.
                self.x = (self.x + dx).clamp(0, self.max_x);
                self.y = (self.y - dy).clamp(0, self.max_y);

                Some(MousePacket {
                    dx,
                    dy,
                    btn_left: self.btn_left,
                    btn_right: self.btn_right,
                    btn_middle: self.btn_middle,
                })
            }
            _ => {
                self.phase = 0;
                None
            }
        }
    }
}

static mut MAX_X: u32 = 1024;
static mut MAX_Y: u32 = 768;

pub fn mouse_set_bounds(max_x: i32, max_y: i32) {
    unsafe {
        MAX_X = max_x.max(0) as u32;
        MAX_Y = max_y.max(0) as u32;
    }
}

pub fn mouse_handle_byte(byte: u8) -> Option<MousePacket> {
    unsafe {
        let ok = crate::wsm_asm_mouse_update(byte, MAX_X, MAX_Y);
        if ok != 0 {
            Some(MousePacket {
                dx: 0,
                dy: 0,
                btn_left: (crate::wsm_mouse_buttons & 1) != 0,
                btn_right: (crate::wsm_mouse_buttons & 2) != 0,
                btn_middle: (crate::wsm_mouse_buttons & 4) != 0,
            })
        } else {
            None
        }
    }
}

pub fn mouse_get_pos() -> (i32, i32) {
    unsafe {
        (crate::wsm_mouse_x, crate::wsm_mouse_y)
    }
}

pub fn mouse_get_buttons() -> (bool, bool, bool) {
    unsafe {
        let b = crate::wsm_mouse_buttons;
        ((b & 1) != 0, (b & 2) != 0, (b & 4) != 0)
    }
}
