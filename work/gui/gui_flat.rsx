include "font.rsx";

extern fn malloc(n: u64) -> ptr<u8>;
extern fn free(p: ptr<u8>) -> void;
extern fn memset(d: ptr<u8>, v: i32, n: u64) -> ptr<u8>;
extern fn strlen(s: ptr<u8>) -> u64;

const GUI_MAX_WIDGETS: i64 = 48;
const GUI_MAX_EVENTS: i64 = 32;
const GUI_TEXT_MAX: i64 = 48;

const GK_PANEL: i64 = 0;
const GK_LABEL: i64 = 1;
const GK_BUTTON: i64 = 2;
const GK_CHECK: i64 = 3;
const GK_FIELD: i64 = 4;
const GK_SLIDER: i64 = 5;
const GK_PROGRESS: i64 = 6;

const GL_COL: i64 = 0;
const GL_ROW: i64 = 1;

const GA_LEFT: i64 = 0;
const GA_CENTER: i64 = 1;
const GA_RIGHT: i64 = 2;

const GEV_CLICK: i64 = 1;
const GEV_TOGGLE: i64 = 2;
const GEV_CHANGE: i64 = 3;
const GEV_SUBMIT: i64 = 4;
const GEV_FOCUS: i64 = 5;
const GEV_BLUR: i64 = 6;
const GEV_TIMER: i64 = 7;
const GEV_CLOSE: i64 = 8;

const VK_BACK: i64 = 8;
const VK_TAB: i64 = 9;
const VK_RETURN: i64 = 13;
const VK_ESCAPE: i64 = 27;
const VK_SPACE: i64 = 32;
const VK_END: i64 = 35;
const VK_HOME: i64 = 36;
const VK_LEFT: i64 = 37;
const VK_UP: i64 = 38;
const VK_RIGHT: i64 = 39;
const VK_DOWN: i64 = 40;
const VK_DELETE: i64 = 46;

struct GColor {
    r: u8,
    g: u8,
    b: u8,
    pad: u8
}

struct GSurface {
    p: ptr<u32>,
    w: i64,
    h: i64
}

struct GTheme {
    scale: i64,
    pad: i64,
    gap: i64,
    row: i64,
    unit: i64,
    bg: GColor,
    face: GColor,
    face_hot: GColor,
    face_down: GColor,
    sunken: GColor,
    edge: GColor,
    edge_hi: GColor,
    ink: GColor,
    ink_dim: GColor,
    accent: GColor,
    accent_ink: GColor,
    track: GColor,
    mark: GColor
}

struct GWidget {
    kind: i64,
    id: i64,
    parent: i64,
    layout: i64,
    pad: i64,
    gap: i64,
    x: i64,
    y: i64,
    w: i64,
    h: i64,
    fw: i64,
    fh: i64,
    grow: i64,
    fill: i64,
    align: i64,
    visible: i64,
    enabled: i64,
    hot: i64,
    active: i64,
    focus: i64,
    value: i64,
    vmin: i64,
    vmax: i64,
    caret: i64,
    blen: i64,
    text: ptr<u8>,
    buf: [u8; GUI_TEXT_MAX]
}

struct GEvent {
    id: i64,
    code: i64,
    value: i64
}

struct GApp {
    w: i64,
    h: i64,
    nw: i64,
    hot: i64,
    press: i64,
    focus: i64,
    drag: i64,
    mx: i64,
    my: i64,
    down: i64,
    frames: i64,
    dirty: i64,
    quit: i64,
    nev: i64,
    evh: i64,
    px: ptr<u8>,
    surface: GSurface,
    theme: GTheme,
    widgets: [GWidget; GUI_MAX_WIDGETS],
    events: [GEvent; GUI_MAX_EVENTS]
}

fn gui_col(r: u8, g: u8, b: u8) -> GColor {
    var c: GColor = zero(GColor);
    c.r = r;
    c.g = g;
    c.b = b;
    c.pad = 0;
    return c;
}

fn gui_word(c: GColor) -> u32 {
    return (c.b as u32) | ((c.g as u32) << 8) | ((c.r as u32) << 16);
}

fn gui_len(s: ptr<u8>) -> i64 {
    if (s == null) {
        return 0;
    }
    return strlen(s) as i64;
}

fn gui_clampi(v: i64, lo: i64, hi: i64) -> i64 {
    if (v < lo) {
        return lo;
    }
    if (v > hi) {
        return hi;
    }
    return v;
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

fn gs_text(s: &GSurface, x: i64, y: i64, t: ptr<u8>, c: GColor, scale: i64) {
    if (t == null) {
        return;
    }
    let n: i64 = strlen(t) as i64;
    var i: i64 = 0;
    unsafe {
        while (i < n) {
            gs_char(s, x + i * 6 * scale, y, t[i] as i64, c, scale);
            i += 1;
        }
    }
}

fn gui_text_w(t: ptr<u8>, scale: i64) -> i64 {
    return strlen(t) as i64 * 6 * scale;
}

fn gui_text_h(scale: i64) -> i64 {
    return 7 * scale;
}

fn gui_itoa(out: ptr<u8>, v: i64) {
    var tmp: [u8; 24] = [0];
    var n: i64 = v;
    var i: i64 = 24;
    var neg: i64 = 0;
    if (n < 0) {
        neg = 1;
        n = 0 - n;
    }
    if (n == 0) {
        i -= 1;
        tmp[i] = 48;
    }
    while (n > 0) {
        i -= 1;
        tmp[i] = (48 + (n % 10)) as u8;
        n = n / 10;
    }
    if (neg == 1) {
        i -= 1;
        tmp[i] = 45;
    }
    var k: i64 = 0;
    unsafe {
        while (i < 24) {
            out[k] = tmp[i];
            k += 1;
            i += 1;
        }
        out[k] = 0;
    }
}

fn gui_copy(dst: ptr<u8>, src: ptr<u8>, max: i64) -> i64 {
    var i: i64 = 0;
    unsafe {
        while (i < max - 1 && src[i] != 0) {
            dst[i] = src[i];
            i += 1;
        }
        dst[i] = 0;
    }
    return i;
}

fn gui_theme_dark(t: &mut GTheme) {
    t.scale = 2;
    t.pad = 10;
    t.gap = 8;
    t.row = 24;
    t.unit = 4;
    t.bg = gui_col(24, 26, 32);
    t.face = gui_col(44, 48, 58);
    t.face_hot = gui_col(62, 68, 82);
    t.face_down = gui_col(30, 33, 40);
    t.sunken = gui_col(18, 20, 24);
    t.edge = gui_col(16, 17, 21);
    t.edge_hi = gui_col(86, 94, 112);
    t.ink = gui_col(228, 234, 244);
    t.ink_dim = gui_col(140, 148, 164);
    t.accent = gui_col(64, 196, 220);
    t.accent_ink = gui_col(12, 18, 22);
    t.track = gui_col(56, 60, 72);
    t.mark = gui_col(248, 212, 96);
}

fn gui_theme_light(t: &mut GTheme) {
    t.scale = 2;
    t.pad = 10;
    t.gap = 8;
    t.row = 24;
    t.unit = 4;
    t.bg = gui_col(238, 240, 244);
    t.face = gui_col(250, 251, 253);
    t.face_hot = gui_col(232, 238, 248);
    t.face_down = gui_col(214, 220, 230);
    t.sunken = gui_col(255, 255, 255);
    t.edge = gui_col(170, 176, 188);
    t.edge_hi = gui_col(120, 128, 144);
    t.ink = gui_col(28, 32, 40);
    t.ink_dim = gui_col(104, 112, 128);
    t.accent = gui_col(28, 122, 214);
    t.accent_ink = gui_col(250, 252, 255);
    t.track = gui_col(206, 212, 222);
    t.mark = gui_col(28, 122, 214);
}

fn gui_app_init(app: &mut GApp, w: i64, h: i64) -> i32 {
    if (w < 32 || h < 32) {
        return -1;
    }
    app.w = w;
    app.h = h;
    app.nw = 0;
    app.hot = -1;
    app.press = -1;
    app.focus = -1;
    app.drag = -1;
    app.mx = 0;
    app.my = 0;
    app.down = 0;
    app.frames = 0;
    app.dirty = 1;
    app.quit = 0;
    app.nev = 0;
    app.evh = 0;
    app.px = malloc((w * h * 4) as u64);
    if (app.px == null) {
        return -2;
    }
    var sp: ptr<u32> = null;
    unsafe { sp = app.px as ptr<u32>; }
    app.surface.p = sp;
    app.surface.w = w;
    app.surface.h = h;
    gui_theme_dark(&mut app.theme);
    var root: GWidget = zero(GWidget);
    root.kind = GK_PANEL;
    root.id = 0;
    root.parent = -1;
    root.layout = GL_COL;
    root.pad = app.theme.pad;
    root.gap = app.theme.gap;
    root.x = 0;
    root.y = 0;
    root.w = w;
    root.h = h;
    root.visible = 1;
    root.enabled = 1;
    app.widgets[0] = root;
    app.nw = 1;
    return 0;
}

fn gui_app_free(app: &mut GApp) {
    if (app.px != null) {
        free(app.px);
        app.px = null;
        app.surface.p = null;
    }
    app.nw = 0;
}

fn gui_add(app: &mut GApp, kind: i64, parent: i64, text: ptr<u8>) -> i64 {
    if (app.nw >= GUI_MAX_WIDGETS) {
        return -1;
    }
    var wd: GWidget = zero(GWidget);
    wd.kind = kind;
    wd.id = app.nw;
    wd.parent = parent;
    wd.layout = GL_COL;
    wd.pad = 0;
    wd.gap = app.theme.gap;
    wd.visible = 1;
    wd.enabled = 1;
    wd.hot = 0;
    wd.active = 0;
    wd.focus = 0;
    wd.value = 0;
    wd.vmin = 0;
    wd.vmax = 100;
    wd.align = GA_LEFT;
    wd.text = text;
    if (kind == GK_FIELD) {
        var bp: ptr<u8> = null;
        unsafe { bp = &mut wd.buf[0] as ptr<u8>; }
        if (text != null) {
            wd.blen = gui_copy(bp, text, GUI_TEXT_MAX);
        }
    }
    let id: i64 = app.nw;
    app.widgets[id] = wd;
    app.nw = id + 1;
    app.dirty = 1;
    return id;
}

fn gui_set_size(app: &mut GApp, id: i64, w: i64, h: i64) {
    if (id < 0 || id >= app.nw) {
        return;
    }
    app.widgets[id].fw = w;
    app.widgets[id].fh = h;
    app.dirty = 1;
}

fn gui_set_grow(app: &mut GApp, id: i64, weight: i64) {
    if (id < 0 || id >= app.nw) {
        return;
    }
    app.widgets[id].grow = weight;
    app.dirty = 1;
}

fn gui_set_fill(app: &mut GApp, id: i64, on: i64) {
    if (id < 0 || id >= app.nw) {
        return;
    }
    app.widgets[id].fill = on;
    app.dirty = 1;
}

fn gui_set_pad(app: &mut GApp, id: i64, pad: i64, gap: i64) {
    if (id < 0 || id >= app.nw) {
        return;
    }
    app.widgets[id].pad = pad;
    app.widgets[id].gap = gap;
    app.dirty = 1;
}

fn gui_set_layout(app: &mut GApp, id: i64, axis: i64) {
    if (id < 0 || id >= app.nw) {
        return;
    }
    app.widgets[id].layout = axis;
    app.dirty = 1;
}

fn gui_set_align(app: &mut GApp, id: i64, align: i64) {
    if (id < 0 || id >= app.nw) {
        return;
    }
    app.widgets[id].align = align;
    app.dirty = 1;
}

fn gui_set_text(app: &mut GApp, id: i64, text: ptr<u8>) {
    if (id < 0 || id >= app.nw) {
        return;
    }
    app.widgets[id].text = text;
    if (app.widgets[id].kind == GK_FIELD) {
        var bp: ptr<u8> = null;
        unsafe { bp = &mut app.widgets[id].buf[0] as ptr<u8>; }
        app.widgets[id].blen = gui_copy(bp, text, GUI_TEXT_MAX);
        app.widgets[id].caret = app.widgets[id].blen;
    }
    app.dirty = 1;
}

fn gui_set_visible(app: &mut GApp, id: i64, on: i64) {
    if (id < 0 || id >= app.nw) {
        return;
    }
    app.widgets[id].visible = on;
    app.dirty = 1;
}

fn gui_set_enabled(app: &mut GApp, id: i64, on: i64) {
    if (id < 0 || id >= app.nw) {
        return;
    }
    app.widgets[id].enabled = on;
    app.dirty = 1;
}

fn gui_set_range(app: &mut GApp, id: i64, lo: i64, hi: i64) {
    if (id < 0 || id >= app.nw) {
        return;
    }
    if (hi <= lo) {
        hi = lo + 1;
    }
    app.widgets[id].vmin = lo;
    app.widgets[id].vmax = hi;
    app.dirty = 1;
}

fn gui_set_value(app: &mut GApp, id: i64, v: i64) {
    if (id < 0 || id >= app.nw) {
        return;
    }
    app.widgets[id].value = gui_clampi(v, app.widgets[id].vmin, app.widgets[id].vmax);
    app.dirty = 1;
}

fn gui_value(app: &mut GApp, id: i64) -> i64 {
    if (id < 0 || id >= app.nw) {
        return 0;
    }
    return app.widgets[id].value;
}

fn gui_widget_x(app: &mut GApp, id: i64) -> i64 {
    if (id < 0 || id >= app.nw) {
        return 0;
    }
    return app.widgets[id].x;
}

fn gui_widget_y(app: &mut GApp, id: i64) -> i64 {
    if (id < 0 || id >= app.nw) {
        return 0;
    }
    return app.widgets[id].y;
}

fn gui_widget_w(app: &mut GApp, id: i64) -> i64 {
    if (id < 0 || id >= app.nw) {
        return 0;
    }
    return app.widgets[id].w;
}

fn gui_widget_h(app: &mut GApp, id: i64) -> i64 {
    if (id < 0 || id >= app.nw) {
        return 0;
    }
    return app.widgets[id].h;
}

fn gui_focus(app: &mut GApp) -> i64 {
    return app.focus;
}

fn gui_set_number(app: &mut GApp, id: i64, v: i64) {
    if (id < 0 || id >= app.nw) {
        return;
    }
    var bp: ptr<u8> = null;
    unsafe { bp = &mut app.widgets[id].buf[0] as ptr<u8>; }
    gui_itoa(bp, v);
    app.widgets[id].text = bp;
    app.dirty = 1;
}

fn gui_set_buf(app: &mut GApp, id: i64, s: ptr<u8>) {
    if (id < 0 || id >= app.nw) {
        return;
    }
    var bp: ptr<u8> = null;
    unsafe { bp = &mut app.widgets[id].buf[0] as ptr<u8>; }
    gui_copy(bp, s, GUI_TEXT_MAX);
    app.widgets[id].text = bp;
    app.dirty = 1;
}

fn gui_field_text(app: &mut GApp, id: i64) -> ptr<u8> {    if (id < 0 || id >= app.nw) {
        return null;
    }
    var p: ptr<u8> = null;
    unsafe { p = &mut app.widgets[id].buf[0] as ptr<u8>; }
    return p;
}

fn gui_push(app: &mut GApp, id: i64, code: i64, value: i64) {
    if (app.nev >= GUI_MAX_EVENTS) {
        return;
    }
    let at: i64 = (app.evh + app.nev) % GUI_MAX_EVENTS;
    app.events[at].id = id;
    app.events[at].code = code;
    app.events[at].value = value;
    app.nev += 1;
}

fn gui_next_event(app: &mut GApp, ev: &mut GEvent) -> i32 {
    if (app.nev <= 0) {
        return 0;
    }
    let at: i64 = app.evh;
    ev.id = app.events[at].id;
    ev.code = app.events[at].code;
    ev.value = app.events[at].value;
    app.evh = (app.evh + 1) % GUI_MAX_EVENTS;
    app.nev -= 1;
    return 1;
}

fn gui_natural_w(app: &mut GApp, id: i64) -> i64 {
    let s: i64 = app.theme.scale;
    let u: i64 = app.theme.unit * s;
    let k: i64 = app.widgets[id].kind;
    if (k == GK_LABEL) {
        return gui_text_w(app.widgets[id].text, s);
    }
    if (k == GK_BUTTON) {
        return gui_text_w(app.widgets[id].text, s) + u * 6;
    }
    if (k == GK_CHECK) {
        return gui_text_w(app.widgets[id].text, s) + u * 6;
    }
    if (k == GK_FIELD) {
        return u * 30;
    }
    if (k == GK_SLIDER) {
        return u * 30;
    }
    if (k == GK_PROGRESS) {
        return u * 30;
    }
    if (app.widgets[id].fw > 0) {
        return app.widgets[id].fw;
    }
    return 0;
}

fn gui_natural_h(app: &mut GApp, id: i64) -> i64 {
    let s: i64 = app.theme.scale;
    let k: i64 = app.widgets[id].kind;
    if (k == GK_PANEL) {
        return app.widgets[id].fh;
    }
    if (k == GK_LABEL) {
        return gui_text_h(s) + 2;
    }
    if (k == GK_BUTTON) {
        return app.theme.row;
    }
    if (k == GK_CHECK) {
        return app.theme.row;
    }
    if (k == GK_FIELD) {
        return app.theme.row;
    }
    if (k == GK_SLIDER) {
        return app.theme.row;
    }
    if (k == GK_PROGRESS) {
        return app.theme.row;
    }
    return app.theme.row;
}

fn gui_min_size(app: &mut GApp, id: i64, axis: i64) -> i64 {
    if (axis == GL_ROW) {
        if (app.widgets[id].fw > 0) {
            return app.widgets[id].fw;
        }
        return gui_natural_w(app, id);
    }
    if (app.widgets[id].fh > 0) {
        return app.widgets[id].fh;
    }
    return gui_natural_h(app, id);
}

fn gui_layout_children(app: &mut GApp, pi: i64) {
    let pad: i64 = app.widgets[pi].pad;
    let gap: i64 = app.widgets[pi].gap;
    let axis: i64 = app.widgets[pi].layout;
    let cx: i64 = app.widgets[pi].x + pad;
    let cy: i64 = app.widgets[pi].y + pad;
    let cw: i64 = app.widgets[pi].w - pad * 2;
    let ch: i64 = app.widgets[pi].h - pad * 2;
    var total: i64 = cw;
    if (axis != GL_ROW) {
        total = ch;
    }
    var fixed: i64 = 0;
    var weight: i64 = 0;
    var n: i64 = 0;
    var i: i64 = 0;
    while (i < app.nw) {
        if (app.widgets[i].parent == pi && app.widgets[i].visible == 1) {
            n += 1;
            if (app.widgets[i].grow > 0) {
                weight += app.widgets[i].grow;
            } else {
                fixed += gui_min_size(app, i, axis);
            }
        }
        i += 1;
    }
    var free: i64 = total - fixed;
    if (n > 1) {
        free = free - gap * (n - 1);
    }
    if (free < 0) {
        free = 0;
    }
    var pos: i64 = cy;
    if (axis == GL_ROW) {
        pos = cx;
    }
    i = 0;
    while (i < app.nw) {
        if (app.widgets[i].parent == pi && app.widgets[i].visible == 1) {
            var main: i64 = 0;
            if (app.widgets[i].grow > 0 && weight > 0) {
                main = free * app.widgets[i].grow / weight;
            } else {
                main = gui_min_size(app, i, axis);
            }
            if (axis == GL_ROW) {
                app.widgets[i].x = pos;
                app.widgets[i].y = cy;
                app.widgets[i].w = main;
                if (app.widgets[i].fill == 1) {
                    app.widgets[i].h = ch;
                } else if (app.widgets[i].fh > 0) {
                    app.widgets[i].h = app.widgets[i].fh;
                } else {
                    app.widgets[i].h = gui_natural_h(app, i);
                }
            } else {
                app.widgets[i].y = pos;
                app.widgets[i].x = cx;
                app.widgets[i].h = main;
                if (app.widgets[i].fill == 1) {
                    app.widgets[i].w = cw;
                } else if (app.widgets[i].fw > 0) {
                    app.widgets[i].w = app.widgets[i].fw;
                } else {
                    app.widgets[i].w = gui_natural_w(app, i);
                }
                if (app.widgets[i].align == GA_CENTER) {
                    app.widgets[i].x = cx + (cw - app.widgets[i].w) / 2;
                } else if (app.widgets[i].align == GA_RIGHT) {
                    app.widgets[i].x = cx + cw - app.widgets[i].w;
                }
            }
            if (app.widgets[i].align == GA_CENTER && axis == GL_ROW) {
                app.widgets[i].y = cy + (ch - app.widgets[i].h) / 2;
            }
            pos += main + gap;
        }
        i += 1;
    }
}

fn gui_layout(app: &mut GApp) {
    app.widgets[0].x = 0;
    app.widgets[0].y = 0;
    app.widgets[0].w = app.w;
    app.widgets[0].h = app.h;
    var i: i64 = 0;
    while (i < app.nw) {
        if (app.widgets[i].kind == GK_PANEL && app.widgets[i].visible == 1) {
            gui_layout_children(app, i);
        }
        i += 1;
    }
}

fn gui_hit(app: &mut GApp, x: i64, y: i64) -> i64 {
    var i: i64 = app.nw - 1;
    while (i > 0) {
        if (app.widgets[i].visible == 1 && app.widgets[i].enabled == 1
            && app.widgets[i].kind != GK_PANEL) {
            let w: i64 = app.widgets[i].w;
            let h: i64 = app.widgets[i].h;
            if (x >= app.widgets[i].x && y >= app.widgets[i].y
                && x < app.widgets[i].x + w && y < app.widgets[i].y + h) {
                return i;
            }
        }
        i -= 1;
    }
    return -1;
}

fn gui_set_focus(app: &mut GApp, id: i64) {
    if (app.focus == id) {
        return;
    }
    if (app.focus >= 0) {
        app.widgets[app.focus].focus = 0;
        let old: i64 = app.focus;
        gui_push(app, old, GEV_BLUR, 0);
    }
    app.focus = id;
    if (id >= 0) {
        app.widgets[id].focus = 1;
        gui_push(app, id, GEV_FOCUS, 0);
    }
    app.dirty = 1;
}

fn gui_slider_at(app: &mut GApp, id: i64, x: i64) {
    let s: i64 = app.theme.scale;
    let knob: i64 = app.theme.unit * 3 * s;
    var span: i64 = app.widgets[id].w - knob;
    if (span < 1) {
        span = 1;
    }
    var t: i64 = x - app.widgets[id].x - knob / 2;
    t = gui_clampi(t, 0, span);
    let lo: i64 = app.widgets[id].vmin;
    let hi: i64 = app.widgets[id].vmax;
    let v: i64 = lo + (hi - lo) * t / span;
    if (v != app.widgets[id].value) {
        app.widgets[id].value = v;
        gui_push(app, id, GEV_CHANGE, v);
        app.dirty = 1;
    }
}

fn gui_field_caret_at(app: &mut GApp, id: i64, x: i64) {
    let s: i64 = app.theme.scale;
    let u: i64 = app.theme.unit * s;
    let cw: i64 = 6 * s;
    var t: i64 = x - app.widgets[id].x - u * 2;
    var c: i64 = t / cw;
    app.widgets[id].caret = gui_clampi(c, 0, app.widgets[id].blen);
    app.dirty = 1;
}

fn gui_mouse_move(app: &mut GApp, x: i64, y: i64) -> i32 {
    app.mx = x;
    app.my = y;
    if (app.drag >= 0) {
        gui_slider_at(app, app.drag, x);
        return 1;
    }
    let h: i64 = gui_hit(app, x, y);
    if (h != app.hot) {
        if (app.hot >= 0) {
            app.widgets[app.hot].hot = 0;
        }
        app.hot = h;
        if (h >= 0) {
            app.widgets[h].hot = 1;
        }
        app.dirty = 1;
        return 1;
    }
    return 0;
}

fn gui_mouse_down(app: &mut GApp, x: i64, y: i64) -> i32 {
    app.down = 1;
    app.mx = x;
    app.my = y;
    let h: i64 = gui_hit(app, x, y);
    if (h < 0) {
        gui_set_focus(app, -1);
        return 0;
    }
    let k: i64 = app.widgets[h].kind;
    if (k == GK_FIELD) {
        gui_set_focus(app, h);
        gui_field_caret_at(app, h, x);
        app.press = h;
        return 1;
    }
    if (k == GK_SLIDER) {
        gui_set_focus(app, h);
        app.drag = h;
        app.press = h;
        app.widgets[h].active = 1;
        gui_slider_at(app, h, x);
        return 1;
    }
    if (k == GK_BUTTON) {
        gui_set_focus(app, h);
        app.press = h;
        app.widgets[h].active = 1;
        app.dirty = 1;
        return 1;
    }
    if (k == GK_CHECK) {
        gui_set_focus(app, h);
        app.press = h;
        app.widgets[h].active = 1;
        app.dirty = 1;
        return 1;
    }
    app.press = h;
    return 1;
}

fn gui_mouse_up(app: &mut GApp, x: i64, y: i64) -> i32 {
    app.down = 0;
    app.mx = x;
    app.my = y;
    if (app.drag >= 0) {
        app.drag = -1;
    }
    let p: i64 = app.press;
    app.press = -1;
    if (p < 0) {
        return 0;
    }
    app.widgets[p].active = 0;
    app.dirty = 1;
    let h: i64 = gui_hit(app, x, y);
    if (h != p) {
        return 0;
    }
    let k: i64 = app.widgets[p].kind;
    if (k == GK_BUTTON) {
        gui_push(app, p, GEV_CLICK, 0);
        return 1;
    }
    if (k == GK_CHECK) {
        if (app.widgets[p].value == 0) {
            app.widgets[p].value = 1;
        } else {
            app.widgets[p].value = 0;
        }
        gui_push(app, p, GEV_TOGGLE, app.widgets[p].value);
        return 1;
    }
    return 0;
}

fn gui_wheel(app: &mut GApp, delta: i64) -> i32 {
    let f: i64 = app.focus;
    if (f < 0) {
        return 0;
    }
    if (app.widgets[f].kind != GK_SLIDER) {
        return 0;
    }
    let lo: i64 = app.widgets[f].vmin;
    let hi: i64 = app.widgets[f].vmax;
    var step: i64 = (hi - lo) / 20;
    if (step < 1) {
        step = 1;
    }
    let v: i64 = gui_clampi(app.widgets[f].value + step * delta, lo, hi);
    if (v != app.widgets[f].value) {
        app.widgets[f].value = v;
        gui_push(app, f, GEV_CHANGE, v);
        app.dirty = 1;
        return 1;
    }
    return 0;
}

fn gui_field_insert(app: &mut GApp, id: i64, ch: i64) {
    if (ch < 32 || ch > 126) {
        return;
    }
    if (app.widgets[id].blen >= GUI_TEXT_MAX - 1) {
        return;
    }
    var i: i64 = app.widgets[id].blen;
    unsafe {
        while (i > app.widgets[id].caret) {
            app.widgets[id].buf[i] = app.widgets[id].buf[i - 1];
            i -= 1;
        }
        app.widgets[id].buf[app.widgets[id].caret] = ch as u8;
        app.widgets[id].blen += 1;
        app.widgets[id].buf[app.widgets[id].blen] = 0;
    }
    app.widgets[id].caret += 1;
    app.dirty = 1;
    gui_push(app, id, GEV_CHANGE, app.widgets[id].blen);
}

fn gui_field_delete(app: &mut GApp, id: i64, back: i64) {
    if (app.widgets[id].blen <= 0) {
        return;
    }
    var at: i64 = app.widgets[id].caret;
    if (back == 1) {
        if (at <= 0) {
            return;
        }
        at -= 1;
    } else if (at >= app.widgets[id].blen) {
        return;
    }
    unsafe {
        var i: i64 = at;
        while (i < app.widgets[id].blen - 1) {
            app.widgets[id].buf[i] = app.widgets[id].buf[i + 1];
            i += 1;
        }
        app.widgets[id].blen -= 1;
        app.widgets[id].buf[app.widgets[id].blen] = 0;
    }
    app.widgets[id].caret = at;
    app.dirty = 1;
    gui_push(app, id, GEV_CHANGE, app.widgets[id].blen);
}

fn gui_key(app: &mut GApp, vk: i64, ch: i64) -> i32 {
    let f: i64 = app.focus;
    if (f < 0) {
        return 0;
    }
    let k: i64 = app.widgets[f].kind;
    if (k == GK_FIELD) {
        if (vk == VK_BACK) {
            gui_field_delete(app, f, 1);
            return 1;
        }
        if (vk == VK_DELETE) {
            gui_field_delete(app, f, 0);
            return 1;
        }
        if (vk == VK_LEFT) {
            app.widgets[f].caret = gui_clampi(app.widgets[f].caret - 1, 0, app.widgets[f].blen);
            app.dirty = 1;
            return 1;
        }
        if (vk == VK_RIGHT) {
            app.widgets[f].caret = gui_clampi(app.widgets[f].caret + 1, 0, app.widgets[f].blen);
            app.dirty = 1;
            return 1;
        }
        if (vk == VK_HOME) {
            app.widgets[f].caret = 0;
            app.dirty = 1;
            return 1;
        }
        if (vk == VK_END) {
            app.widgets[f].caret = app.widgets[f].blen;
            app.dirty = 1;
            return 1;
        }
        if (vk == VK_RETURN) {
            gui_push(app, f, GEV_SUBMIT, app.widgets[f].blen);
            return 1;
        }
        if (ch >= 32 && ch <= 126) {
            gui_field_insert(app, f, ch);
            return 1;
        }
        return 0;
    }
    if (vk == VK_SPACE || vk == VK_RETURN) {
        if (k == GK_BUTTON) {
            gui_push(app, f, GEV_CLICK, 0);
            return 1;
        }
        if (k == GK_CHECK) {
            if (app.widgets[f].value == 0) {
                app.widgets[f].value = 1;
            } else {
                app.widgets[f].value = 0;
            }
            gui_push(app, f, GEV_TOGGLE, app.widgets[f].value);
            app.dirty = 1;
            return 1;
        }
    }
    if (vk == VK_LEFT || vk == VK_DOWN) {
        return gui_wheel(app, -1);
    }
    if (vk == VK_RIGHT || vk == VK_UP) {
        return gui_wheel(app, 1);
    }
    return 0;
}

fn gui_timer(app: &mut GApp) -> i32 {
    app.frames += 1;
    app.dirty = 1;
    gui_push(app, -1, GEV_TIMER, app.frames);
    return 1;
}

fn gui_draw_text_c(s: &GSurface, x: i64, y: i64, w: i64, t: ptr<u8>, c: GColor, scale: i64, align: i64) {
    var tx: i64 = x;
    if (align == GA_CENTER) {
        tx = x + (w - gui_text_w(t, scale)) / 2;
    } else if (align == GA_RIGHT) {
        tx = x + w - gui_text_w(t, scale);
    }
    gs_text(s, tx, y, t, c, scale);
}

fn gui_draw_panel(app: &mut GApp, i: i64) {
    let t: GTheme = app.theme;
    let wd: GWidget = app.widgets[i];
    gs_fill(&app.surface, wd.x, wd.y, wd.w, wd.h, t.face);
    gs_rect(&app.surface, wd.x, wd.y, wd.w, wd.h, t.edge);
    if (wd.text != null && gui_len(wd.text) > 0) {
        gs_fill(&app.surface, wd.x, wd.y, wd.w, t.row, t.face_hot);
        gs_hline(&app.surface, wd.x, wd.y + t.row - 1, wd.w, t.edge);
        gs_text(&app.surface, wd.x + t.unit * t.scale, wd.y + (t.row - gui_text_h(t.scale)) / 2,
                wd.text, t.ink, t.scale);
    }
}

fn gui_draw_label(app: &mut GApp, i: i64) {
    let t: GTheme = app.theme;
    let wd: GWidget = app.widgets[i];
    let c: GColor = t.ink;
    gs_text(&app.surface, wd.x, wd.y + (wd.h - gui_text_h(t.scale)) / 2, wd.text, c, t.scale);
}

fn gui_draw_button(app: &mut GApp, i: i64) {
    let t: GTheme = app.theme;
    let wd: GWidget = app.widgets[i];
    var face: GColor = t.face;
    if (wd.active == 1) {
        face = t.face_down;
    } else if (wd.hot == 1) {
        face = t.face_hot;
    }
    if (wd.enabled == 0) {
        face = t.face_down;
    }
    gs_fill(&app.surface, wd.x, wd.y, wd.w, wd.h, face);
    gs_rect(&app.surface, wd.x, wd.y, wd.w, wd.h, t.edge_hi);
    var ink: GColor = t.ink;
    if (wd.enabled == 0) {
        ink = t.ink_dim;
    }
    var dy: i64 = 0;
    if (wd.active == 1) {
        dy = 1;
    }
    gui_draw_text_c(&app.surface, wd.x, wd.y + (wd.h - gui_text_h(t.scale)) / 2 + dy, wd.w,
                    wd.text, ink, t.scale, GA_CENTER);
    if (wd.focus == 1) {
        gs_rect(&app.surface, wd.x - 2, wd.y - 2, wd.w + 4, wd.h + 4, t.accent);
    }
}

fn gui_draw_check(app: &mut GApp, i: i64) {
    let t: GTheme = app.theme;
    let wd: GWidget = app.widgets[i];
    let s: i64 = t.scale;
    let bx: i64 = 6 * s + 2;
    let by: i64 = wd.y + (wd.h - bx) / 2;
    gs_fill(&app.surface, wd.x, by, bx, bx, t.sunken);
    gs_rect(&app.surface, wd.x, by, bx, bx, t.edge_hi);
    if (wd.value != 0) {
        let m: i64 = t.unit * 2 * s;
        gs_fill(&app.surface, wd.x + m, by + m, bx - m * 2, bx - m * 2, t.accent);
    }
    gs_text(&app.surface, wd.x + bx + t.unit * s, wd.y + (wd.h - gui_text_h(s)) / 2,
            wd.text, t.ink, s);
    if (wd.focus == 1) {
        gs_rect(&app.surface, wd.x - 2, by - 2, bx + 4, bx + 4, t.accent);
    }
}

fn gui_draw_field(app: &mut GApp, i: i64) {
    let t: GTheme = app.theme;
    let wd: GWidget = app.widgets[i];
    let s: i64 = t.scale;
    let u: i64 = t.unit * s;
    gs_fill(&app.surface, wd.x, wd.y, wd.w, wd.h, t.sunken);
    gs_rect(&app.surface, wd.x, wd.y, wd.w, wd.h, t.edge_hi);
    var tx: i64 = wd.x + u * 2;
    let ty: i64 = wd.y + (wd.h - gui_text_h(s)) / 2;
    var bp: ptr<u8> = null;
    unsafe { bp = &mut app.widgets[i].buf[0] as ptr<u8>; }
    gs_text(&app.surface, tx, ty, bp, t.ink, s);
    if (wd.focus == 1) {
        let cx: i64 = tx + wd.caret * 6 * s;
        gs_fill(&app.surface, cx, wd.y + u, 1 * s, wd.h - u * 2, t.accent);
    }
    gs_rect(&app.surface, wd.x - 1, wd.y - 1, wd.w + 2, wd.h + 2, t.accent);
}

fn gui_draw_slider(app: &mut GApp, i: i64) {
    let t: GTheme = app.theme;
    let wd: GWidget = app.widgets[i];
    let s: i64 = t.scale;
    let knob: i64 = t.unit * 3 * s;
    let cy: i64 = wd.y + wd.h / 2;
    let th: i64 = 2 * s;
    let span: i64 = wd.w - knob;
    gs_fill(&app.surface, wd.x, cy - th / 2, wd.w, th, t.track);
    var frac: i64 = 0;
    let lo: i64 = wd.vmin;
    let hi: i64 = wd.vmax;
    if (hi > lo) {
        frac = (wd.value - lo) * span / (hi - lo);
    }
    if (frac > 0) {
        gs_fill(&app.surface, wd.x, cy - th / 2, frac + knob / 2, th, t.accent);
    }
    gs_fill(&app.surface, wd.x + frac, cy - knob / 2, knob, knob, t.face_hot);
    gs_rect(&app.surface, wd.x + frac, cy - knob / 2, knob, knob, t.edge_hi);
    gs_fill(&app.surface, wd.x + frac + knob / 2 - s, cy - s, 2 * s, 2 * s, t.accent);
    if (wd.focus == 1) {
        gs_rect(&app.surface, wd.x - 2, wd.y, wd.w + 4, wd.h, t.accent);
    }
}

fn gui_draw_progress(app: &mut GApp, i: i64) {
    let t: GTheme = app.theme;
    let wd: GWidget = app.widgets[i];
    let s: i64 = t.scale;
    let u: i64 = t.unit * s;
    gs_fill(&app.surface, wd.x, wd.y, wd.w, wd.h, t.sunken);
    gs_rect(&app.surface, wd.x, wd.y, wd.w, wd.h, t.edge_hi);
    var frac: i64 = 0;
    let lo: i64 = wd.vmin;
    let hi: i64 = wd.vmax;
    if (hi > lo) {
        frac = gui_clampi((wd.value - lo) * (wd.w - u * 2) / (hi - lo), 0, wd.w - u * 2);
    }
    if (frac > 0) {
        gs_fill(&app.surface, wd.x + u, wd.y + u, frac, wd.h - u * 2, t.accent);
    }
    var tmp: [u8; 24] = [0];
    var tp: ptr<u8> = null;
    unsafe { tp = &mut tmp[0] as ptr<u8>; }
    var pct: i64 = 0;
    if (hi > lo) {
        pct = (wd.value - lo) * 100 / (hi - lo);
    }
    gui_itoa(tp, pct);
    let n: i64 = gui_len(tp);
    unsafe {
        tp[n] = 37;
        tp[n + 1] = 0;
    }
    gs_text(&app.surface, wd.x + wd.w - gui_text_w(tp, s) - u * 2,
            wd.y + (wd.h - gui_text_h(s)) / 2, tp, t.ink, s);
}

fn gui_render(app: &mut GApp) -> i32 {
    gui_layout(app);
    let t: GTheme = app.theme;
    gs_clear(&app.surface, t.bg);
    var i: i64 = 0;
    while (i < app.nw) {
        if (app.widgets[i].visible == 1) {
            let k: i64 = app.widgets[i].kind;
            if (k == GK_PANEL) {
                gui_draw_panel(app, i);
            } else if (k == GK_LABEL) {
                gui_draw_label(app, i);
            } else if (k == GK_BUTTON) {
                gui_draw_button(app, i);
            } else if (k == GK_CHECK) {
                gui_draw_check(app, i);
            } else if (k == GK_FIELD) {
                gui_draw_field(app, i);
            } else if (k == GK_SLIDER) {
                gui_draw_slider(app, i);
            } else if (k == GK_PROGRESS) {
                gui_draw_progress(app, i);
            }
        }
        i += 1;
    }
    app.dirty = 0;
    return 0;
}

fn gui_hash(app: &mut GApp) -> u64 {
    var h: u64 = 1469598103934665603 as u64;
    let n: i64 = app.w * app.h;
    var i: i64 = 0;
    unsafe {
        let p: ptr<u32> = app.surface.p;
        while (i < n) {
            let v: u64 = p[i] as u64;
            h = (h ^ v) * 1099511628211;
            i += 1;
        }
    }
    return h;
}
