fn gui_clampi(v: i64, lo: i64, hi: i64) -> i64 {
    if (v < lo) {
        return lo;
    }
    if (v > hi) {
        return hi;
    }
    return v;
}
