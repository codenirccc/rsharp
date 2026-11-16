struct GApp {
    w: i64,
    h: i64,
    nw: i64,
    hot: i64,
    press: i64,
    focus: i64,
    drag: i64,
    mx: i64,
    my: i64,
    down: i64,
    frames: i64,
    dirty: i64,
    quit: i64,
    pmx: i64,
    pmy: i64,
    nev: i64,
    evh: i64,
    px: ptr<u8>,
    surface: GSurface,
    theme: GTheme,
    widgets: [GWidget; GUI_MAX_WIDGETS],
    events: [GEvent; GUI_MAX_EVENTS]
}

fn gui_app_init(app: &mut GApp, w: i64, h: i64) -> i32 {
    if (w < 32 || h < 32) {
        return -1;
    }
    app.w = w;
    app.h = h;
    app.nw = 0;
    app.hot = -1;
    app.press = -1;
    app.focus = -1;
    app.drag = -1;
    app.mx = 0;
    app.my = 0;
    app.pmx = 0;
    app.pmy = 0;
    app.down = 0;
    app.frames = 0;
    app.dirty = 1;
    app.quit = 0;
    app.nev = 0;
    app.evh = 0;
    app.px = malloc((w * h * 4) as u64);
    if (app.px == null) {
        return -2;
    }
    var sp: ptr<u32> = null;
    unsafe { sp = app.px as ptr<u32>; }
    app.surface.p = sp;
    app.surface.w = w;
    app.surface.h = h;
    gui_theme_dark(&mut app.theme);
    var root: GWidget = zero(GWidget);
    root.kind = GK_PANEL;
    root.id = 0;
    root.parent = -1;
    root.layout = GL_COL;
    root.pad = app.theme.pad;
    root.gap = app.theme.gap;
    root.x = 0;
    root.y = 0;
    root.w = w;
    root.h = h;
    root.visible = 1;
    root.enabled = 1;
    app.widgets[0] = root;
    app.nw = 1;
    return 0;
}

fn gui_app_free(app: &mut GApp) {
    if (app.px != null) {
        free(app.px);
        app.px = null;
        app.surface.p = null;
    }
    var fi: i64 = 0;
    while (fi < app.nw) {
        if (app.widgets[fi].ink != null) {
            free(app.widgets[fi].ink);
            app.widgets[fi].ink = null;
        }
        fi += 1;
    }
    app.nw = 0;
}
