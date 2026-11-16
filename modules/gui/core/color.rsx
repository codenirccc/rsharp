struct GColor {
    r: u8,
    g: u8,
    b: u8,
    pad: u8
}

fn gui_col(r: u8, g: u8, b: u8) -> GColor {
    var c: GColor = zero(GColor);
    c.r = r;
    c.g = g;
    c.b = b;
    c.pad = 0;
    return c;
}

fn gui_word(c: GColor) -> u32 {
    return (c.b as u32) | ((c.g as u32) << 8) | ((c.r as u32) << 16);
}
