fn gui_len(s: ptr<u8>) -> i64 {
    if (s == null) {
        return 0;
    }
    return strlen(s) as i64;
}

fn gui_text_w(t: ptr<u8>, scale: i64) -> i64 {
    return strlen(t) as i64 * 6 * scale;
}

fn gui_text_h(scale: i64) -> i64 {
    return 7 * scale;
}
