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

fn gui_field_caret_at(app: &mut GApp, id: i64, x: i64) {
    let s: i64 = app.theme.scale;
    let u: i64 = app.theme.unit * s;
    let cw: i64 = 6 * s;
    var t: i64 = x - app.widgets[id].x - u * 2;
    var c: i64 = t / cw;
    app.widgets[id].caret = gui_clampi(c, 0, app.widgets[id].blen);
    app.dirty = 1;
}
