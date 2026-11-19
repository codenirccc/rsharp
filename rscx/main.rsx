include "parse.rsx";

extern "kernel32" fn GetCommandLineA() -> ptr<u8>;
extern "kernel32" fn GetStdHandle(kind: i32) -> i64;
extern "kernel32" fn ReadFile(h: i64, buf: ptr<u8>, want: u32, got: ptr<u32>, ov: ptr<u8>) -> i32;
extern "kernel32" fn CreateFileA(path: ptr<u8>, access: u32, share: u32, sa: ptr<u8>, disp: u32,
                                 flags: u32, tmpl: i64) -> i64;
extern "kernel32" fn CloseHandle(h: i64) -> i32;
extern "kernel32" fn ExitProcess(code: u32);
extern "kernel32" fn GetFullPathNameA(name: ptr<u8>, n: u32, buf: ptr<u8>, file: ptr<ptr<u8>>) -> u32;
extern "kernel32" fn GetFileAttributesA(path: ptr<u8>) -> u32;
extern "kernel32" fn VirtualAlloc(addr: ptr<u8>, size: u64, kind: u32, protect: u32) -> ptr<u8>;
extern "kernel32" fn GetEnvironmentVariableA(name: ptr<u8>, buf: ptr<u8>, n: u32) -> u32;
extern "kernel32" fn QueryPerformanceCounter(c: ptr<i64>) -> i32;
extern "kernel32" fn QueryPerformanceFrequency(f: ptr<i64>) -> i32;
extern "kernel32" fn GetFileSizeEx(h: i64, size: ptr<i64>) -> i32;
extern "kernel32" fn GetCurrentProcess() -> i64;
extern "kernel32" fn K32GetProcessMemoryInfo(h: i64, pmc: ptr<u8>, cb: u32) -> i32;

const READ_CHUNK: i64 = 1048576;
const PATH_MAX: i64 = 1024;

struct Buf {
    p: ptr<u8>,
    n: i64
}

struct Seen {
    tab: ptr<u8>,
    n: i64
}

struct Clock {
    on: i32,
    start: i64,
    prev: i64,
    freq: i64
}

struct Pmc {
    cb: u32,
    faults: u32,
    peak: u64,
    ws: u64,
    quota_peak_paged: u64,
    quota_paged: u64,
    quota_peak_npaged: u64,
    quota_npaged: u64,
    pagefile: u64,
    peak_pagefile: u64
}

fn peak_mb() -> i64 {
    var m: Pmc = zero(Pmc);
    m.cb = 72;
    var ok: i32 = 0;
    unsafe {
        ok = K32GetProcessMemoryInfo(GetCurrentProcess(), &m as ptr<u8>, 72);
    }
    if (ok == 0) {
        return 0;
    }
    return (m.peak / 1048576) as i64;
}

fn a_len(s: ptr<u8>) -> i64 {
    var i: i64 = 0;
    unsafe {
        while (s[i] != 0) {
            i += 1;
        }
    }
    return i;
}

fn a_copy(dst: ptr<u8>, src: ptr<u8>) -> i64 {
    var i: i64 = 0;
    unsafe {
        while (src[i] != 0) {
            dst[i] = src[i];
            i += 1;
        }
        dst[i] = 0;
    }
    return i;
}

fn a_copy_n(dst: ptr<u8>, n: i64, src: ptr<u8>) {
    var i: i64 = 0;
    unsafe {
        while (i < n && src[i] != 0) {
            dst[i] = src[i];
            i += 1;
        }
        dst[i] = 0;
    }
}

fn a_lower(dst: ptr<u8>, src: ptr<u8>) -> i64 {
    var i: i64 = 0;
    unsafe {
        while (src[i] != 0) {
            var c: u8 = src[i];
            if (c >= 65 && c <= 90) {
                c = c + 32;
            }
            dst[i] = c;
            i += 1;
        }
        dst[i] = 0;
    }
    return i;
}

fn a_starts(a: ptr<u8>, c: ptr<u8>) -> bool {
    var i: i64 = 0;
    unsafe {
        while (c[i] != 0) {
            if (a[i] != c[i]) {
                return false;
            }
            i += 1;
        }
    }
    return true;
}

fn a_eq(a: ptr<u8>, b: ptr<u8>) -> bool {
    var i: i64 = 0;
    unsafe {
        while (true) {
            if (a[i] != b[i]) {
                return false;
            }
            if (a[i] == 0) {
                return true;
            }
            i += 1;
        }
    }
    return false;
}

fn a_buf(n: i64) -> ptr<u8> {    let p: ptr<u8> = VirtualAlloc(null, n as u64, 12288, 4);
    if (p == null) {
        return p;
    }
    unsafe { p[0] = 0; }
    return p;
}

fn host_write(h: i64, p: ptr<u8>, n: i64) {
    var wrote: u32 = 0;
    var off: i64 = 0;
    var ok: i32 = 1;
    unsafe {
        while (ok == 1 && off < n) {
            ok = WriteFile(h, p + off, (n - off) as u32, &wrote as ptr<u32>, null);
            if (ok != 1 || wrote == 0) {
                break;
            }
            off += wrote as i64;
        }
    }
}

fn out_s(p: ptr<u8>) {
    host_write(GetStdHandle(-11), p, a_len(p));
}

fn out_b(p: ptr<u8>, n: i64) {
    host_write(GetStdHandle(-11), p, n);
}

fn err_b(p: ptr<u8>, n: i64) {
    host_write(GetStdHandle(-12), p, n);
}

fn err_s(p: ptr<u8>) {
    host_write(GetStdHandle(-12), p, a_len(p));
    host_write(GetStdHandle(-12), "\n" as ptr<u8>, 1);
}

fn argv_count() -> i64 {
    let cmd: ptr<u8> = GetCommandLineA();
    var i: i64 = 0;
    var n: i64 = 0;
    unsafe {
        while (true) {
            while (cmd[i] == 32 || cmd[i] == 9) {
                i += 1;
            }
            if (cmd[i] == 0) {
                return n;
            }
            if (cmd[i] == 34) {
                i += 1;
                while (cmd[i] != 0 && cmd[i] != 34) {
                    i += 1;
                }
                if (cmd[i] == 34) {
                    i += 1;
                }
            } else {
                while (cmd[i] != 0 && cmd[i] != 32 && cmd[i] != 9) {
                    i += 1;
                }
            }
            n += 1;
        }
    }
    return n;
}

fn argv_get(want: i64, dst: ptr<u8>, cap: i64) -> i64 {
    let cmd: ptr<u8> = GetCommandLineA();
    var i: i64 = 0;
    var n: i64 = 0;
    var k: i64 = 0;
    unsafe {
        while (true) {
            while (cmd[i] == 32 || cmd[i] == 9) {
                i += 1;
            }
            if (cmd[i] == 0) {
                dst[0] = 0;
                return -1;
            }
            if (n == want) {
                if (cmd[i] == 34) {
                    i += 1;
                    while (cmd[i] != 0 && cmd[i] != 34) {
                        if (k < cap - 1) {
                            dst[k] = cmd[i];
                            k += 1;
                        }
                        i += 1;
                    }
                } else {
                    while (cmd[i] != 0 && cmd[i] != 32 && cmd[i] != 9) {
                        if (k < cap - 1) {
                            dst[k] = cmd[i];
                            k += 1;
                        }
                        i += 1;
                    }
                }
                dst[k] = 0;
                return k;
            }
            if (cmd[i] == 34) {
                i += 1;
                while (cmd[i] != 0 && cmd[i] != 34) {
                    i += 1;
                }
                if (cmd[i] == 34) {
                    i += 1;
                }
            } else {
                while (cmd[i] != 0 && cmd[i] != 32 && cmd[i] != 9) {
                    i += 1;
                }
            }
            n += 1;
        }
    }
    return -1;
}

fn is_file(p: ptr<u8>) -> bool {
    let a: u32 = GetFileAttributesA(p);
    if (a == 0xFFFFFFFF) {
        return false;
    }
    if ((a & 0x10) != 0) {
        return false;
    }
    return true;
}

fn parent_len(p: ptr<u8>, n: i64) -> i64 {
    var i: i64 = n - 1;
    unsafe {
        while (i > 0) {
            let c: u8 = p[i];
            if (c == 92 || c == 47) {
                return i;
            }
            i -= 1;
        }
    }
    return 0;
}

fn join_into(dir: ptr<u8>, dlen: i64, name: ptr<u8>, out: ptr<u8>) {
    var k: i64 = 0;
    unsafe {
        var i: i64 = 0;
        while (i < dlen) {
            out[k] = dir[i];
            k += 1;
            i += 1;
        }
        if (k > 0 && out[k - 1] != 92 && out[k - 1] != 47) {
            out[k] = 92;
            k += 1;
        }
        i = 0;
        while (name[i] != 0) {
            out[k] = name[i];
            k += 1;
            i += 1;
        }
        out[k] = 0;
    }
}

fn read_file(path: ptr<u8>) -> Buf {
    var r: Buf = zero(Buf);
    r.n = 0 - 1;
    let h: i64 = CreateFileA(path, 0x80000000, 1, null, 3, 0x80, 0);
    if (h == -1) {
        return r;
    }
    var size: i64 = 0;
    var sized: i32 = 0;
    unsafe { sized = GetFileSizeEx(h, &size as ptr<i64>); }
    if (sized != 1 || size < 0) {
        CloseHandle(h);
        return r;
    }
    r.p = a_buf(size + 1);
    if (r.p == null) {
        CloseHandle(h);
        return r;
    }
    var got: u32 = 0;
    var total: i64 = 0;
    var want: i64 = 0;
    var ok: i32 = 1;
    unsafe {
        while (total < size) {
            want = size - total;
            if (want > READ_CHUNK) {
                want = READ_CHUNK;
            }
            ok = ReadFile(h, r.p + total, want as u32, &got as ptr<u32>, null);
            if (ok != 1 || got == 0) {
                break;
            }
            total += got as i64;
        }
        r.p[total] = 0;
    }
    CloseHandle(h);
    r.n = total;
    return r;
}

fn seen_new() -> Seen {
    var s: Seen = zero(Seen);
    s.tab = a_buf(64 * PATH_MAX);
    s.n = 0;
    return s;
}

fn seen_add(s: &mut Seen, key: ptr<u8>) -> bool {
    var i: i64 = 0;
    while (i < s.n) {
        var slot: ptr<u8> = null;
        unsafe { slot = s.tab + i * PATH_MAX; }
        if (a_eq(slot, key)) {
            return false;
        }
        i += 1;
    }
    if (s.n >= 64) {
        return true;
    }
    var slot2: ptr<u8> = null;
    unsafe { slot2 = s.tab + s.n * PATH_MAX; }
    a_copy(slot2, key);
    s.n += 1;
    return true;
}

fn canon_path(path: ptr<u8>, out: ptr<u8>) {
    let n: u32 = GetFullPathNameA(path, PATH_MAX as u32, out, null);
    if (n == 0) {
        a_copy(out, path);
    }
    a_lower(out, out);
}

fn scan_line(line: ptr<u8>, in_block: i32) -> i32 {
    var blk: i32 = in_block;
    var found: i32 = 0;
    let n: i64 = a_len(line);
    if (blk == 0 && a_starts_trim(line, "include")) {
        found = inc_quote_ok(line);
    }
    var i: i64 = 0;
    var in_str: i32 = 0;
    unsafe {
        while (i < n) {
            if (blk == 1) {
                if (i + 1 < n && line[i] == 42 && line[i + 1] == 47) {
                    blk = 0;
                    i += 2;
                    continue;
                }
                i += 1;
                continue;
            }
            if (in_str == 1) {
                if (line[i] == 92) {
                    i += 2;
                    continue;
                }
                if (line[i] == 34) {
                    in_str = 0;
                }
                i += 1;
                continue;
            }
            if (line[i] == 34) {
                in_str = 1;
                i += 1;
                continue;
            }
            if (i + 1 < n && line[i] == 47 && line[i + 1] == 47) {
                return blk + found * 2;
            }
            if (i + 1 < n && line[i] == 47 && line[i + 1] == 42) {
                blk = 1;
                i += 2;
                continue;
            }
            i += 1;
        }
    }
    return blk + found * 2;
}

fn a_starts_trim(line: ptr<u8>, word: ptr<u8>) -> bool {
    var i: i64 = 0;
    unsafe {
        while (line[i] == 32 || line[i] == 9) {
            i += 1;
        }
    }
    var at: ptr<u8> = null;
    unsafe { at = line + i; }
    return a_starts(at, word);
}

fn inc_quote_ok(line: ptr<u8>) -> i32 {
    var i: i64 = 0;
    unsafe {
        while (line[i] == 32 || line[i] == 9) {
            i += 1;
        }
        var k: i64 = 0;
        while (k < 7) {
            if (line[i + k] == 0) {
                return 0;
            }
            k += 1;
        }
        i += 7;
        while (line[i] == 32 || line[i] == 9) {
            i += 1;
        }
        if (line[i] != 34) {
            return 0;
        }
        i += 1;
        while (line[i] != 0) {
            if (line[i] == 34) {
                return 1;
            }
            i += 1;
        }
    }
    return 0;
}

fn inc_name(line: ptr<u8>, dst: ptr<u8>) {
    var i: i64 = 0;
    var k: i64 = 0;
    unsafe {
        while (line[i] == 32 || line[i] == 9) {
            i += 1;
        }
        i += 7;
        while (line[i] == 32 || line[i] == 9) {
            i += 1;
        }
        if (line[i] == 34) {
            i += 1;
        }
        while (line[i] != 0 && line[i] != 34) {
            dst[k] = line[i];
            k += 1;
            i += 1;
        }
        dst[k] = 0;
    }
}

fn find_include(from: ptr<u8>, name: ptr<u8>, out: ptr<u8>) -> i32 {
    let flen: i64 = a_len(from);
    let plen: i64 = parent_len(from, flen);
    var dir: ptr<u8> = a_buf(PATH_MAX);
    a_copy_n(dir, plen, from);
    join_into(dir, plen, name, out);
    if (is_file(out)) {
        return 1;
    }
    var d: i64 = plen;
    while (true) {
        var lib: ptr<u8> = a_buf(PATH_MAX);
        join_into(dir, d, "lib" as ptr<u8>, lib);
        join_into(lib, a_len(lib), name, out);
        if (is_file(out)) {
            return 1;
        }
        if (d == 0) {
            break;
        }
        d = parent_len(dir, d);
    }
    a_copy(out, name);
    if (is_file(out)) {
        return 1;
    }
    return 0;
}

fn exp_plain(p: ptr<u8>, n: i64) -> i32 {
    var at: i64 = 0;
    unsafe {
        while (at < n) {
            var k: i64 = at;
            while (k < n && (p[k] == 32 || p[k] == 9)) {
                k += 1;
            }
            if (k + 7 <= n) {
                if (p[k] == 105 && p[k + 1] == 110 && p[k + 2] == 99 && p[k + 3] == 108
                    && p[k + 4] == 117 && p[k + 5] == 100 && p[k + 6] == 101) {
                    return 0;
                }
            }
            var j: i64 = at;
            while (j < n) {
                let c: u8 = p[j];
                if (c == 10) {
                    break;
                }
                if (c == 13) {
                    return 0;
                }
                if (c == 47 && j + 1 < n) {
                    let d: u8 = p[j + 1];
                    if (d == 47 || d == 42) {
                        return 0;
                    }
                }
                j += 1;
            }
            at = j + 1;
        }
    }
    return 1;
}

fn expand(path: ptr<u8>, depth: i32, seen: &mut Seen, out: &mut Sb, msg: &mut Sb) -> i32 {
    if (depth > 16) {
        sb_puts(msg, "includes nested more than 16 deep, here at '");
        sb_puts(msg, path);
        sb_puts(msg, "'");
        return 0;
    }
    var canon: ptr<u8> = a_buf(PATH_MAX);
    canon_path(path, canon);
    if (!seen_add(seen, canon)) {
        return 1;
    }
    var b: Buf = read_file(path);
    if (b.n < 0) {
        sb_puts(msg, "cannot read '");
        sb_puts(msg, path);
        sb_puts(msg, "': The system cannot find the file specified. (os error 2)");
        return 0;
    }
    if (exp_plain(b.p, b.n) == 1) {
        sb_put(out, b.p, b.n);
        var last: u8 = 0;
        unsafe { last = b.p[b.n - 1]; }
        if (b.n > 0 && last != 10) {
            sb_putc(out, 10);
        }
        return 1;
    }
    var line: ptr<u8> = a_buf(b.n + 1);
    var fname: ptr<u8> = a_buf(PATH_MAX);
    var hit: ptr<u8> = a_buf(PATH_MAX);
    var in_block: i32 = 0;
    var i: i64 = 0;
    while (i < b.n) {
        var j: i64 = i;
        unsafe {
            while (j < b.n && b.p[j] != 10) {
                j += 1;
            }
        }
        var ln: i64 = j - i;
        if (ln > 0) {
            unsafe {
                if (b.p[i + ln - 1] == 13) {
                    ln -= 1;
                }
            }
        }
        var src_at: ptr<u8> = null;
        unsafe { src_at = b.p + i; }
        a_copy_n(line, ln, src_at);
        let was: i32 = in_block;
        let flags: i32 = scan_line(line, in_block);
        in_block = flags & 1;
        let found: i32 = (flags >> 1) & 1;
        var done: i32 = 0;
        if (was == 0 && found == 1) {
            inc_name(line, fname);
            if (find_include(path, fname, hit) == 1) {
                if (expand(hit, depth + 1, seen, out, msg) == 0) {
                    return 0;
                }
                if (out.n > 0) {
                    var last: u8 = 0;
                    unsafe { last = out.p[out.n - 1]; }
                    if (last != 10) {
                        sb_putc(out, 10);
                    }
                }
                done = 1;
            } else {
                if (depth == 0) {
                    sb_puts(msg, "cannot find include '");
                    sb_puts(msg, fname);
                    sb_puts(msg, "'");
                } else {
                    sb_puts(msg, path);
                    sb_puts(msg, ": cannot find include '");
                    sb_puts(msg, fname);
                    sb_puts(msg, "'");
                }
                return 0;
            }
        }
        if (done == 0) {
            sb_put(out, line, ln);
            sb_putc(out, 10);
        }
        if (j >= b.n) {
            break;
        }
        i = j + 1;
    }
    return 1;
}

fn usage() -> i32 {
    err_s("rsc - R# front end");
    err_s("usage: rsc <file.rsx> [-o <file.rsi>]");
    err_s("       rsc --tokenize <file.rsx>");
    return 2;
}

fn env_on(name: ptr<u8>) -> i32 {
    var v: ptr<u8> = null;
    unsafe { v = a_buf(8); }
    let got: u32 = GetEnvironmentVariableA(name, v, 8);
    if (got > 0) {
        return 1;
    }
    return 0;
}

fn clock_new() -> Clock {
    var c: Clock = zero(Clock);
    var f: i64 = 0;
    var t: i64 = 0;
    unsafe {
        QueryPerformanceFrequency(&f as ptr<i64>);
        QueryPerformanceCounter(&t as ptr<i64>);
    }
    c.freq = f;
    c.start = t;
    c.prev = t;
    var env: ptr<u8> = a_buf(16);
    let got: u32 = GetEnvironmentVariableA("RSC_TIME" as ptr<u8>, env, 16);
    if (got > 0) {
        c.on = 1;
    }
    return c;
}

fn clock_stamp(c: &mut Clock, name: ptr<u8>) {
    if (c.on == 0) {
        return;
    }
    var t: i64 = 0;
    unsafe { QueryPerformanceCounter(&t as ptr<i64>); }
    let ms: f64 = (t - c.prev) as f64 * 1000.0 / c.freq as f64;
    let cum: f64 = (t - c.start) as f64 * 1000.0 / c.freq as f64;
    c.prev = t;
    var b: Sb = sb_new(128);
    sb_puts(&mut b, "rsc: ");
    sb_puts(&mut b, name);
    var pad: i64 = 8 - a_len(name);
    while (pad > 0) {
        sb_putc(&mut b, 32);
        pad -= 1;
    }
    sb_putc(&mut b, 32);
    sb_fixed(&mut b, ms, 7, 2);
    sb_puts(&mut b, " ms  (cum ");
    sb_fixed(&mut b, cum, 7, 2);
    sb_puts(&mut b, ")  peak ");
    sb_i64(&mut b, peak_mb());
    sb_puts(&mut b, " MB");
    err_b(b.p, b.n);
    host_write(GetStdHandle(-12), "\n" as ptr<u8>, 1);
    sb_free(&mut b);
}

fn sb_fixed(b: &mut Sb, v: f64, width: i64, dec: i64) {
    var tmp: ptr<u8> = a_buf(64);
    var fmt: ptr<u8> = a_buf(8);
    a_copy(fmt, "%.2f" as ptr<u8>);
    unsafe {
        fmt[2] = 48 + dec as u8;
        sprintf(tmp, fmt, v);
    }
    let n: i64 = a_len(tmp);
    var pad: i64 = width - n;
    while (pad > 0) {
        sb_putc(b, 32);
        pad -= 1;
    }
    sb_put(b, tmp, n);
}

fn dump_tokens(f: &mut Fr) {
    var b: Sb = sb_new(256);
    let n: i64 = f.lx.ntok;
    var i: i64 = 0;
    while (i < n) {
        let k: i32 = lex_tok_kind(&mut f.lx, i);
        sb_i64(&mut b, lex_tok_line(&mut f.lx, i));
        sb_putc(&mut b, 58);
        sb_i64(&mut b, lex_tok_col(&mut f.lx, i));
        sb_puts(&mut b, "  ");
        tok_dbg(&mut b, &mut f.lx, i, k);
        sb_putc(&mut b, 10);
        out_b(b.p, b.n);
        sb_clear(&mut b);
        i += 1;
    }
    sb_free(&mut b);
}

fn tok_dbg(b: &mut Sb, lx: &mut Lexer, i: i64, k: i32) {
    if (k == TK_IDENT) {
        sb_puts(b, "Ident(\"");
        sb_put(b, lex_tok_sp(lx, i), lex_tok_slen(lx, i));
        sb_puts(b, "\")");
    } else if (k == TK_INT) {
        sb_puts(b, "Int(");
        sb_i64(b, lex_tok_num(lx, i));
        sb_puts(b, ")");
    } else if (k == TK_FLOAT) {
        sb_puts(b, "Float(");
        sb_f64_dbg(b, lex_tok_fp(lx, i));
        sb_puts(b, ")");
    } else if (k == TK_STR) {
        sb_puts(b, "Str(");
        sb_dbg(b, lex_tok_sp(lx, i), lex_tok_slen(lx, i));
        sb_puts(b, ")");
    } else if (k == TK_SYM) {
        sb_puts(b, "Sym(\"");
        sb_put(b, lex_tok_sp(lx, i), lex_tok_slen(lx, i));
        sb_puts(b, "\")");
    } else {
        sb_puts(b, "Eof");
    }
}

fn die(path: ptr<u8>, msg: ptr<u8>, n: i64) -> i32 {
    var b: Sb = sb_new(256);
    sb_puts(&mut b, "rsc: ");
    sb_puts(&mut b, path);
    sb_puts(&mut b, ": ");
    sb_put(&mut b, msg, n);
    err_b(b.p, b.n);
    host_write(GetStdHandle(-12), "\n" as ptr<u8>, 1);
    sb_free(&mut b);
    return 1;
}

fn main() -> i32 {
    let argc: i64 = argv_count();
    var args: ptr<u8> = a_buf(64 * PATH_MAX);
    var text: ptr<u8> = a_buf(64 * PATH_MAX);
    var out_path: ptr<u8> = a_buf(PATH_MAX);
    unsafe { out_path[0] = 0; }
    var have_out: i32 = 0;
    var dump: i32 = 0;
    var input: ptr<u8> = a_buf(PATH_MAX);
    unsafe { input[0] = 0; }
    var have_in: i32 = 0;
    var i: i64 = 1;
    while (i < argc) {
        argv_get(i, text, PATH_MAX);
        if (a_eq(text, "-o" as ptr<u8>) || a_eq(text, "--output" as ptr<u8>)) {
            if (i + 1 >= argc) {
                return usage();
            }
            argv_get(i + 1, out_path, PATH_MAX);
            have_out = 1;
            i += 2;
        } else if (a_eq(text, "--tokenize" as ptr<u8>)) {
            dump = 1;
            i += 1;
        } else if (a_eq(text, "-h" as ptr<u8>) || a_eq(text, "--help" as ptr<u8>)) {
            return usage();
        } else if (a_starts(text, "-" as ptr<u8>)) {
            var b: Sb = sb_new(128);
            sb_puts(&mut b, "rsc: unknown flag '");
            sb_puts(&mut b, text);
            sb_puts(&mut b, "'");
            err_b(b.p, b.n);
            host_write(GetStdHandle(-12), "\n" as ptr<u8>, 1);
            sb_free(&mut b);
            return usage();
        } else {
            if (have_in == 1) {
                err_s("rsc: only one input file is supported");
                return usage();
            }
            a_copy(input, text);
            have_in = 1;
            i += 1;
        }
    }
    if (have_in == 0) {
        return usage();
    }
    var clk: Clock = clock_new();
    var seen: Seen = seen_new();
    var src: Sb = sb_new(65536);
    var msg: Sb = sb_new(256);
    if (expand(input, 0, &mut seen, &mut src, &mut msg) == 0) {
        let r: i32 = die(input, msg.p, msg.n);
        return r;
    }
    clock_stamp(&mut clk, "expand" as ptr<u8>);
    var f: Fr = fr_new();
    if (dump == 1) {
        if (fr_lex_all(&mut f, src.p, src.n) == 0) {
            var ep0: ptr<u8> = null;
            var el0: i64 = 0;
            unsafe {
                ep0 = fr_err_ptr(&mut f);
                el0 = fr_err_len(&mut f);
            }
            let r0: i32 = die(input, ep0, el0);
            return r0;
        }
        clock_stamp(&mut clk, "lex" as ptr<u8>);
        dump_tokens(&mut f);
        return 0;
    }
    if (fr_lex(&mut f, src.p, src.n) == 0) {
        var ep: ptr<u8> = null;
        var el: i64 = 0;
        unsafe {
            ep = fr_err_ptr(&mut f);
            el = fr_err_len(&mut f);
        }
        let r: i32 = die(input, ep, el);
        return r;
    }
    if (env_on("RSC_LEXONLY" as ptr<u8>) == 1) {
        while (p_kind(&mut f, f.i) != TK_EOF) {
            p_bump(&mut f);
        }
        clock_stamp(&mut clk, "lexall" as ptr<u8>);
        return 0;
    }
    var p: Pr = fr_parse(&mut f);
    if (fr_ok(&mut f) == 0) {
        var ep2: ptr<u8> = null;
        var el2: i64 = 0;
        unsafe {
            ep2 = fr_err_ptr(&mut f);
            el2 = fr_err_len(&mut f);
        }
        let r: i32 = die(input, ep2, el2);
        return r;
    }
    clock_stamp(&mut clk, "parse" as ptr<u8>);
    var ir: Sb = sb_new(65536);
    var out_h: i64 = 0;
    var out_bad: i32 = 0;
    if (have_out == 1) {
        out_h = CreateFileA(out_path, 0x40000000, 0, null, 2, 0x80, 0);
        if (out_h == -1) {
            out_h = 0;
            out_bad = 1;
        }
        sb_spill(&mut ir, out_h);
    } else {
        sb_spill(&mut ir, GetStdHandle(-11));
    }
    if (out_bad == 0) {
        fr_emit(&mut f, &mut p, &mut ir);
        sb_flush(&mut ir);
    }
    if (out_h != 0) {
        CloseHandle(out_h);
    }
    if (out_bad == 1) {
        var b: Sb = sb_new(256);
        sb_puts(&mut b, "rsc: cannot write '");
        sb_puts(&mut b, out_path);
        sb_puts(&mut b, "': permission denied (os error 5)");
        err_b(b.p, b.n);
        host_write(GetStdHandle(-12), "\n" as ptr<u8>, 1);
        sb_free(&mut b);
        return 1;
    }
    clock_stamp(&mut clk, "write" as ptr<u8>);
    if (clk.on == 1) {
        var b: Sb = sb_new(160);
        sb_puts(&mut b, "rsc: nodes ");
        sb_i64(&mut b, f.na.n);
        sb_puts(&mut b, " x ");
        sb_i64(&mut b, sizeof(Nd) as i64);
        sb_puts(&mut b, " B, blocks ");
        sb_i64(&mut b, f.na.nb);
        sb_puts(&mut b, " lists ");
        sb_i64(&mut b, f.lp.n);
        sb_puts(&mut b, " strings ");
        sb_i64(&mut b, f.sp.n);
        sb_puts(&mut b, " ir ");
        sb_i64(&mut b, ir.total + ir.n);
        sb_puts(&mut b, " lpMB ");
        sb_i64(&mut b, lp_bytes(&mut f.lp) >> 20);
        sb_puts(&mut b, " spMB ");
        sb_i64(&mut b, (f.sp.bn + f.sp.n * 16) >> 20);
        err_b(b.p, b.n);
        host_write(GetStdHandle(-12), "\n" as ptr<u8>, 1);
        sb_free(&mut b);
    }
    return 0;
}
