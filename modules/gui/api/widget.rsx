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
