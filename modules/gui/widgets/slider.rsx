fn gui_draw_slider(app: &mut GApp, i: i64) {
    let t: GTheme = app.theme;
    let wd: GWidget = app.widgets[i];
    let s: i64 = t.scale;
    let knob: i64 = t.unit * 3 * s;
    let cy: i64 = wd.y + wd.h / 2;
    let th: i64 = 2 * s;
    let span: i64 = wd.w - knob;
    gs_fill(&app.surface, wd.x, cy - th / 2, wd.w, th, t.track);
    var frac: i64 = 0;
    let lo: i64 = wd.vmin;
    let hi: i64 = wd.vmax;
    if (hi > lo) {
        frac = (wd.value - lo) * span / (hi - lo);
    }
    if (frac > 0) {
        gs_fill(&app.surface, wd.x, cy - th / 2, frac + knob / 2, th, t.accent);
    }
    gs_fill(&app.surface, wd.x + frac, cy - knob / 2, knob, knob, t.face_hot);
    gs_rect(&app.surface, wd.x + frac, cy - knob / 2, knob, knob, t.edge_hi);
    gs_fill(&app.surface, wd.x + frac + knob / 2 - s, cy - s, 2 * s, 2 * s, t.accent);
    if (wd.focus == 1) {
        gs_rect(&app.surface, wd.x - 2, wd.y, wd.w + 4, wd.h, t.accent);
    }
}
