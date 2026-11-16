fn gui_draw_progress(app: &mut GApp, i: i64) {
    let t: GTheme = app.theme;
    let wd: GWidget = app.widgets[i];
    let s: i64 = t.scale;
    let u: i64 = t.unit * s;
    gs_fill(&app.surface, wd.x, wd.y, wd.w, wd.h, t.sunken);
    gs_rect(&app.surface, wd.x, wd.y, wd.w, wd.h, t.edge_hi);
    var frac: i64 = 0;
    let lo: i64 = wd.vmin;
    let hi: i64 = wd.vmax;
    if (hi > lo) {
        frac = gui_clampi((wd.value - lo) * (wd.w - u * 2) / (hi - lo), 0, wd.w - u * 2);
    }
    if (frac > 0) {
        gs_fill(&app.surface, wd.x + u, wd.y + u, frac, wd.h - u * 2, t.accent);
    }
    var tmp: [u8; 24] = [0];
    var tp: ptr<u8> = null;
    unsafe { tp = &mut tmp[0] as ptr<u8>; }
    var pct: i64 = 0;
    if (hi > lo) {
        pct = (wd.value - lo) * 100 / (hi - lo);
    }
    gui_itoa(tp, pct);
    let n: i64 = gui_len(tp);
    unsafe {
        tp[n] = 37;
        tp[n + 1] = 0;
    }
    gs_text(&app.surface, wd.x + wd.w - gui_text_w(tp, s) - u * 2,
            wd.y + (wd.h - gui_text_h(s)) / 2, tp, t.ink, s);
}
