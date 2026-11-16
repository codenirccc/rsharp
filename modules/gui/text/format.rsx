fn gui_itoa(out: ptr<u8>, v: i64) {
    var tmp: [u8; 24] = [0];
    var n: i64 = v;
    var i: i64 = 24;
    var neg: i64 = 0;
    if (n < 0) {
        neg = 1;
        n = 0 - n;
    }
    if (n == 0) {
        i -= 1;
        tmp[i] = 48;
    }
    while (n > 0) {
        i -= 1;
        tmp[i] = (48 + (n % 10)) as u8;
        n = n / 10;
    }
    if (neg == 1) {
        i -= 1;
        tmp[i] = 45;
    }
    var k: i64 = 0;
    unsafe {
        while (i < 24) {
            out[k] = tmp[i];
            k += 1;
            i += 1;
        }
        out[k] = 0;
    }
}
