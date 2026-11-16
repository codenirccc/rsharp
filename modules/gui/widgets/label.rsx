fn gui_draw_label(app: &mut GApp, i: i64) {
    let t: GTheme = app.theme;
    let wd: GWidget = app.widgets[i];
    let c: GColor = t.ink;
    gs_text(&app.surface, wd.x, wd.y + (wd.h - gui_text_h(t.scale)) / 2, wd.text, c, t.scale);
}
