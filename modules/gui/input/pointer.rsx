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

fn gui_mouse_move(app: &mut GApp, x: i64, y: i64) -> i32 {
    app.mx = x;
    app.my = y;
    if (app.drag >= 0) {
        if (app.widgets[app.drag].kind == GK_CANVAS) {
            gui_canvas_stroke(app, app.drag, x, y);
        } else {
            gui_slider_at(app, app.drag, x);
        }
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
    if (k == GK_CANVAS) {
        gui_set_focus(app, h);
        app.drag = h;
        app.press = h;
        gui_canvas_begin(app, h, x, y);
        return 1;
    }
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
