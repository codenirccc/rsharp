fn gui_canvas_setup(app: &mut GApp, id: i64, w: i64, h: i64) -> i32 {
    if (id < 0 || id >= app.nw) {
        return -1;
    }
    if (w < 1 || h < 1) {
        return -2;
    }
    if (app.widgets[id].ink != null) {
        free(app.widgets[id].ink);
        app.widgets[id].ink = null;
    }
    let p: ptr<u8> = malloc((w * h * 4) as u64);
    if (p == null) {
        return -3;
    }
    let n: i64 = w * h;
    var i: i64 = 0;
    unsafe {
        let q: ptr<u32> = p as ptr<u32>;
        while (i < n) {
            q[i] = 16777215;
            i += 1;
        }
    }
    app.widgets[id].ink = p;
    app.widgets[id].iw = w;
    app.widgets[id].ih = h;
    app.widgets[id].bword = 0;
    app.widgets[id].bsize = 2;
    app.dirty = 1;
    return 0;
}

fn gui_canvas_brush(app: &mut GApp, id: i64, word: u32, size: i64) {
    if (id < 0 || id >= app.nw) {
        return;
    }
    app.widgets[id].bword = word;
    app.widgets[id].bsize = size;
    app.dirty = 1;
}

fn gui_canvas_px(app: &mut GApp, id: i64, cx: i64, cy: i64) {
    if (app.widgets[id].ink == null) {
        return;
    }
    let w: i64 = app.widgets[id].iw;
    let h: i64 = app.widgets[id].ih;
    let size: i64 = app.widgets[id].bsize;
    let half: i64 = size / 2;
    let word: u32 = app.widgets[id].bword;
    var y: i64 = cy - half;
    unsafe {
        let base: ptr<u32> = app.widgets[id].ink as ptr<u32>;
        while (y < cy + size - half) {
            var x: i64 = cx - half;
            while (x < cx + size - half) {
                if (x >= 0 && y >= 0 && x < w && y < h) {
                    base[y * w + x] = word;
                }
                x += 1;
            }
            y += 1;
        }
    }
}

fn gui_canvas_line(app: &mut GApp, id: i64, x0: i64, y0: i64, x1: i64, y1: i64) {
    var dx: i64 = x1 - x0;
    if (dx < 0) {
        dx = 0 - dx;
    }
    var dy: i64 = y1 - y0;
    if (dy < 0) {
        dy = 0 - dy;
    }
    var sx: i64 = 1;
    if (x0 > x1) {
        sx = -1;
    }
    var sy: i64 = 1;
    if (y0 > y1) {
        sy = -1;
    }
    var err: i64 = dx - dy;
    var x: i64 = x0;
    var y: i64 = y0;
    while (true) {
        gui_canvas_px(app, id, x, y);
        if (x == x1 && y == y1) {
            break;
        }
        let e2: i64 = 2 * err;
        if (e2 > 0 - dy) {
            err -= dy;
            x += sx;
        }
        if (e2 < dx) {
            err += dx;
            y += sy;
        }
    }
}

fn gui_canvas_clear(app: &mut GApp, id: i64, word: u32) {
    if (app.widgets[id].ink == null) {
        return;
    }
    let w: i64 = app.widgets[id].iw;
    let h: i64 = app.widgets[id].ih;
    var i: i64 = 0;
    let n: i64 = w * h;
    unsafe {
        let q: ptr<u32> = app.widgets[id].ink as ptr<u32>;
        while (i < n) {
            q[i] = word;
            i += 1;
        }
    }
    app.dirty = 1;
}

fn gui_canvas_stroke(app: &mut GApp, id: i64, x: i64, y: i64) {
    let wx: i64 = app.widgets[id].x;
    let wy: i64 = app.widgets[id].y;
    let x0: i64 = app.pmx - wx;
    let y0: i64 = app.pmy - wy;
    let x1: i64 = x - wx;
    let y1: i64 = y - wy;
    gui_canvas_line(app, id, x0, y0, x1, y1);
    app.pmx = x;
    app.pmy = y;
    app.dirty = 1;
}

fn gui_canvas_begin(app: &mut GApp, id: i64, x: i64, y: i64) {
    app.pmx = x;
    app.pmy = y;
    let wx: i64 = app.widgets[id].x;
    let wy: i64 = app.widgets[id].y;
    gui_canvas_px(app, id, x - wx, y - wy);
    app.dirty = 1;
}

fn gui_draw_canvas(app: &mut GApp, i: i64) {
    let t: GTheme = app.theme;
    let wd: GWidget = app.widgets[i];
    if (wd.ink == null) {
        gs_fill(&app.surface, wd.x, wd.y, wd.w, wd.h, t.sunken);
        gs_rect(&app.surface, wd.x, wd.y, wd.w, wd.h, t.edge);
        return;
    }
    let w: i64 = wd.iw;
    let h: i64 = wd.ih;
    unsafe {
        let ink: ptr<u32> = wd.ink as ptr<u32>;
        var yy: i64 = 0;
        while (yy < h) {
            let dy: i64 = wd.y + yy;
            if (dy >= 0 && dy < app.surface.h) {
                let row: ptr<u32> = app.surface.p + dy * app.surface.w;
                var xx: i64 = 0;
                while (xx < w) {
                    let sx: i64 = wd.x + xx;
                    if (sx >= 0 && sx < app.surface.w) {
                        row[sx] = ink[yy * w + xx];
                    }
                    xx += 1;
                }
            }
            yy += 1;
        }
    }
    gs_rect(&app.surface, wd.x, wd.y, wd.w, wd.h, t.edge_hi);
}
