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
            } else if (k == GK_CANVAS) {
                gui_draw_canvas(app, i);
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
