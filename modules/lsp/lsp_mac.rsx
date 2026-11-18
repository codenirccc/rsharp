include "lsp.rsx";

extern "system" fn read(fd: i32, buf: ptr<u8>, n: u64) -> i64;
extern "system" fn write(fd: i32, buf: ptr<u8>, n: u64) -> i64;

fn lsp_read(p: ptr<u8>, cap: i64) -> i64 {
    if (cap <= 0) {
        return 0;
    }
    return read(0, p, cap as u64);
}

fn lsp_write(p: ptr<u8>, n: i64) -> i32 {
    if (n <= 0) {
        return 1;
    }
    var off: i64 = 0;
    while (off < n) {
        var at: ptr<u8> = null;
        unsafe { at = p + off; }
        let w: i64 = write(1, at, (n - off) as u64);
        if (w <= 0) {
            return 0;
        }
        off += w;
    }
    return 1;
}
