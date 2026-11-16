fn gui_draw_text_c(s: &GSurface, x: i64, y: i64, w: i64, t: ptr<u8>, c: GColor, scale: i64, align: i64) {
    var tx: i64 = x;
    if (align == GA_CENTER) {
        tx = x + (w - gui_text_w(t, scale)) / 2;
    } else if (align == GA_RIGHT) {
        tx = x + w - gui_text_w(t, scale);
    }
    gs_text(s, tx, y, t, c, scale);
}
