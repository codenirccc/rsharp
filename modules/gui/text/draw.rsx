fn gs_text(s: &GSurface, x: i64, y: i64, t: ptr<u8>, c: GColor, scale: i64) {
    if (t == null) {
        return;
    }
    let n: i64 = strlen(t) as i64;
    var i: i64 = 0;
    unsafe {
        while (i < n) {
            gs_char(s, x + i * 6 * scale, y, t[i] as i64, c, scale);
            i += 1;
        }
    }
}
