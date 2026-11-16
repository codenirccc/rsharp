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
