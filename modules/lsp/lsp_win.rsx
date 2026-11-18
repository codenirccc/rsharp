include "lsp.rsx";

extern "kernel32" fn GetStdHandle(which: u32) -> i64;
extern "kernel32" fn ReadFile(h: i64, buf: ptr<u8>, n: u32, got: ptr<u32>, ov: ptr<u8>) -> i32;
extern "kernel32" fn WriteFile(h: i64, buf: ptr<u8>, n: u32, wrote: ptr<u32>, ov: ptr<u8>) -> i32;

const LSP_STD_IN: u32 = 4294967286;
const LSP_STD_OUT: u32 = 4294967285;

fn lsp_read(p: ptr<u8>, cap: i64) -> i64 {
    if (cap <= 0) {
        return 0;
    }
    var want: i64 = cap;
    if (want > 65536) {
        want = 65536;
    }
    let h: i64 = GetStdHandle(LSP_STD_IN);
    var got: u32 = 0;
    var ok: i32 = 0;
    unsafe { ok = ReadFile(h, p, want as u32, &mut got as ptr<u32>, null); }
    if (ok == 0 || got == 0) {
        return 0;
    }
    return got as i64;
}

fn lsp_write(p: ptr<u8>, n: i64) -> i32 {
    if (n <= 0) {
        return 1;
    }
    let h: i64 = GetStdHandle(LSP_STD_OUT);
    var off: i64 = 0;
    while (off < n) {
        var want: i64 = n - off;
        if (want > 65536) {
            want = 65536;
        }
        var at: ptr<u8> = null;
        unsafe { at = p + off; }
        var wrote: u32 = 0;
        var ok: i32 = 0;
        unsafe { ok = WriteFile(h, at, want as u32, &mut wrote as ptr<u32>, null); }
        if (ok == 0 || wrote == 0) {
            return 0;
        }
        off += wrote as i64;
    }
    return 1;
}
