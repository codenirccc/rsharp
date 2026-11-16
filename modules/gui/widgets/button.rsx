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
