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
