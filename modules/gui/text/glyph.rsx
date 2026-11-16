fn gs_char(s: &GSurface, x: i64, y: i64, ch: i64, c: GColor, scale: i64) {
    if (ch < 32 || ch > 126) {
        return;
    }
    if (x < 0 || y < 0 || x + 5 * scale > s.w || y + 7 * scale > s.h) {
        return;
    }
    let word: u32 = gui_word(c);
    let stride: i64 = s.w;
    var r: i64 = 0;
    unsafe {
        while (r < 7) {
            let bits: u8 = gui_font_row(ch, r);
            if (bits != 0) {
                var yy: i64 = 0;
                while (yy < scale) {
                    let row: ptr<u32> = s.p + (y + r * scale + yy) * stride;
                    var cx: i64 = 0;
                    while (cx < 5) {
                        if ((((bits as u32) >> (cx as u32)) & 1) == 1) {
                            var sx: i64 = 0;
                            while (sx < scale) {
                                row[x + cx * scale + sx] = word;
                                sx += 1;
                            }
                        }
                        cx += 1;
                    }
                    yy += 1;
                }
            }
            r += 1;
        }
    }
}
