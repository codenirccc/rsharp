include "bx_parse.rsx";
include "bx_conv.rsx";
include "bx_io.rsx";

extern fn printf(fmt: ptr<u8>, ...) -> i32;

fn bx_emit(x: &mut Bp, pr: &mut Pr, out: &mut Sb) {
    bx_conv(x, pr);
    var a: Na = zero(Na);
    a = x.na;
    var l: Lp = zero(Lp);
    l = x.lp;
    var s: Sp = zero(Sp);
    s = x.sp;
    prog_w(&mut a, &mut l, &mut s, out, pr);
}

fn tb_diff(a: ptr<u8>, n: i64, b: ptr<u8>) -> i64 {
    var i: i64 = 0;
    while (i < n) {
        var ca: u8 = 0;
        var cb: u8 = 0;
        unsafe {
            ca = a[i];
            cb = b[i];
        }
        if (ca != cb) {
            return i;
        }
        i += 1;
    }
    return 0 - 1;
}

fn tb_one(path: ptr<u8>, outp: ptr<u8>) -> i32 {
    var b: Buf = io_read(path);
    if (b.p == null) {
        printf("bx: %s: cannot read\n", path);
        return 1;
    }
    var x: Bp = bp_new();
    var pr: Pr = bx_parse_ir(&mut x, b.p, b.n);
    if (bp_ok(&mut x) == 0) {
        let ep: ptr<u8> = bp_err_ptr(&mut x);
        let en: i64 = bp_err_len(&mut x);
        printf("bx: %s: malformed IR: %.*s\n", path, en as i32, ep);
        bp_free(&mut x);
        free(b.p);
        return 1;
    }
    var out: Sb = sb_new(b.n + 64);
    bx_emit(&mut x, &mut pr, &mut out);
    var rc: i32 = 0;
    if (outp != null) {
        let w: ptr<u8> = out.p;
        if (io_write(outp, w, out.n) == 0) {
            printf("bx: %s: cannot write\n", outp);
            rc = 1;
        }
    } else if (out.n != b.n) {
        printf("bx: %s: %lld bytes out, %lld in\n", path, out.n, b.n);
        rc = 1;
    } else {
        let at: i64 = tb_diff(out.p, out.n, b.p);
        if (at >= 0) {
            var got: [u8; 72] = [0];
            var want: [u8; 72] = [0];
            var k: i64 = 0;
            while (k < 44 && at + k < out.n) {
                var c1: u8 = 0;
                var c2: u8 = 0;
                unsafe {
                    c1 = out.p[at + k];
                    c2 = b.p[at + k];
                }
                if (c1 == 10) {
                    c1 = 32;
                }
                if (c2 == 10) {
                    c2 = 32;
                }
                got[k] = c1;
                want[k] = c2;
                k += 1;
            }
            got[k] = 0;
            want[k] = 0;
            let gp: ptr<u8> = p_u8(&mut got[0]);
            let wp: ptr<u8> = p_u8(&mut want[0]);
            printf("bx: %s: diff at %lld\n  out: %s\n  in:  %s\n", path, at, gp, wp);
            rc = 1;
        }
    }
    sb_free(&mut out);
    bp_free(&mut x);
    free(b.p);
    return rc;
}

fn tb_run(mpath: ptr<u8>) -> i32 {
    var m: Buf = io_read(mpath);
    if (m.p == null) {
        printf("bx: cannot read manifest %s\n", mpath);
        return 2;
    }
    var files: i64 = 0;
    var bad: i64 = 0;
    var i: i64 = 0;
    var start: i64 = 0;
    while (i <= m.n) {
        var c: u8 = 10;
        if (i < m.n) {
            unsafe { c = m.p[i]; }
        }
        if (c == 10) {
            if (i > start) {
                var line: [u8; 1024] = [0];
                var k: i64 = 0;
                while (start + k < i && k < 1023) {
                    var ch: u8 = 0;
                    unsafe { ch = m.p[start + k]; }
                    line[k] = ch;
                    k += 1;
                }
                line[k] = 0;
                let lp: ptr<u8> = p_u8(&mut line[0]);
                files += 1;
                if (tb_one(lp, null) != 0) {
                    bad += 1;
                }
            }
            start = i + 1;
        }
        i += 1;
    }
    free(m.p);
    printf("bx: %lld files, %lld bad\n", files, bad);
    if (bad != 0) {
        return 1;
    }
    return 0;
}

fn main() -> i32 {
    let argc: i64 = io_argc();
    if (argc < 2) {
        printf("usage: t_bx [-o out.rsi] <in.rsi>...\n       t_bx -m <manifest>\n");
        return 2;
    }
    var line: [u8; 1024] = [0];
    let lp: ptr<u8> = p_u8(&mut line[0]);
    io_arg(1, lp, 1024);
    var outp: [u8; 1024] = [0];
    let opp: ptr<u8> = p_u8(&mut outp[0]);
    var start: i64 = 1;
    var dst: ptr<u8> = null;
    if (c_eq(lp, "-m")) {
        if (argc < 3) {
            printf("bx: -m needs a manifest\n");
            return 2;
        }
        var mp: [u8; 1024] = [0];
        let mpp: ptr<u8> = p_u8(&mut mp[0]);
        io_arg(2, mpp, 1024);
        return tb_run(mpp);
    }
    if (c_eq(lp, "-o")) {
        if (argc < 4) {
            printf("bx: -o needs an output path and an input\n");
            return 2;
        }
        io_arg(2, opp, 1024);
        dst = opp;
        start = 3;
    }
    var files: i64 = 0;
    var bad: i64 = 0;
    var i: i64 = start;
    while (i < argc) {
        var p: [u8; 1024] = [0];
        let pp: ptr<u8> = p_u8(&mut p[0]);
        io_arg(i, pp, 1024);
        files += 1;
        if (tb_one(pp, dst) != 0) {
            bad += 1;
        }
        i += 1;
    }
    printf("bx: %lld files, %lld bad\n", files, bad);
    if (bad != 0) {
        return 1;
    }
    return 0;
}
