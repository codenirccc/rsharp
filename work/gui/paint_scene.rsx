extern "kernel32" fn CreateFileA(path: ptr<u8>, access: u32, share: u32, sa: ptr<u8>, disp: u32,
                                 flags: u32, tmpl: i64) -> i64;
extern "kernel32" fn ReadFile(h: i64, buf: ptr<u8>, want: u32, got: ptr<u32>, ov: ptr<u8>) -> i32;
extern "kernel32" fn WriteFile(h: i64, buf: ptr<u8>, n: u32, wrote: ptr<u32>, ov: ptr<u8>) -> i32;
extern "kernel32" fn CloseHandle(h: i64) -> i32;
extern "kernel32" fn GetFileSizeEx(h: i64, size: ptr<u64>) -> i32;

const PA_TITLE: i64 = 1;
const PA_BAR: i64 = 2;
const PA_C0: i64 = 3;
const PA_C1: i64 = 4;
const PA_C2: i64 = 5;
const PA_C3: i64 = 6;
const PA_C4: i64 = 7;
const PA_C5: i64 = 8;
const PA_C6: i64 = 9;
const PA_C7: i64 = 10;
const PA_BMINUS: i64 = 11;
const PA_BPLUS: i64 = 12;
const PA_CLEAR: i64 = 13;
const PA_SAVE: i64 = 14;
const PA_QUIT: i64 = 15;
const PA_CANVAS: i64 = 16;
const PA_HINT: i64 = 17;

const PA_CW: i64 = 656;
const PA_CH: i64 = 336;
const PA_WHITE: i64 = 16777215;

fn paint_palette(i: i64) -> GColor {
    if (i == 0) {
        return gui_col(20, 22, 28);
    }
    if (i == 1) {
        return gui_col(216, 48, 40);
    }
    if (i == 2) {
        return gui_col(240, 132, 32);
    }
    if (i == 3) {
        return gui_col(244, 204, 48);
    }
    if (i == 4) {
        return gui_col(56, 176, 88);
    }
    if (i == 5) {
        return gui_col(48, 96, 216);
    }
    if (i == 6) {
        return gui_col(168, 72, 200);
    }
    return gui_col(255, 255, 255);
}

fn paint_put_u16(b: ptr<u8>, off: i64, v: i64) {
    unsafe {
        b[off] = (v & 255) as u8;
        b[off + 1] = ((v >> 8) & 255) as u8;
    }
}

fn paint_put_u32(b: ptr<u8>, off: i64, v: i64) {
    unsafe {
        b[off] = (v & 255) as u8;
        b[off + 1] = ((v >> 8) & 255) as u8;
        b[off + 2] = ((v >> 16) & 255) as u8;
        b[off + 3] = ((v >> 24) & 255) as u8;
    }
}

fn paint_save_bmp(app: &mut GApp, id: i64, path: ptr<u8>) -> i32 {
    let w: i64 = app.widgets[id].iw;
    let h: i64 = app.widgets[id].ih;
    if (w < 1 || h < 1 || app.widgets[id].ink == null) {
        return 1;
    }
    let stride: i64 = w * 3;
    let image: i64 = stride * h;
    let total: i64 = 54 + image;
    let hdr: ptr<u8> = malloc(54);
    let pix: ptr<u8> = malloc(image as u64);
    if (hdr == null || pix == null) {
        return 1;
    }
    var zi: i64 = 0;
    unsafe {
        while (zi < 54) {
            hdr[zi] = 0;
            zi += 1;
        }
    }
    unsafe {
        hdr[0] = 66;
        hdr[1] = 77;
    }
    paint_put_u32(hdr, 2, total);
    paint_put_u32(hdr, 10, 54);
    paint_put_u32(hdr, 14, 40);
    paint_put_u32(hdr, 18, w);
    paint_put_u32(hdr, 22, h);
    paint_put_u16(hdr, 26, 1);
    paint_put_u16(hdr, 28, 24);
    paint_put_u32(hdr, 30, 0);
    paint_put_u32(hdr, 34, image);
    paint_put_u32(hdr, 38, 2835);
    paint_put_u32(hdr, 42, 2835);
    unsafe {
        let ink: ptr<u32> = app.widgets[id].ink as ptr<u32>;
        var row: i64 = 0;
        while (row < h) {
            let sy: i64 = h - 1 - row;
            var x: i64 = 0;
            while (x < w) {
                let px: u32 = ink[sy * w + x];
                let off: i64 = row * stride + x * 3;
                pix[off] = (px & 255) as u8;
                pix[off + 1] = ((px >> 8) & 255) as u8;
                pix[off + 2] = ((px >> 16) & 255) as u8;
                x += 1;
            }
            row += 1;
        }
    }
    let f: i64 = CreateFileA(path, 0x40000000, 0, null, 2, 0x80, 0);
    if (f == -1) {
        free(hdr);
        free(pix);
        return 1;
    }
    var wrote: u32 = 0;
    var ok: i32 = 1;
    unsafe {
        ok = WriteFile(f, hdr, 54, &wrote as ptr<u32>, null);
        wrote = 0;
        ok = WriteFile(f, pix, image as u32, &wrote as ptr<u32>, null);
    }
    CloseHandle(f);
    free(hdr);
    free(pix);
    if (ok == 0) {
        return 1;
    }
    return 0;
}

fn paint_brush(app: &mut GApp) -> i64 {
    return app.widgets[PA_CANVAS].bsize;
}

fn paint_word_index(app: &mut GApp) -> i64 {
    let wd: GWidget = app.widgets[PA_CANVAS];
    var i: i64 = 0;
    while (i < 7) {
        if (wd.bword == gui_word(paint_palette(i))) {
            return i;
        }
        i += 1;
    }
    return 7;
}

fn paint_status(app: &mut GApp) {
    let names: ptr<u8> = "KROYGBMW" as ptr<u8>;
    var idx: i64 = paint_word_index(app);
    let brush: i64 = paint_brush(app);
    var bp: ptr<u8> = gui_field_text(app, PA_HINT);
    var k: i64 = 0;
    unsafe {
        let prefix: ptr<u8> = "brush " as ptr<u8>;
        var p: i64 = 0;
        while (prefix[p] != 0) {
            bp[k] = prefix[p];
            k += 1;
            p += 1;
        }
        var nd: i64 = 0;
        var t: i64 = brush;
        while (t > 0) {
            t /= 10;
            nd += 1;
        }
        if (brush == 0) {
            nd = 1;
        }
        gui_itoa(bp + k, brush);
        k += nd;
        let mid: ptr<u8> = "  color " as ptr<u8>;
        p = 0;
        while (mid[p] != 0) {
            bp[k] = mid[p];
            k += 1;
            p += 1;
        }
        bp[k] = names[idx];
        k += 1;
        bp[k] = 0;
    }
    gui_set_text(app, PA_HINT, bp);
}

fn paint_set_brush(app: &mut GApp, size: i64) {
    var s: i64 = size;
    if (s < 1) {
        s = 1;
    }
    if (s > 8) {
        s = 8;
    }
    gui_canvas_brush(app, PA_CANVAS, app.widgets[PA_CANVAS].bword, s);
    paint_status(app);
}

fn paint_set_color(app: &mut GApp, idx: i64) {
    let c: GColor = paint_palette(idx);
    gui_canvas_brush(app, PA_CANVAS, gui_word(c), paint_brush(app));
    paint_status(app);
}

fn paint_clear(app: &mut GApp) {
    gui_canvas_clear(app, PA_CANVAS, PA_WHITE as u32);
    paint_status(app);
}

fn paint_build(app: &mut GApp) -> i32 {
    gui_set_pad(app, 0, 8, 8);
    var id: i64 = 0;
    id = gui_add(app, GK_LABEL, 0, "paint");
    if (id != PA_TITLE) {
        return -1;
    }
    id = gui_add(app, GK_PANEL, 0, null);
    if (id != PA_BAR) {
        return -1;
    }
    gui_set_layout(app, PA_BAR, GL_ROW);
    gui_set_pad(app, PA_BAR, 0, 6);
    gui_set_size(app, PA_BAR, 0, 34);
    gui_set_fill(app, PA_BAR, 1);
    id = gui_add(app, GK_BUTTON, PA_BAR, "K");
    if (id != PA_C0) {
        return -1;
    }
    gui_set_grow(app, PA_C0, 1);
    gui_set_fill(app, PA_C0, 1);
    id = gui_add(app, GK_BUTTON, PA_BAR, "R");
    if (id != PA_C1) {
        return -1;
    }
    gui_set_grow(app, PA_C1, 1);
    gui_set_fill(app, PA_C1, 1);
    id = gui_add(app, GK_BUTTON, PA_BAR, "O");
    if (id != PA_C2) {
        return -1;
    }
    gui_set_grow(app, PA_C2, 1);
    gui_set_fill(app, PA_C2, 1);
    id = gui_add(app, GK_BUTTON, PA_BAR, "Y");
    if (id != PA_C3) {
        return -1;
    }
    gui_set_grow(app, PA_C3, 1);
    gui_set_fill(app, PA_C3, 1);
    id = gui_add(app, GK_BUTTON, PA_BAR, "G");
    if (id != PA_C4) {
        return -1;
    }
    gui_set_grow(app, PA_C4, 1);
    gui_set_fill(app, PA_C4, 1);
    id = gui_add(app, GK_BUTTON, PA_BAR, "B");
    if (id != PA_C5) {
        return -1;
    }
    gui_set_grow(app, PA_C5, 1);
    gui_set_fill(app, PA_C5, 1);
    id = gui_add(app, GK_BUTTON, PA_BAR, "M");
    if (id != PA_C6) {
        return -1;
    }
    gui_set_grow(app, PA_C6, 1);
    gui_set_fill(app, PA_C6, 1);
    id = gui_add(app, GK_BUTTON, PA_BAR, "W");
    if (id != PA_C7) {
        return -1;
    }
    gui_set_grow(app, PA_C7, 1);
    gui_set_fill(app, PA_C7, 1);
    id = gui_add(app, GK_BUTTON, PA_BAR, "-");
    if (id != PA_BMINUS) {
        return -1;
    }
    gui_set_size(app, PA_BMINUS, 34, 0);
    gui_set_fill(app, PA_BMINUS, 1);
    id = gui_add(app, GK_BUTTON, PA_BAR, "+");
    if (id != PA_BPLUS) {
        return -1;
    }
    gui_set_size(app, PA_BPLUS, 34, 0);
    gui_set_fill(app, PA_BPLUS, 1);
    id = gui_add(app, GK_BUTTON, PA_BAR, "clear");
    if (id != PA_CLEAR) {
        return -1;
    }
    gui_set_size(app, PA_CLEAR, 88, 0);
    gui_set_fill(app, PA_CLEAR, 1);
    id = gui_add(app, GK_BUTTON, PA_BAR, "save");
    if (id != PA_SAVE) {
        return -1;
    }
    gui_set_size(app, PA_SAVE, 74, 0);
    gui_set_fill(app, PA_SAVE, 1);
    id = gui_add(app, GK_BUTTON, PA_BAR, "quit");
    if (id != PA_QUIT) {
        return -1;
    }
    gui_set_size(app, PA_QUIT, 74, 0);
    gui_set_fill(app, PA_QUIT, 1);
    id = gui_add(app, GK_CANVAS, 0, null);
    if (id != PA_CANVAS) {
        return -1;
    }
    gui_set_size(app, PA_CANVAS, PA_CW, PA_CH);
    gui_set_align(app, PA_CANVAS, GA_CENTER);
    if (gui_canvas_setup(app, PA_CANVAS, PA_CW, PA_CH) != 0) {
        return -1;
    }
    gui_canvas_brush(app, PA_CANVAS, gui_word(gui_col(20, 22, 28)), 2);
    id = gui_add(app, GK_FIELD, 0, null);
    if (id != PA_HINT) {
        return -1;
    }
    gui_set_fill(app, PA_HINT, 1);
    paint_status(app);
    return 0;
}

fn paint_drain(app: &mut GApp) -> i64 {
    var ev: GEvent = zero(GEvent);
    var n: i64 = 0;
    while (gui_next_event(app, &mut ev) == 1) {
        n += 1;
        if (ev.code == GEV_CLICK) {
            if (ev.id == PA_QUIT) {
                app.quit = 1;
            } else if (ev.id == PA_CLEAR) {
                paint_clear(app);
            } else if (ev.id == PA_SAVE) {
                let rc: i32 = paint_save_bmp(app, PA_CANVAS, "paint.bmp" as ptr<u8>);
                if (rc == 0) {
                    gui_set_buf(app, PA_HINT, "saved paint.bmp");
                } else {
                    gui_set_buf(app, PA_HINT, "save failed");
                }
            } else if (ev.id == PA_BMINUS) {
                paint_set_brush(app, paint_brush(app) - 1);
            } else if (ev.id == PA_BPLUS) {
                paint_set_brush(app, paint_brush(app) + 1);
            } else if (ev.id >= PA_C0 && ev.id <= PA_C7) {
                paint_set_color(app, ev.id - PA_C0);
            }
        }
    }
    return n;
}
