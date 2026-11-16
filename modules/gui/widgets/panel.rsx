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
