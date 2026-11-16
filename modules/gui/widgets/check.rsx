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
