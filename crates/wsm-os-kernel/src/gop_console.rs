// Bootloader-provisioned GOP framebuffer text console: 8x16 glyphs drawn as
// BGR/RGB pixels from the public-domain IBM VGA font table, with a cell grid
// (cell = 8x16 px), one-keystroke scrollback and a background-cleared screen.

use bootloader_api::info::{FrameBuffer, FrameBufferInfo, PixelFormat};

use crate::font8x16::FONT_8X16;

pub const FG_WHITE: [u8; 3] = [0xFF, 0xFF, 0xFF];

const GLYPH_W: usize = 8;
const GLYPH_H: usize = 16;

pub struct GopConsole<'a> {
    buffer: &'a mut [u8],
    width: usize,
    height: usize,
    stride: usize,
    bytes_per_pixel: usize,
    pixel_format: PixelFormat,
    fg: [u8; 3],
    cols: usize,
    rows: usize,
    col: usize,
    row: usize,
}

impl<'a> GopConsole<'a> {
    pub fn new(fb: &'a mut FrameBuffer) -> Self {
        let info: FrameBufferInfo = fb.info();
        let buffer = fb.buffer_mut();
        let cols = (info.width / GLYPH_W).max(1);
        let rows = (info.height / GLYPH_H).max(1);
        GopConsole {
            buffer,
            width: info.width,
            height: info.height,
            stride: info.stride,
            bytes_per_pixel: info.bytes_per_pixel,
            pixel_format: info.pixel_format,
            fg: FG_WHITE,
            cols,
            rows,
            col: 0,
            row: 0,
        }
    }

    pub fn info(&self) -> FrameBufferInfo {
        FrameBufferInfo {
            byte_len: self.buffer.len(),
            width: self.width,
            height: self.height,
            pixel_format: self.pixel_format,
            bytes_per_pixel: self.bytes_per_pixel,
            stride: self.stride,
        }
    }

    pub fn width(&self) -> usize {
        self.width
    }

    pub fn height(&self) -> usize {
        self.height
    }

    #[allow(dead_code)]
    pub fn read_pixel(&self, x: usize, y: usize) -> [u8; 3] {
        let Some(base) = self.pixel_offset(x, y) else {
            return [0, 0, 0];
        };
        if base + 3 > self.buffer.len() {
            return [0, 0, 0];
        }
        match self.pixel_format {
            PixelFormat::Bgr => [self.buffer[base + 2], self.buffer[base + 1], self.buffer[base]],
            PixelFormat::Rgb => [self.buffer[base], self.buffer[base + 1], self.buffer[base + 2]],
            _ => [0, 0, 0],
        }
    }

    #[allow(dead_code)]
    pub fn draw_mouse_pointer(&mut self, cx: usize, cy: usize, color: [u8; 3]) {
        const ARROW: [u8; 8] = [
            0b10000000,
            0b11000000,
            0b11100000,
            0b11110000,
            0b11111000,
            0b11100000,
            0b10110000,
            0b00011000,
        ];
        for (dy, row) in ARROW.iter().enumerate() {
            for dx in 0..8 {
                if (row & (0x80 >> dx)) != 0 {
                    self.write_pixel(cx + dx, cy + dy, color);
                }
            }
        }
    }

    #[allow(dead_code)]
    pub fn invert_pixel(&mut self, x: usize, y: usize) {
        let Some(base) = self.pixel_offset(x, y) else {
            return;
        };
        if base + 2 < self.buffer.len() {
            self.buffer[base] ^= 0xFF;
            self.buffer[base + 1] ^= 0xFF;
            self.buffer[base + 2] ^= 0xFF;
        }
    }

    pub fn draw_xor_cursor(&mut self, cx: usize, cy: usize) {
        unsafe {
            crate::wsm_asm_draw_xor_cursor(
                self.buffer.as_mut_ptr(),
                self.width as u64,
                self.height as u64,
                self.stride as u64,
                self.bytes_per_pixel as u64,
                cx as u64,
                cy as u64,
            );
        }
    }

    fn pixel_offset(&self, x: usize, y: usize) -> Option<usize> {
        if x >= self.width || y >= self.height {
            return None;
        }
        Some((y * self.stride + x) * self.bytes_per_pixel)
    }

    fn write_pixel(&mut self, x: usize, y: usize, rgb: [u8; 3]) {
        let Some(base) = self.pixel_offset(x, y) else {
            return;
        };
        if base + 3 > self.buffer.len() {
            return;
        }
        let (b, g, r) = match self.pixel_format {
            PixelFormat::Bgr => (rgb[2], rgb[1], rgb[0]),
            PixelFormat::Rgb => (rgb[0], rgb[1], rgb[2]),
            _ => return,
        };
        self.buffer[base] = b;
        self.buffer[base + 1] = g;
        self.buffer[base + 2] = r;
        if self.bytes_per_pixel >= 4 && base + 4 <= self.buffer.len() {
            self.buffer[base + 3] = 0xFF;
        }
    }

    pub fn clear(&mut self) {
        for byte in self.buffer.iter_mut() {
            *byte = 0;
        }
        self.col = 0;
        self.row = 0;
    }

    fn draw_glyph(&mut self, ch: u8, col: usize, row: usize) {
        let glyph = FONT_8X16[ch as usize];
        let x0 = col * GLYPH_W;
        let y0 = row * GLYPH_H;
        for (glyph_row, line) in glyph.iter().enumerate() {
            for gx in 0..GLYPH_W {
                if line & (0x80 >> gx) != 0 {
                    self.write_pixel(x0 + gx, y0 + glyph_row, self.fg);
                }
            }
        }
    }

    fn newline(&mut self) {
        self.col = 0;
        self.row += 1;
        if self.row >= self.rows {
            self.scroll_up();
            self.row = self.rows - 1;
        }
    }

    fn scroll_up(&mut self) {
        let line_bytes = self.stride * self.bytes_per_pixel;
        let scroll_bytes = GLYPH_H * line_bytes;
        if scroll_bytes >= self.buffer.len() {
            self.clear();
            return;
        }
        let keep = self.buffer.len() - scroll_bytes;
        self.buffer.copy_within(scroll_bytes.., 0);
        for byte in self.buffer[keep..].iter_mut() {
            *byte = 0;
        }
    }

    pub fn put_char(&mut self, ch: u8) {
        match ch {
            b'\n' => self.newline(),
            b'\r' => self.col = 0,
            8 | 127 => self.col = self.col.saturating_sub(1),
            0..=31 => {}
            _ => {
                self.draw_glyph(ch, self.col, self.row);
                self.col += 1;
                if self.col >= self.cols {
                    self.newline();
                }
            }
        }
    }

    pub fn write_slice(&mut self, bytes: &[u8]) {
        for &b in bytes {
            self.put_char(b);
        }
    }

    pub fn write_line(&mut self, bytes: &[u8]) {
        self.write_slice(bytes);
        self.put_char(b'\n');
    }

    /// Count pixels distinguishable from the zeroed background. The witness
    /// uses this to prove glyphs were actually rasterized into the buffer.
    pub fn drawn_pixel_count(&self) -> usize {
        let bpp = self.bytes_per_pixel;
        if bpp == 0 {
            return 0;
        }
        let mut count = 0;
        let mut i = 0;
        while i + 2 < self.buffer.len() {
            if self.buffer[i] != 0 || self.buffer[i + 1] != 0 || self.buffer[i + 2] != 0 {
                count += 1;
            }
            i += bpp;
        }
        count
    }
}