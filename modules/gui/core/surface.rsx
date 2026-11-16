struct GSurface {
    p: ptr<u32>,
    w: i64,
    h: i64
}

fn gs_clear(s: &GSurface, c: GColor) {
    gs_fill(s, 0, 0, s.w, s.h, c);
}

fn gs_fill(s: &GSurface, x: i64, y: i64, w: i64, h: i64, c: GColor) {
    var x0: i64 = x;
    var y0: i64 = y;
    var x1: i64 = x + w;
    var y1: i64 = y + h;
    if (x0 < 0) {
        x0 = 0;
    }
    if (y0 < 0) {
        y0 = 0;
    }
    if (x1 > s.w) {
        x1 = s.w;
    }
    if (y1 > s.h) {
        y1 = s.h;
    }
    if (x0 >= x1 || y0 >= y1) {
        return;
    }
    let word: u32 = gui_word(c);
    let stride: i64 = s.w;
    unsafe {
        var yy: i64 = y0;
        while (yy < y1) {
            let row: ptr<u32> = s.p + yy * stride;
            var xx: i64 = x0;
            while (xx < x1) {
                row[xx] = word;
                xx += 1;
            }
            yy += 1;
        }
    }
}

fn gs_rect(s: &GSurface, x: i64, y: i64, w: i64, h: i64, c: GColor) {
    gs_fill(s, x, y, w, 1, c);
    gs_fill(s, x, y + h - 1, w, 1, c);
    gs_fill(s, x, y, 1, h, c);
    gs_fill(s, x + w - 1, y, 1, h, c);
}

fn gs_hline(s: &GSurface, x: i64, y: i64, w: i64, c: GColor) {
    gs_fill(s, x, y, w, 1, c);
}

fn gs_vline(s: &GSurface, x: i64, y: i64, h: i64, c: GColor) {
    gs_fill(s, x, y, 1, h, c);
}
