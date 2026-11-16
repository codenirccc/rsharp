struct GTheme {
    scale: i64,
    pad: i64,
    gap: i64,
    row: i64,
    unit: i64,
    bg: GColor,
    face: GColor,
    face_hot: GColor,
    face_down: GColor,
    sunken: GColor,
    edge: GColor,
    edge_hi: GColor,
    ink: GColor,
    ink_dim: GColor,
    accent: GColor,
    accent_ink: GColor,
    track: GColor,
    mark: GColor
}

fn gui_theme_dark(t: &mut GTheme) {
    t.scale = 2;
    t.pad = 10;
    t.gap = 8;
    t.row = 24;
    t.unit = 4;
    t.bg = gui_col(24, 26, 32);
    t.face = gui_col(44, 48, 58);
    t.face_hot = gui_col(62, 68, 82);
    t.face_down = gui_col(30, 33, 40);
    t.sunken = gui_col(18, 20, 24);
    t.edge = gui_col(16, 17, 21);
    t.edge_hi = gui_col(86, 94, 112);
    t.ink = gui_col(228, 234, 244);
    t.ink_dim = gui_col(140, 148, 164);
    t.accent = gui_col(64, 196, 220);
    t.accent_ink = gui_col(12, 18, 22);
    t.track = gui_col(56, 60, 72);
    t.mark = gui_col(248, 212, 96);
}

fn gui_theme_light(t: &mut GTheme) {
    t.scale = 2;
    t.pad = 10;
    t.gap = 8;
    t.row = 24;
    t.unit = 4;
    t.bg = gui_col(238, 240, 244);
    t.face = gui_col(250, 251, 253);
    t.face_hot = gui_col(232, 238, 248);
    t.face_down = gui_col(214, 220, 230);
    t.sunken = gui_col(255, 255, 255);
    t.edge = gui_col(170, 176, 188);
    t.edge_hi = gui_col(120, 128, 144);
    t.ink = gui_col(28, 32, 40);
    t.ink_dim = gui_col(104, 112, 128);
    t.accent = gui_col(28, 122, 214);
    t.accent_ink = gui_col(250, 252, 255);
    t.track = gui_col(206, 212, 222);
    t.mark = gui_col(28, 122, 214);
}
