extern fn printf(fmt: ptr<u8>, ...) -> i32;
extern fn fflush(f: ptr<u8>) -> i32;
extern fn fopen(path: ptr<u8>, mode: ptr<u8>) -> ptr<u8>;
extern fn fclose(f: ptr<u8>) -> i32;
extern fn fread(p: ptr<u8>, sz: u64, n: u64, f: ptr<u8>) -> u64;
extern fn fwrite(p: ptr<u8>, sz: u64, n: u64, f: ptr<u8>) -> u64;
extern fn fgets(s: ptr<u8>, n: i32, f: ptr<u8>) -> ptr<u8>;
extern fn system(cmd: ptr<u8>) -> i32;
extern fn getenv(name: ptr<u8>) -> ptr<u8>;
extern fn strlen(s: ptr<u8>) -> u64;
extern fn remove(path: ptr<u8>) -> i32;
extern fn malloc(n: u64) -> ptr<u8>;
extern fn memset(p: ptr<u8>, v: i32, n: u64) -> ptr<u8>;

const ARENA: i64 = 524288;
const MBUF: i64 = 131072;
const LBUF: i64 = 8192;
const MAXL: i32 = 8191;
const CBUF: i64 = 8192;
const TBUF: i64 = 4096;
const NSTR: i64 = 4096;
const NT: i64 = 64;
const NSEEN: i64 = 1024;
const NDEP: i64 = 512;
const NARG: i64 = 16;

const NEWLINE: u8 = 10;
const QUOTE: u8 = 34;
const SPACE: u8 = 32;
const TAB: u8 = 9;
const CR: u8 = 13;
const HASH: u8 = 35;
const SLASH: u8 = 47;
const BSLASH: u8 = 92;
const LBR: u8 = 91;
const RBR: u8 = 93;
const STAR: u8 = 42;
const COLON: u8 = 58;
const PERIOD: u8 = 46;

const HSEED: u64 = 1469598103934665603;

const TS1: i64 = 0;
const TS2: i64 = 1024;
const TS3: i64 = 2048;
const TS4: i64 = 3072;

const KIND_EXE: i32 = 0;
const KIND_TEST: i32 = 1;

struct Tgt {
    name: i64,
    src: i64,
    out: i64,
    plat: i64,
    dep0: i64,
    ndeps: i64,
    ast0: i64,
    nassets: i64,
    kind: i32,
    state: i32
}

struct Ctx {
    bp: ptr<u8>,
    mp: ptr<u8>,
    lp: ptr<u8>,
    cp: ptr<u8>,
    tp: ptr<u8>,
    at: i64,
    mn: i64,
    cn: i64,
    pn: i64,
    seen: [i64; NSEEN],
    nseen: i64,
    dep: [i64; NDEP],
    ndep: i64,
    ast: [i64; NDEP],
    nast: i64,
    cur: i64,
    tg: [Tgt; NT],
    nt: i64,
    ord: [i64; NT],
    nord: i64,
    args: [i64; NARG],
    nargs: i64,
    pos: [i64; 8],
    npos: i64,
    outdir: i64,
    rsc: i64,
    man: i64,
    man_def: i32,
    hostplat: i64,
    sb: [u8; 8],
    err: i32,
    win: i32,
    built: i32,
    skipped: i32
}

fn ob(p: ptr<u8>, k: i64) -> ptr<u8> {
    var q: ptr<u8> = null;
    unsafe { q = p + k; }
    return q;
}

fn rd8(p: ptr<u8>, k: i64) -> u8 {
    var v: u8 = 0;
    unsafe { v = p[k]; }
    return v;
}

fn wr8(p: ptr<u8>, k: i64, v: u8) {
    unsafe { p[k] = v; }
}

fn sl(p: ptr<u8>) -> i64 {
    if (p == null) {
        return 0;
    }
    return strlen(p) as i64;
}

fn sq(a: ptr<u8>, b: ptr<u8>) -> i32 {
    let n: i64 = sl(a);
    if (n != sl(b)) {
        return 0;
    }
    var k: i64 = 0;
    while (k < n) {
        if (rd8(a, k) != rd8(b, k)) {
            return 0;
        }
        k += 1;
    }
    return 1;
}

fn sn(a: ptr<u8>, b: ptr<u8>, n: i64) -> i32 {
    var k: i64 = 0;
    while (k < n) {
        if (rd8(a, k) != rd8(b, k)) {
            return 0;
        }
        k += 1;
    }
    return 1;
}

fn ws(v: u8) -> i32 {
    if (v == SPACE || v == TAB || v == CR) {
        return 1;
    }
    return 0;
}

fn zalloc(n: i64) -> ptr<u8> {
    let p: ptr<u8> = malloc(n as u64);
    if (p == null) {
        return null;
    }
    memset(p, 0, n as u64);
    return p;
}

fn tp_room(c: &mut Ctx, at: i64, need: i64) -> i32 {
    if (at < 0 || at + need + 1 > TBUF) {
        printf("rmake: path too long for the scratch area\n");
        c.err = 1;
        return 0;
    }
    return 1;
}

fn host_win() -> i32 {
    let p: ptr<u8> = getenv("COMSPEC");
    if (p == null) {
        return 0;
    }
    return 1;
}

fn rc_ok(rc: i32) -> i32 {
    if (rc == 0) {
        return 1;
    }
    return 0;
}

fn cmd_room(c: &mut Ctx, need: i64) -> i32 {
    if (c.cn < 0 || need < 0 || c.cn + need + 2 > CBUF) {
        printf("rmake: command line too long\n");
        c.err = 1;
        return 0;
    }
    return 1;
}

fn cmd_begin(c: &mut Ctx) {
    c.cn = 0;
    if (c.win == 1) {
        if (cmd_room(c, 1) == 0) {
            return;
        }
        wr8(c.cp, 0, QUOTE);
        c.cn = 1;
    }
}

fn cmd_raw(c: &mut Ctx, p: ptr<u8>) {
    let n: i64 = sl(p);
    if (cmd_room(c, n) == 0) {
        return;
    }
    var k: i64 = 0;
    while (k < n) {
        wr8(c.cp, c.cn, rd8(p, k));
        c.cn += 1;
        k += 1;
    }
}

fn cmd_sp(c: &mut Ctx) {
    if (cmd_room(c, 1) == 0) {
        return;
    }
    wr8(c.cp, c.cn, SPACE);
    c.cn += 1;
}

fn cmd_arg(c: &mut Ctx, p: ptr<u8>) {
    let n: i64 = sl(p);
    if (cmd_room(c, n + 2) == 0) {
        return;
    }
    wr8(c.cp, c.cn, QUOTE);
    c.cn += 1;
    cmd_raw(c, p);
    wr8(c.cp, c.cn, QUOTE);
    c.cn += 1;
}

fn cmd_end(c: &mut Ctx) -> ptr<u8> {
    if (c.win == 1) {
        if (cmd_room(c, 1) == 0) {
            wr8(c.cp, CBUF - 1, 0);
            return c.cp;
        }
        wr8(c.cp, c.cn, QUOTE);
        c.cn += 1;
    }
    wr8(c.cp, c.cn, 0);
    return c.cp;
}

fn spawn(c: &mut Ctx) -> i32 {
    if (c.err != 0) {
        return 1;
    }
    let p: ptr<u8> = cmd_end(c);
    if (c.err != 0) {
        return 1;
    }
    fflush(null);
    return system(p);
}
