fn gui_copy(dst: ptr<u8>, src: ptr<u8>, max: i64) -> i64 {
    var i: i64 = 0;
    unsafe {
        while (i < max - 1 && src[i] != 0) {
            dst[i] = src[i];
            i += 1;
        }
        dst[i] = 0;
    }
    return i;
}
