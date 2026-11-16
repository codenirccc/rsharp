include "rt.rsx";

extern "crypt32" fn CertOpenSystemStoreW(h: u64, name: ptr<u8>) -> u64;
extern "crypt32" fn CertEnumCertificatesInStore(store: u64, prev: ptr<u8>) -> ptr<u8>;
extern "crypt32" fn CertFreeCertificateContext(ctx: ptr<u8>) -> i32;
extern "crypt32" fn CertCloseStore(store: u64, flags: i32) -> i32;

struct WinCertContext {
    enc_type: i32,
    pad0: i32,
    enc: ptr<u8>,
    enc_len: i32,
    pad1: i32,
    info: ptr<u8>,
    store: u64
}

struct Roots {
    store: u64,
    cur: ptr<u8>
}

fn roots_win_wide(out: ptr<u8>, s: ptr<u8>) -> i32 {
    var i: i64 = 0;
    var done: i32 = 0;
    while (done == 0) {
        if (i >= 32) {
            return -1;
        }
        var ch: u8 = 0;
        unsafe { ch = s[i]; }
        rt_setbyte(out, i * 2, ch);
        rt_setbyte(out, i * 2 + 1, 0);
        if (ch == 0) {
            done = 1;
        }
        i += 1;
    }
    return 0;
}

fn roots_open(r: &mut Roots) -> i32 {
    r.store = 0;
    r.cur = null;
    var wbuf: [u8; 64] = [0];
    var wp: ptr<u8> = null;
    unsafe { wp = &mut wbuf[0] as ptr<u8>; }
    if (roots_win_wide(wp, "ROOT") != 0) {
        return -1;
    }
    let h: u64 = CertOpenSystemStoreW(0, wp);
    if (h == 0) {
        return -1;
    }
    r.store = h;
    return 0;
}

fn roots_next(r: &mut Roots, out: &mut RtBlob) -> i32 {
    out.p = null;
    out.len = 0;
    if (r.store == 0) {
        return 0;
    }
    let ctx: ptr<u8> = CertEnumCertificatesInStore(r.store, r.cur);
    r.cur = ctx;
    if (ctx == null) {
        return 0;
    }
    var node: ptr<WinCertContext> = null;
    unsafe { node = ctx as ptr<WinCertContext>; }
    var p: ptr<u8> = null;
    var n: i32 = 0;
    unsafe {
        p = node.enc;
        n = node.enc_len;
    }
    if (p == null || n <= 0) {
        return -1;
    }
    out.p = p;
    out.len = n as i64;
    return 1;
}

fn roots_close(r: &mut Roots) -> i32 {
    if (r.cur != null) {
        CertFreeCertificateContext(r.cur);
        r.cur = null;
    }
    if (r.store != 0) {
        CertCloseStore(r.store, 0);
        r.store = 0;
    }
    return 0;
}
