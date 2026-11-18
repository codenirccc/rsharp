include "bx_parse.rsx";
include "bx_conv.rsx";
include "bx_fold.rsx";
include "bx_io.rsx";

extern fn printf(fmt: ptr<u8>, ...) -> i32;

fn tf_emit(x: &mut Bp, pr: &mut Pr, out: &mut Sb) {
    bx_conv(x, pr);
    var a: Na = zero(Na);
    a = x.na;
    var l: Lp = zero(Lp);
    l = x.lp;
    var s: Sp = zero(Sp);
    s = x.sp;
    prog_w(&mut a, &mut l, &mut s, out, pr);
}

fn tf_fold_text(p: ptr<u8>, n: i64, dst: &mut Sb) -> i32 {
    var y: Bp = bp_new();
    var pr2: Pr = bx_parse_ir(&mut y, p, n);
    if (bp_ok(&mut y) == 0) {
        bp_free(&mut y);
        return 0;
    }
    fx_run(&mut y, &mut pr2);
    tf_emit(&mut y, &mut pr2, dst);
    bp_free(&mut y);
    return 1;
}

fn tf_same(a: ptr<u8>, b: ptr<u8>, n: i64) -> i32 {
    var i: i64 = 0;
    while (i < n) {
        var ca: u8 = 0;
        var cb: u8 = 0;
        unsafe {
            ca = a[i];
            cb = b[i];
        }
        if (ca != cb) {
            return 0;
        }
        i += 1;
    }
    return 1;
}

fn tf_one(path: ptr<u8>, show: i32) -> i32 {
    var b: Buf = io_read(path);
    if (b.p == null) {
        printf("fold: %s: cannot read\n", path);
        return 1;
    }
    var x: Bp = bp_new();
    var pr: Pr = bx_parse_ir(&mut x, b.p, b.n);
    if (bp_ok(&mut x) == 0) {
        let ep: ptr<u8> = bp_err_ptr(&mut x);
        let en: i64 = bp_err_len(&mut x);
        printf("fold: %s: malformed IR: %.*s\n", path, en as i32, ep);
        bp_free(&mut x);
        free(b.p);
        return 1;
    }
    fx_run(&mut x, &mut pr);
    var out: Sb = sb_new(b.n + 64);
    tf_emit(&mut x, &mut pr, &mut out);
    bp_free(&mut x);
    free(b.p);
    if (show == 1) {
        sb_putc(&mut out, 0);
        printf("%s", out.p);
        sb_free(&mut out);
        return 0;
    }
    var rc: i32 = 0;
    var out2: Sb = sb_new(out.n + 16);
    if (tf_fold_text(out.p, out.n, &mut out2) == 0) {
        printf("fold: %s: folded IR does not parse\n", path);
        rc = 1;
    } else if (out2.n != out.n || tf_same(out.p, out2.p, out.n) == 0) {
        printf("fold: %s: second pass changed the program\n", path);
        rc = 1;
    }
    sb_free(&mut out2);
    sb_free(&mut out);
    return rc;
}

fn tf_manifest(mpath: ptr<u8>) -> i32 {
    var m: Buf = io_read(mpath);
    if (m.p == null) {
        printf("fold: cannot read manifest %s\n", mpath);
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
                if (tf_one(lp, 0) != 0) {
                    bad += 1;
                }
            }
            start = i + 1;
        }
        i += 1;
    }
    free(m.p);
    printf("fold: %lld files, %lld bad\n", files, bad);
    if (bad != 0) {
        return 1;
    }
    return 0;
}

fn main() -> i32 {
    let argc: i64 = io_argc();
    if (argc < 2) {
        printf("usage: t_fold <in.rsi>...\n       t_fold -s <in.rsi>\n       t_fold -m <manifest>\n");
        return 2;
    }
    var first: [u8; 1024] = [0];
    let fp: ptr<u8> = p_u8(&mut first[0]);
    io_arg(1, fp, 1024);
    if (c_eq(fp, "-m")) {
        if (argc < 3) {
            printf("fold: -m needs a manifest\n");
            return 2;
        }
        var mp: [u8; 1024] = [0];
        let mpp: ptr<u8> = p_u8(&mut mp[0]);
        io_arg(2, mpp, 1024);
        return tf_manifest(mpp);
    }
    if (c_eq(fp, "-s")) {
        if (argc < 3) {
            printf("fold: -s needs an input\n");
            return 2;
        }
        var sp: [u8; 1024] = [0];
        let spp: ptr<u8> = p_u8(&mut sp[0]);
        io_arg(2, spp, 1024);
        return tf_one(spp, 1);
    }
    var files: i64 = 0;
    var bad2: i64 = 0;
    var i: i64 = 1;
    while (i < argc) {
        var p: [u8; 1024] = [0];
        let pp: ptr<u8> = p_u8(&mut p[0]);
        io_arg(i, pp, 1024);
        files += 1;
        if (tf_one(pp, 0) != 0) {
            bad2 += 1;
        }
        i += 1;
    }
    printf("fold: %lld files, %lld bad\n", files, bad2);
    if (bad2 != 0) {
        return 1;
    }
    return 0;
}
