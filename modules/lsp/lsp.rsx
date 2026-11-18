extern fn malloc(n: u64) -> ptr<u8>;
extern fn free(p: ptr<u8>) -> void;
extern fn realloc(p: ptr<u8>, n: u64) -> ptr<u8>;
extern fn memcpy(d: ptr<u8>, s: ptr<u8>, n: u64) -> ptr<u8>;
extern fn strlen(s: ptr<u8>) -> u64;

const LSP_MAX_DOCS: i32 = 32;
const LSP_MAX_DIAGS: i32 = 64;
const LSP_MAX_DEPTH: i32 = 64;
const LSP_MAX_BRACKETS: i32 = 128;
const LSP_MAX_MESSAGE: i64 = 33554432;

struct LspBuf {
    p: ptr<u8>,
    len: i64,
    cap: i64,
    err: i32
}

fn lsp_buf_new(cap: i64) -> LspBuf {
    var b: LspBuf = zero(LspBuf);
    if (cap < 32) {
        cap = 32;
    }
    b.p = malloc(cap as u64);
    if (b.p != null) {
        b.cap = cap;
    } else {
        b.err = 1;
    }
    return b;
}

fn lsp_buf_free(b: &mut LspBuf) {
    if (b.p != null) {
        free(b.p);
        b.p = null;
    }
    b.len = 0;
    b.cap = 0;
    b.err = 0;
}

fn lsp_buf_reserve(b: &mut LspBuf, extra: i64) -> i32 {
    if (b.err == 1 || extra < 0) {
        b.err = 1;
        return 0 - 1;
    }
    let need: i64 = b.len + extra;
    if (need <= b.cap) {
        return 0;
    }
    var cap: i64 = b.cap;
    if (cap < 32) {
        cap = 32;
    }
    while (cap < need) {
        if (cap > 268435456) {
            b.err = 1;
            return 0 - 1;
        }
        cap = cap * 2;
    }
    var np: ptr<u8> = realloc(b.p, cap as u64);
    if (np == null) {
        b.err = 1;
        return 0 - 1;
    }
    b.p = np;
    b.cap = cap;
    return 0;
}

fn lsp_buf_put(b: &mut LspBuf, src: ptr<u8>, n: i64) -> i32 {
    if (n <= 0) {
        return 0;
    }
    if (lsp_buf_reserve(b, n) != 0) {
        return 0 - 1;
    }
    var dst: ptr<u8> = null;
    unsafe { dst = b.p + b.len; }
    memcpy(dst, src, n as u64);
    b.len += n;
    return 0;
}

fn lsp_buf_putc(b: &mut LspBuf, c: u8) -> i32 {
    if (lsp_buf_reserve(b, 1) != 0) {
        return 0 - 1;
    }
    unsafe { b.p[b.len] = c; }
    b.len += 1;
    return 0;
}

fn lsp_buf_puts(b: &mut LspBuf, s: ptr<u8>) -> i32 {
    return lsp_buf_put(b, s, strlen(s) as i64);
}

fn lsp_buf_clear(b: &mut LspBuf) {
    b.len = 0;
}

fn lsp_buf_putu(b: &mut LspBuf, v: i64) {
    var tmp: [u8; 24] = [0];
    var i: i64 = 24;
    var n: i64 = v;
    var neg: i32 = 0;
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
    var base: ptr<u8> = null;
    unsafe { base = &mut tmp[0] as ptr<u8>; }
    var off: ptr<u8> = null;
    unsafe { off = base + i; }
    lsp_buf_put(b, off, 24 - i);
}

fn lsp_digits(dst: ptr<u8>, v: i64) -> i64 {
    var tmp: [u8; 24] = [0];
    var i: i64 = 24;
    var n: i64 = v;
    if (n == 0) {
        i -= 1;
        tmp[i] = 48;
    }
    while (n > 0) {
        i -= 1;
        tmp[i] = (48 + (n % 10)) as u8;
        n = n / 10;
    }
    var base: ptr<u8> = null;
    unsafe { base = &mut tmp[0] as ptr<u8>; }
    var off: ptr<u8> = null;
    unsafe { off = base + i; }
    memcpy(dst, off, (24 - i) as u64);
    return 24 - i;
}

fn lsp_eqn(a: ptr<u8>, an: i64, b: ptr<u8>, bn: i64) -> i32 {
    if (an != bn) {
        return 0;
    }
    var i: i64 = 0;
    while (i < an) {
        var ca: u8 = 0;
        var cb: u8 = 0;
        unsafe { ca = a[i]; }
        unsafe { cb = b[i]; }
        if (ca != cb) {
            return 0;
        }
        i += 1;
    }
    return 1;
}

fn lsp_eq(a: ptr<u8>, b: ptr<u8>) -> i32 {
    return lsp_eqn(a, strlen(a) as i64, b, strlen(b) as i64);
}

fn lsp_word_is(a: ptr<u8>, an: i64, b: ptr<u8>) -> i32 {
    return lsp_eqn(a, an, b, strlen(b) as i64);
}

const LSP_JV_NULL: i64 = 1;
const LSP_JV_BOOL: i64 = 2;
const LSP_JV_INT: i64 = 3;
const LSP_JV_FLOAT: i64 = 4;
const LSP_JV_STR: i64 = 5;
const LSP_JV_ARR: i64 = 6;
const LSP_JV_OBJ: i64 = 7;

struct LspJv {
    kind: i64,
    num: i64,
    sp: ptr<u8>,
    slen: i64,
    next: i64,
    first: i64,
    last: i64
}

struct LspJp {
    p: ptr<u8>,
    len: i64,
    i: i64,
    nodes: ptr<LspJv>,
    n: i64,
    cap: i64,
    ok: i32,
    depth: i32,
    sb: LspBuf
}

fn lsp_jp_new(p: ptr<u8>, len: i64) -> LspJp {
    var jp: LspJp = zero(LspJp);
    jp.p = p;
    jp.len = len;
    jp.ok = 1;
    jp.cap = 64;
    jp.nodes = malloc((jp.cap as u64) * sizeof(LspJv)) as ptr<LspJv>;
    jp.sb = lsp_buf_new(64);
    if (jp.nodes == null || jp.sb.err == 1) {
        jp.ok = 0;
    }
    if (jp.nodes != null) {
        jp.n = 1;
        unsafe { jp.nodes[0] = zero(LspJv); }
    }
    return jp;
}

fn lsp_jp_push(jp: &mut LspJp) -> i64 {
    if (jp.ok == 0) {
        return 0;
    }
    if (jp.n >= jp.cap) {
        let nc: i64 = jp.cap * 2;
        var raw: ptr<u8> = realloc(jp.nodes as ptr<u8>, (nc as u64) * sizeof(LspJv));
        if (raw == null) {
            jp.ok = 0;
            return 0;
        }
        jp.nodes = raw as ptr<LspJv>;
        jp.cap = nc;
    }
    let i: i64 = jp.n;
    unsafe { jp.nodes[i] = zero(LspJv); }
    jp.n += 1;
    return i;
}

fn lsp_jp_link(jp: &mut LspJp, parent: i64, child: i64) {
    if (parent == 0 || child == 0) {
        return;
    }
    unsafe {
        if (jp.nodes[parent].first == 0) {
            jp.nodes[parent].first = child;
        } else {
            jp.nodes[jp.nodes[parent].last].next = child;
        }
        jp.nodes[parent].last = child;
    }
}

fn lsp_jp_byte(jp: &mut LspJp, at: i64) -> i64 {
    if (at < 0 || at >= jp.len) {
        return 0 - 1;
    }
    unsafe { return jp.p[at] as i64; }
}

fn lsp_jp_ws(jp: &mut LspJp) {
    while (jp.i < jp.len) {
        let c: i64 = lsp_jp_byte(jp, jp.i);
        if (c != 32 && c != 9 && c != 10 && c != 13) {
            return;
        }
        jp.i += 1;
    }
}

fn lsp_jp_peek(jp: &mut LspJp) -> i64 {
    return lsp_jp_byte(jp, jp.i);
}

fn lsp_jp_hex4(jp: &mut LspJp) -> i64 {
    if (jp.i + 4 > jp.len) {
        return 0 - 1;
    }
    var v: i64 = 0;
    var k: i64 = 0;
    while (k < 4) {
        let c: i64 = lsp_jp_byte(jp, jp.i + k);
        var d: i64 = 0 - 1;
        if (c >= 48 && c <= 57) {
            d = c - 48;
        } else if (c >= 97 && c <= 102) {
            d = c - 87;
        } else if (c >= 65 && c <= 70) {
            d = c - 55;
        }
        if (d < 0) {
            return 0 - 1;
        }
        v = v * 16 + d;
        k += 1;
    }
    jp.i += 4;
    return v;
}

fn lsp_buf_utf8(b: &mut LspBuf, cp: i64) {
    if (cp < 0x80) {
        lsp_buf_putc(b, cp as u8);
        return;
    }
    if (cp < 0x800) {
        lsp_buf_putc(b, (0xC0 | (cp >> 6)) as u8);
        lsp_buf_putc(b, (0x80 | (cp & 0x3F)) as u8);
        return;
    }
    if (cp < 0x10000) {
        lsp_buf_putc(b, (0xE0 | (cp >> 12)) as u8);
        lsp_buf_putc(b, (0x80 | ((cp >> 6) & 0x3F)) as u8);
        lsp_buf_putc(b, (0x80 | (cp & 0x3F)) as u8);
        return;
    }
    lsp_buf_putc(b, (0xF0 | (cp >> 18)) as u8);
    lsp_buf_putc(b, (0x80 | ((cp >> 12) & 0x3F)) as u8);
    lsp_buf_putc(b, (0x80 | ((cp >> 6) & 0x3F)) as u8);
    lsp_buf_putc(b, (0x80 | (cp & 0x3F)) as u8);
}

fn lsp_jp_esc(jp: &mut LspJp) {
    let e: i64 = lsp_jp_peek(jp);
    if (e < 0) {
        jp.ok = 0;
        return;
    }
    if (e == 34 || e == 92 || e == 47) {
        lsp_buf_putc(&mut jp.sb, e as u8);
        jp.i += 1;
        return;
    }
    if (e == 98) {
        lsp_buf_putc(&mut jp.sb, 8);
        jp.i += 1;
        return;
    }
    if (e == 102) {
        lsp_buf_putc(&mut jp.sb, 12);
        jp.i += 1;
        return;
    }
    if (e == 110) {
        lsp_buf_putc(&mut jp.sb, 10);
        jp.i += 1;
        return;
    }
    if (e == 114) {
        lsp_buf_putc(&mut jp.sb, 13);
        jp.i += 1;
        return;
    }
    if (e == 116) {
        lsp_buf_putc(&mut jp.sb, 9);
        jp.i += 1;
        return;
    }
    if (e != 117) {
        jp.ok = 0;
        return;
    }
    jp.i += 1;
    var cp: i64 = lsp_jp_hex4(jp);
    if (cp < 0) {
        jp.ok = 0;
        return;
    }
    if (cp >= 0xD800 && cp <= 0xDBFF) {
        if (lsp_jp_byte(jp, jp.i) != 92 || lsp_jp_byte(jp, jp.i + 1) != 117) {
            jp.ok = 0;
            return;
        }
        jp.i += 2;
        let lo: i64 = lsp_jp_hex4(jp);
        if (lo < 0xDC00 || lo > 0xDFFF) {
            jp.ok = 0;
            return;
        }
        cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
    } else if (cp >= 0xDC00 && cp <= 0xDFFF) {
        jp.ok = 0;
        return;
    }
    lsp_buf_utf8(&mut jp.sb, cp);
}

fn lsp_jp_string(jp: &mut LspJp) -> i64 {
    jp.i += 1;
    lsp_buf_clear(&mut jp.sb);
    var closed: i32 = 0;
    while (jp.i < jp.len) {
        let c: i64 = lsp_jp_byte(jp, jp.i);
        if (c == 34) {
            jp.i += 1;
            closed = 1;
            break;
        }
        if (c == 92) {
            jp.i += 1;
            lsp_jp_esc(jp);
            if (jp.ok == 0) {
                return 0;
            }
            continue;
        }
        if (c < 0x20) {
            jp.ok = 0;
            return 0;
        }
        lsp_buf_putc(&mut jp.sb, c as u8);
        jp.i += 1;
    }
    if (closed == 0) {
        jp.ok = 0;
        return 0;
    }
    let node: i64 = lsp_jp_push(jp);
    if (node == 0) {
        return 0;
    }
    var mem: ptr<u8> = malloc((jp.sb.len + 1) as u64);
    if (mem == null) {
        jp.ok = 0;
        return 0;
    }
    memcpy(mem, jp.sb.p, jp.sb.len as u64);
    unsafe { mem[jp.sb.len] = 0; }
    unsafe {
        jp.nodes[node].kind = LSP_JV_STR;
        jp.nodes[node].sp = mem;
        jp.nodes[node].slen = jp.sb.len;
    }
    return node;
}

fn lsp_jp_number(jp: &mut LspJp) -> i64 {
    let start: i64 = jp.i;
    var isf: i32 = 0;
    if (lsp_jp_peek(jp) == 45) {
        jp.i += 1;
    }
    while (jp.i < jp.len) {
        let c: i64 = lsp_jp_byte(jp, jp.i);
        if (c >= 48 && c <= 57) {
            jp.i += 1;
            continue;
        }
        if (c == 46 || c == 101 || c == 69) {
            isf = 1;
            jp.i += 1;
            continue;
        }
        if ((c == 43 || c == 45) && jp.i > start) {
            let prev: i64 = lsp_jp_byte(jp, jp.i - 1);
            if (prev == 101 || prev == 69) {
                jp.i += 1;
                continue;
            }
        }
        break;
    }
    if (jp.i == start) {
        jp.ok = 0;
        return 0;
    }
    let node: i64 = lsp_jp_push(jp);
    if (node == 0) {
        return 0;
    }
    var val: i64 = 0;
    if (isf == 0) {
        var k: i64 = start;
        var neg: i32 = 0;
        if (lsp_jp_byte(jp, k) == 45) {
            neg = 1;
            k += 1;
        }
        while (k < jp.i) {
            let d: i64 = lsp_jp_byte(jp, k);
            val = val * 10 + (d - 48);
            k += 1;
        }
        if (neg == 1) {
            val = 0 - val;
        }
    }
    var base: ptr<u8> = null;
    unsafe { base = jp.p + start; }
    unsafe {
        jp.nodes[node].sp = base;
        jp.nodes[node].slen = jp.i - start;
        if (isf == 1) {
            jp.nodes[node].kind = LSP_JV_FLOAT;
        } else {
            jp.nodes[node].kind = LSP_JV_INT;
            jp.nodes[node].num = val;
        }
    }
    return node;
}

fn lsp_jp_lit(jp: &mut LspJp, word: ptr<u8>, kind: i64, num: i64) -> i64 {
    let n: i64 = strlen(word) as i64;
    if (jp.i + n > jp.len) {
        jp.ok = 0;
        return 0;
    }
    var k: i64 = 0;
    while (k < n) {
        let c: i64 = lsp_jp_byte(jp, jp.i + k);
        var w: u8 = 0;
        unsafe { w = word[k]; }
        if (c != (w as i64)) {
            jp.ok = 0;
            return 0;
        }
        k += 1;
    }
    jp.i += n;
    let node: i64 = lsp_jp_push(jp);
    if (node == 0) {
        return 0;
    }
    unsafe {
        jp.nodes[node].kind = kind;
        jp.nodes[node].num = num;
    }
    return node;
}

fn lsp_jp_array(jp: &mut LspJp) -> i64 {
    jp.depth += 1;
    if (jp.depth > LSP_MAX_DEPTH) {
        jp.ok = 0;
        return 0;
    }
    jp.i += 1;
    let node: i64 = lsp_jp_push(jp);
    if (node == 0) {
        return 0;
    }
    unsafe { jp.nodes[node].kind = LSP_JV_ARR; }
    lsp_jp_ws(jp);
    if (lsp_jp_peek(jp) == 93) {
        jp.i += 1;
        jp.depth -= 1;
        return node;
    }
    while (jp.ok == 1) {
        let v: i64 = lsp_jp_value(jp);
        if (v == 0) {
            return 0;
        }
        lsp_jp_link(jp, node, v);
        lsp_jp_ws(jp);
        let c: i64 = lsp_jp_peek(jp);
        if (c == 44) {
            jp.i += 1;
            continue;
        }
        if (c == 93) {
            jp.i += 1;
            jp.depth -= 1;
            return node;
        }
        jp.ok = 0;
        return 0;
    }
    return 0;
}

fn lsp_jp_object(jp: &mut LspJp) -> i64 {
    jp.depth += 1;
    if (jp.depth > LSP_MAX_DEPTH) {
        jp.ok = 0;
        return 0;
    }
    jp.i += 1;
    let node: i64 = lsp_jp_push(jp);
    if (node == 0) {
        return 0;
    }
    unsafe { jp.nodes[node].kind = LSP_JV_OBJ; }
    lsp_jp_ws(jp);
    if (lsp_jp_peek(jp) == 125) {
        jp.i += 1;
        jp.depth -= 1;
        return node;
    }
    while (jp.ok == 1) {
        lsp_jp_ws(jp);
        if (lsp_jp_peek(jp) != 34) {
            jp.ok = 0;
            return 0;
        }
        let k: i64 = lsp_jp_string(jp);
        if (k == 0) {
            return 0;
        }
        lsp_jp_link(jp, node, k);
        lsp_jp_ws(jp);
        if (lsp_jp_peek(jp) != 58) {
            jp.ok = 0;
            return 0;
        }
        jp.i += 1;
        let v: i64 = lsp_jp_value(jp);
        if (v == 0) {
            return 0;
        }
        lsp_jp_link(jp, node, v);
        lsp_jp_ws(jp);
        let c: i64 = lsp_jp_peek(jp);
        if (c == 44) {
            jp.i += 1;
            continue;
        }
        if (c == 125) {
            jp.i += 1;
            jp.depth -= 1;
            return node;
        }
        jp.ok = 0;
        return 0;
    }
    return 0;
}

fn lsp_jp_value(jp: &mut LspJp) -> i64 {
    if (jp.ok == 0) {
        return 0;
    }
    lsp_jp_ws(jp);
    let c: i64 = lsp_jp_peek(jp);
    if (c < 0) {
        jp.ok = 0;
        return 0;
    }
    if (c == 34) {
        return lsp_jp_string(jp);
    }
    if (c == 123) {
        return lsp_jp_object(jp);
    }
    if (c == 91) {
        return lsp_jp_array(jp);
    }
    if (c == 116) {
        return lsp_jp_lit(jp, "true", LSP_JV_BOOL, 1);
    }
    if (c == 102) {
        return lsp_jp_lit(jp, "false", LSP_JV_BOOL, 0);
    }
    if (c == 110) {
        return lsp_jp_lit(jp, "null", LSP_JV_NULL, 0);
    }
    if (c == 45 || (c >= 48 && c <= 57)) {
        return lsp_jp_number(jp);
    }
    jp.ok = 0;
    return 0;
}

fn lsp_json_parse(p: ptr<u8>, len: i64) -> LspJp {
    var jp: LspJp = lsp_jp_new(p, len);
    if (jp.ok == 0) {
        return jp;
    }
    let root: i64 = lsp_jp_value(&mut jp);
    if (root == 0) {
        jp.ok = 0;
        return jp;
    }
    lsp_jp_ws(&mut jp);
    if (jp.i != jp.len) {
        jp.ok = 0;
    }
    return jp;
}

fn lsp_json_free(jp: &mut LspJp) {
    if (jp.nodes != null) {
        var i: i64 = 1;
        while (i < jp.n) {
            unsafe {
                if (jp.nodes[i].kind == LSP_JV_STR && jp.nodes[i].sp != null) {
                    free(jp.nodes[i].sp);
                }
            }
            i += 1;
        }
        free(jp.nodes as ptr<u8>);
        jp.nodes = null;
    }
    jp.n = 0;
    jp.cap = 0;
    lsp_buf_free(&mut jp.sb);
}

fn lsp_jv_kind(nodes: ptr<LspJv>, idx: i64) -> i64 {
    if (idx <= 0) {
        return 0;
    }
    unsafe { return nodes[idx].kind; }
}

fn lsp_jv_str(nodes: ptr<LspJv>, idx: i64) -> ptr<u8> {
    if (idx <= 0) {
        return null;
    }
    unsafe {
        if (nodes[idx].kind != LSP_JV_STR) {
            return null;
        }
        return nodes[idx].sp;
    }
}

fn lsp_jv_slen(nodes: ptr<LspJv>, idx: i64) -> i64 {
    if (idx <= 0) {
        return 0;
    }
    unsafe {
        if (nodes[idx].kind != LSP_JV_STR) {
            return 0;
        }
        return nodes[idx].slen;
    }
}

fn lsp_jv_int(nodes: ptr<LspJv>, idx: i64) -> i64 {
    if (idx <= 0) {
        return 0;
    }
    unsafe { return nodes[idx].num; }
}

fn lsp_jv_at(nodes: ptr<LspJv>, arr: i64, at: i64) -> i64 {
    if (arr <= 0 || at < 0) {
        return 0;
    }
    var c: i64 = 0;
    unsafe {
        if (nodes[arr].kind != LSP_JV_ARR) {
            return 0;
        }
        c = nodes[arr].first;
    }
    var i: i64 = 0;
    while (c != 0) {
        if (i == at) {
            return c;
        }
        unsafe { c = nodes[c].next; }
        i += 1;
    }
    return 0;
}

fn lsp_jv_count(nodes: ptr<LspJv>, arr: i64) -> i64 {
    if (arr <= 0) {
        return 0;
    }
    var c: i64 = 0;
    unsafe {
        if (nodes[arr].kind != LSP_JV_ARR) {
            return 0;
        }
        c = nodes[arr].first;
    }
    var n: i64 = 0;
    while (c != 0) {
        n += 1;
        unsafe { c = nodes[c].next; }
    }
    return n;
}

fn lsp_jv_get(nodes: ptr<LspJv>, obj: i64, key: ptr<u8>) -> i64 {
    if (obj <= 0) {
        return 0;
    }
    var k: i64 = 0;
    unsafe {
        if (nodes[obj].kind != LSP_JV_OBJ) {
            return 0;
        }
        k = nodes[obj].first;
    }
    let kn: i64 = strlen(key) as i64;
    while (k != 0) {
        var v: i64 = 0;
        var kp: ptr<u8> = null;
        var kl: i64 = 0;
        unsafe {
            v = nodes[k].next;
            kp = nodes[k].sp;
            kl = nodes[k].slen;
        }
        if (v == 0) {
            return 0;
        }
        if (lsp_eqn(kp, kl, key, kn) == 1) {
            return v;
        }
        unsafe { k = nodes[v].next; }
    }
    return 0;
}

fn lsp_hex_digit(v: i64) -> u8 {
    if (v < 10) {
        return (48 + v) as u8;
    }
    return (87 + v) as u8;
}

fn lsp_buf_put_esc(b: &mut LspBuf, c: u8) {
    lsp_buf_putc(b, 92);
    lsp_buf_putc(b, 117);
    lsp_buf_putc(b, 48);
    lsp_buf_putc(b, 48);
    lsp_buf_putc(b, lsp_hex_digit((c as i64) >> 4));
    lsp_buf_putc(b, lsp_hex_digit((c as i64) & 15));
}

fn lsp_json_put_str(b: &mut LspBuf, s: ptr<u8>, n: i64) {
    lsp_buf_putc(b, 34);
    var i: i64 = 0;
    while (i < n) {
        var c: u8 = 0;
        unsafe { c = s[i]; }
        if (c == 34) {
            lsp_buf_putc(b, 92);
            lsp_buf_putc(b, 34);
        } else if (c == 92) {
            lsp_buf_putc(b, 92);
            lsp_buf_putc(b, 92);
        } else if (c < 0x20) {
            lsp_buf_put_esc(b, c);
        } else {
            lsp_buf_putc(b, c);
        }
        i += 1;
    }
    lsp_buf_putc(b, 34);
}

fn lsp_json_put_cstr(b: &mut LspBuf, s: ptr<u8>) {
    lsp_json_put_str(b, s, strlen(s) as i64);
}

fn lsp_json_put_id(b: &mut LspBuf, nodes: ptr<LspJv>, idx: i64) {
    let k: i64 = lsp_jv_kind(nodes, idx);
    if (k == LSP_JV_STR) {
        lsp_json_put_str(b, lsp_jv_str(nodes, idx), lsp_jv_slen(nodes, idx));
        return;
    }
    if (k == LSP_JV_INT || k == LSP_JV_FLOAT) {
        var p: ptr<u8> = null;
        var n: i64 = 0;
        unsafe {
            p = nodes[idx].sp;
            n = nodes[idx].slen;
        }
        lsp_buf_put(b, p, n);
        return;
    }
    lsp_buf_puts(b, "null");
}

struct LspReader {
    buf: ptr<u8>,
    cap: i64,
    len: i64,
    pos: i64,
    mem: ptr<u8>,
    memlen: i64,
    mempos: i64,
    eof: i32
}

struct LspFrame {
    ok: i32,
    p: ptr<u8>,
    len: i64
}

fn lsp_buf_byte(buf: ptr<u8>, at: i64) -> i64 {
    unsafe { return buf[at] as i64; }
}

fn lsp_reader_new() -> LspReader {
    var r: LspReader = zero(LspReader);
    r.cap = 8192;
    r.buf = malloc(r.cap as u64);
    if (r.buf == null) {
        r.cap = 0;
    }
    return r;
}

fn lsp_reader_from_mem(p: ptr<u8>, n: i64) -> LspReader {
    var r: LspReader = lsp_reader_new();
    r.mem = p;
    r.memlen = n;
    r.mempos = 0;
    return r;
}

fn lsp_reader_free(r: &mut LspReader) {
    if (r.buf != null) {
        free(r.buf);
        r.buf = null;
    }
    r.cap = 0;
    r.len = 0;
    r.pos = 0;
}

fn lsp_reader_grow(r: &mut LspReader) -> i32 {
    if (r.cap > 268435456) {
        return 0 - 1;
    }
    let nc: i64 = r.cap * 2;
    var raw: ptr<u8> = realloc(r.buf, nc as u64);
    if (raw == null) {
        return 0 - 1;
    }
    r.buf = raw;
    r.cap = nc;
    return 0;
}

fn lsp_reader_fill(r: &mut LspReader) -> i64 {
    if (r.len == r.cap) {
        if (lsp_reader_grow(r) != 0) {
            return 0 - 1;
        }
    }
    if (r.mem != null) {
        if (r.mempos >= r.memlen) {
            r.eof = 1;
            return 0;
        }
        var want: i64 = r.memlen - r.mempos;
        if (want > r.cap - r.len) {
            want = r.cap - r.len;
        }
        var dst: ptr<u8> = null;
        var src: ptr<u8> = null;
        unsafe { dst = r.buf + r.len; }
        unsafe { src = r.mem + r.mempos; }
        memcpy(dst, src, want as u64);
        r.len += want;
        r.mempos += want;
        return want;
    }
    var got: ptr<u8> = null;
    unsafe { got = r.buf + r.len; }
    let n: i64 = lsp_read(got, r.cap - r.len);
    if (n <= 0) {
        return n;
    }
    r.len += n;
    return n;
}

fn lsp_reader_ensure(r: &mut LspReader, n: i64) -> i32 {
    while (r.len - r.pos < n) {
        if (lsp_reader_fill(r) <= 0) {
            return 0;
        }
    }
    return 1;
}

fn lsp_find_hdr_end(r: &mut LspReader) -> i64 {
    var j: i64 = 0;
    while (1 == 1) {
        let avail: i64 = r.len - r.pos;
        var k: i64 = 0;
        while (k < 4 && j + k < avail) {
            let c: i64 = lsp_buf_byte(r.buf, r.pos + j + k);
            var want: i64 = 13;
            if (k == 1 || k == 3) {
                want = 10;
            }
            if (c != want) {
                break;
            }
            k += 1;
        }
        if (k == 4) {
            return r.pos + j;
        }
        if (j + k >= avail) {
            if (lsp_reader_fill(r) <= 0) {
                return 0 - 1;
            }
        } else {
            j += 1;
        }
    }
    return 0 - 1;
}

fn lsp_header_len(r: &mut LspReader, start: i64, end: i64) -> i64 {
    let pat: ptr<u8> = "content-length";
    var i: i64 = start;
    while (i + 14 <= end) {
        var k: i64 = 0;
        var hit: i32 = 1;
        while (k < 14) {
            var c: i64 = lsp_buf_byte(r.buf, i + k);
            if (c >= 65 && c <= 90) {
                c += 32;
            }
            var w: u8 = 0;
            unsafe { w = pat[k]; }
            if (c != (w as i64)) {
                hit = 0;
                break;
            }
            k += 1;
        }
        if (hit == 1) {
            var j: i64 = i + 14;
            while (j < end && lsp_buf_byte(r.buf, j) != 58) {
                j += 1;
            }
            if (j >= end) {
                return 0 - 1;
            }
            j += 1;
            while (j < end && lsp_buf_byte(r.buf, j) == 32) {
                j += 1;
            }
            var v: i64 = 0;
            var got: i32 = 0;
            while (j < end) {
                let d: i64 = lsp_buf_byte(r.buf, j);
                if (d < 48 || d > 57) {
                    break;
                }
                v = v * 10 + (d - 48);
                if (v > LSP_MAX_MESSAGE) {
                    return 0 - 1;
                }
                got = 1;
                j += 1;
            }
            if (got == 0) {
                return 0 - 1;
            }
            return v;
        }
        i += 1;
    }
    return 0 - 1;
}

fn lsp_read_frame(r: &mut LspReader) -> LspFrame {
    var f: LspFrame = zero(LspFrame);
    if (r.pos == r.len) {
        r.pos = 0;
        r.len = 0;
    }
    let he: i64 = lsp_find_hdr_end(r);
    if (he < 0) {
        f.ok = 0;
        return f;
    }
    let cl: i64 = lsp_header_len(r, r.pos, he);
    if (cl < 0) {
        f.ok = 0 - 1;
        return f;
    }
    r.pos = he + 4;
    if (lsp_reader_ensure(r, cl) == 0) {
        f.ok = 0 - 1;
        return f;
    }
    var mem: ptr<u8> = malloc((cl + 1) as u64);
    if (mem == null) {
        f.ok = 0 - 1;
        return f;
    }
    var src: ptr<u8> = null;
    unsafe { src = r.buf + r.pos; }
    memcpy(mem, src, cl as u64);
    unsafe { mem[cl] = 0; }
    r.pos += cl;
    f.ok = 1;
    f.p = mem;
    f.len = cl;
    return f;
}

fn lsp_frame_header(dst: ptr<u8>, n: i64) -> i64 {
    let pre: ptr<u8> = "Content-Length: ";
    memcpy(dst, pre, 16);
    var at: ptr<u8> = null;
    unsafe { at = dst + 16; }
    var len: i64 = 16 + lsp_digits(at, n);
    unsafe { at = dst + len; }
    let post: ptr<u8> = "\r\n\r\n";
    memcpy(at, post, 4);
    len += 4;
    return len;
}

fn lsp_frame_into(dst: &mut LspBuf, body: &LspBuf) {
    var hdr: [u8; 40] = [0];
    var hp: ptr<u8> = null;
    unsafe { hp = &mut hdr[0] as ptr<u8>; }
    let hn: i64 = lsp_frame_header(hp, body.len);
    lsp_buf_put(dst, hp, hn);
    lsp_buf_put(dst, body.p, body.len);
}

fn lsp_write_frame(body: &LspBuf) {
    var hdr: [u8; 40] = [0];
    var hp: ptr<u8> = null;
    unsafe { hp = &mut hdr[0] as ptr<u8>; }
    let hn: i64 = lsp_frame_header(hp, body.len);
    lsp_write(hp, hn);
    lsp_write(body.p, body.len);
}

struct LspDiag {
    sl: i64,
    sc: i64,
    el: i64,
    ec: i64,
    sev: i32,
    msg: ptr<u8>
}

struct LspScanOut {
    d: [LspDiag; 64],
    n: i32
}

fn lsp_diag_add(out: &mut LspScanOut, sl: i64, sc: i64, el: i64, ec: i64, msg: ptr<u8>) {
    if (out.n >= LSP_MAX_DIAGS) {
        return;
    }
    let i: i64 = out.n as i64;
    out.d[i].sl = sl;
    out.d[i].sc = sc;
    out.d[i].el = el;
    out.d[i].ec = ec;
    out.d[i].sev = 1;
    out.d[i].msg = msg;
    out.n += 1;
}

fn lsp_utf8_span(text: ptr<u8>, len: i64, i: i64) -> i64 {
    let b: i64 = lsp_buf_byte(text, i);
    var n: i64 = 1;
    if (b >= 0xF0) {
        n = 4;
    } else if (b >= 0xE0) {
        n = 3;
    } else if (b >= 0xC0) {
        n = 2;
    }
    if (i + n > len) {
        return 1;
    }
    return n;
}

fn lsp_utf8_cols(text: ptr<u8>, len: i64, i: i64) -> i64 {
    let b: i64 = lsp_buf_byte(text, i);
    if (b >= 0xF0) {
        return 2;
    }
    return 1;
}

fn lsp_msg_unmatched(ch: i64) -> ptr<u8> {
    if (ch == 41) {
        return "unmatched ')'";
    }
    if (ch == 93) {
        return "unmatched ']'";
    }
    return "unmatched '}'";
}

fn lsp_msg_mismatch(ch: i64) -> ptr<u8> {
    if (ch == 41) {
        return "mismatched ')'";
    }
    if (ch == 93) {
        return "mismatched ']'";
    }
    return "mismatched '}'";
}

fn lsp_msg_unclosed(ch: i64) -> ptr<u8> {
    if (ch == 40) {
        return "unclosed '('";
    }
    if (ch == 91) {
        return "unclosed '['";
    }
    return "unclosed '{'";
}

fn lsp_scan(text: ptr<u8>, len: i64, out: &mut LspScanOut) -> i32 {
    out.n = 0;
    var i: i64 = 0;
    var line: i64 = 0;
    var col: i64 = 0;
    var och: [u8; 128] = [0];
    var ol: [i64; 128] = [0];
    var oc: [i64; 128] = [0];
    var depth: i64 = 0;
    while (i < len) {
        let b: i64 = lsp_buf_byte(text, i);
        if (b == 13 || b == 10) {
            i += 1;
            if (b == 13 && i < len && lsp_buf_byte(text, i) == 10) {
                i += 1;
            }
            line += 1;
            col = 0;
            continue;
        }
        if (b == 47 && i + 1 < len) {
            let b2: i64 = lsp_buf_byte(text, i + 1);
            if (b2 == 47) {
                i += 2;
                while (i < len) {
                    let c: i64 = lsp_buf_byte(text, i);
                    if (c == 10 || c == 13) {
                        break;
                    }
                    i += 1;
                }
                continue;
            }
            if (b2 == 42) {
                let sl: i64 = line;
                let sc: i64 = col;
                i += 2;
                var shut: i32 = 0;
                while (i < len) {
                    let c: i64 = lsp_buf_byte(text, i);
                    if (c == 42 && i + 1 < len && lsp_buf_byte(text, i + 1) == 47) {
                        i += 2;
                        shut = 1;
                        break;
                    }
                    if (c == 13 || c == 10) {
                        i += 1;
                        if (c == 13 && i < len && lsp_buf_byte(text, i) == 10) {
                            i += 1;
                        }
                        line += 1;
                        col = 0;
                        continue;
                    }
                    col += lsp_utf8_cols(text, len, i);
                    i += lsp_utf8_span(text, len, i);
                }
                if (shut == 0) {
                    lsp_diag_add(out, sl, sc, sl, sc + 1, "unterminated block comment");
                }
                continue;
            }
        }
        if (b == 34) {
            let sl: i64 = line;
            let sc: i64 = col;
            i += 1;
            col += 1;
            var shut: i32 = 0;
            while (i < len) {
                let c: i64 = lsp_buf_byte(text, i);
                if (c == 92) {
                    if (i + 1 < len) {
                        let c2: i64 = lsp_buf_byte(text, i + 1);
                        if (c2 == 10 || c2 == 13) {
                            break;
                        }
                        i += 2;
                        col += 2;
                        continue;
                    }
                    break;
                }
                if (c == 34) {
                    i += 1;
                    col += 1;
                    shut = 1;
                    break;
                }
                if (c == 10 || c == 13) {
                    break;
                }
                col += lsp_utf8_cols(text, len, i);
                i += lsp_utf8_span(text, len, i);
            }
            if (shut == 0) {
                lsp_diag_add(out, sl, sc, sl, sc + 1, "unterminated string literal");
            }
            continue;
        }
        if (b == 40 || b == 91 || b == 123) {
            if (depth < 128) {
                och[depth] = b as u8;
                ol[depth] = line;
                oc[depth] = col;
                depth += 1;
            }
            col += 1;
            i += 1;
            continue;
        }
        if (b == 41 || b == 93 || b == 125) {
            var want: i64 = 40;
            if (b == 93) {
                want = 91;
            }
            if (b == 125) {
                want = 123;
            }
            if (depth == 0) {
                lsp_diag_add(out, line, col, line, col + 1, lsp_msg_unmatched(b));
            } else {
                let top: i64 = och[depth - 1] as i64;
                depth -= 1;
                if (top != want) {
                    lsp_diag_add(out, line, col, line, col + 1, lsp_msg_mismatch(b));
                }
            }
            col += 1;
            i += 1;
            continue;
        }
        col += lsp_utf8_cols(text, len, i);
        i += lsp_utf8_span(text, len, i);
    }
    var k: i64 = 0;
    while (k < depth) {
        lsp_diag_add(out, ol[k], oc[k], ol[k], oc[k] + 1, lsp_msg_unclosed(och[k] as i64));
        k += 1;
    }
    return out.n;
}

struct LspDoc {
    used: i32,
    uri: ptr<u8>,
    ulen: i64,
    text: ptr<u8>,
    tlen: i64,
    version: i64
}

struct LspSrv {
    docs: [LspDoc; 32],
    ndocs: i32,
    shutdown: i32,
    capture: i32,
    out: LspBuf,
    tmp: LspBuf
}

struct LspPos {
    line: i64,
    col: i64
}

fn lsp_srv_new() -> LspSrv {
    var s: LspSrv = zero(LspSrv);
    s.out = lsp_buf_new(1024);
    s.tmp = lsp_buf_new(1024);
    return s;
}

fn lsp_srv_free(s: &mut LspSrv) {
    var i: i64 = 0;
    while (i < LSP_MAX_DOCS as i64) {
        if (s.docs[i].used == 1) {
            if (s.docs[i].text != null) {
                free(s.docs[i].text);
            }
            if (s.docs[i].uri != null) {
                free(s.docs[i].uri);
            }
            s.docs[i].used = 0;
        }
        i += 1;
    }
    s.ndocs = 0;
    lsp_buf_free(&mut s.out);
    lsp_buf_free(&mut s.tmp);
}

fn lsp_doc_find(s: &mut LspSrv, uri: ptr<u8>, ulen: i64) -> i64 {
    var i: i64 = 0;
    while (i < LSP_MAX_DOCS as i64) {
        if (s.docs[i].used == 1) {
            if (lsp_eqn(s.docs[i].uri, s.docs[i].ulen, uri, ulen) == 1) {
                return i;
            }
        }
        i += 1;
    }
    return 0 - 1;
}

fn lsp_doc_set_text(s: &mut LspSrv, idx: i64, text: ptr<u8>, tlen: i64) -> i32 {
    var mem: ptr<u8> = malloc((tlen + 1) as u64);
    if (mem == null) {
        return 0 - 1;
    }
    memcpy(mem, text, tlen as u64);
    unsafe { mem[tlen] = 0; }
    if (s.docs[idx].text != null) {
        free(s.docs[idx].text);
    }
    s.docs[idx].text = mem;
    s.docs[idx].tlen = tlen;
    return 0;
}

fn lsp_doc_open(s: &mut LspSrv, uri: ptr<u8>, ulen: i64, text: ptr<u8>, tlen: i64, version: i64) -> i64 {
    var idx: i64 = lsp_doc_find(s, uri, ulen);
    if (idx < 0) {
        var k: i64 = 0;
        while (k < LSP_MAX_DOCS as i64) {
            if (s.docs[k].used == 0) {
                idx = k;
                break;
            }
            k += 1;
        }
        if (idx < 0) {
            return 0 - 1;
        }
        var up: ptr<u8> = malloc((ulen + 1) as u64);
        if (up == null) {
            return 0 - 1;
        }
        memcpy(up, uri, ulen as u64);
        unsafe { up[ulen] = 0; }
        s.docs[idx].used = 1;
        s.docs[idx].uri = up;
        s.docs[idx].ulen = ulen;
        s.docs[idx].text = null;
        s.docs[idx].tlen = 0;
        s.ndocs += 1;
    }
    if (lsp_doc_set_text(s, idx, text, tlen) != 0) {
        return 0 - 1;
    }
    s.docs[idx].version = version;
    return idx;
}

fn lsp_doc_close(s: &mut LspSrv, uri: ptr<u8>, ulen: i64) -> i32 {
    let idx: i64 = lsp_doc_find(s, uri, ulen);
    if (idx < 0) {
        return 0 - 1;
    }
    if (s.docs[idx].text != null) {
        free(s.docs[idx].text);
    }
    if (s.docs[idx].uri != null) {
        free(s.docs[idx].uri);
    }
    s.docs[idx].used = 0;
    s.docs[idx].text = null;
    s.docs[idx].tlen = 0;
    s.docs[idx].uri = null;
    s.docs[idx].ulen = 0;
    s.docs[idx].version = 0;
    s.ndocs -= 1;
    return 0;
}

fn lsp_msg_begin(s: &mut LspSrv, nodes: ptr<LspJv>, id: i64) {
    lsp_buf_clear(&mut s.tmp);
    lsp_buf_puts(&mut s.tmp, "{\"jsonrpc\":\"2.0\",\"id\":");
    lsp_json_put_id(&mut s.tmp, nodes, id);
}

fn lsp_msg_notice(s: &mut LspSrv, method: ptr<u8>) {
    lsp_buf_clear(&mut s.tmp);
    lsp_buf_puts(&mut s.tmp, "{\"jsonrpc\":\"2.0\",\"method\":");
    lsp_json_put_cstr(&mut s.tmp, method);
}

fn lsp_send(s: &mut LspSrv) {
    if (s.tmp.err == 1) {
        return;
    }
    if (s.capture == 1) {
        var body: LspBuf = s.tmp;
        lsp_frame_into(&mut s.out, &body);
        return;
    }
    lsp_write_frame(&s.tmp);
}

fn lsp_publish(s: &mut LspSrv, idx: i64) {
    let uri: ptr<u8> = s.docs[idx].uri;
    let ulen: i64 = s.docs[idx].ulen;
    let text: ptr<u8> = s.docs[idx].text;
    let tlen: i64 = s.docs[idx].tlen;
    let ver: i64 = s.docs[idx].version;
    var sc: LspScanOut = zero(LspScanOut);
    lsp_scan(text, tlen, &mut sc);
    lsp_msg_notice(s, "textDocument/publishDiagnostics");
    lsp_buf_puts(&mut s.tmp, ",\"params\":{\"uri\":");
    lsp_json_put_str(&mut s.tmp, uri, ulen);
    lsp_buf_puts(&mut s.tmp, ",\"version\":");
    lsp_buf_putu(&mut s.tmp, ver);
    lsp_buf_puts(&mut s.tmp, ",\"diagnostics\":[");
    var k: i64 = 0;
    while (k < sc.n as i64) {
        if (k > 0) {
            lsp_buf_putc(&mut s.tmp, 44);
        }
        lsp_buf_puts(&mut s.tmp, "{\"range\":{\"start\":{\"line\":");
        lsp_buf_putu(&mut s.tmp, sc.d[k].sl);
        lsp_buf_puts(&mut s.tmp, ",\"character\":");
        lsp_buf_putu(&mut s.tmp, sc.d[k].sc);
        lsp_buf_puts(&mut s.tmp, "},\"end\":{\"line\":");
        lsp_buf_putu(&mut s.tmp, sc.d[k].el);
        lsp_buf_puts(&mut s.tmp, ",\"character\":");
        lsp_buf_putu(&mut s.tmp, sc.d[k].ec);
        lsp_buf_puts(&mut s.tmp, "}},\"severity\":");
        lsp_buf_putu(&mut s.tmp, sc.d[k].sev as i64);
        lsp_buf_puts(&mut s.tmp, ",\"source\":\"rsharp\",\"message\":");
        lsp_json_put_cstr(&mut s.tmp, sc.d[k].msg);
        lsp_buf_putc(&mut s.tmp, 125);
        k += 1;
    }
    lsp_buf_puts(&mut s.tmp, "]}}");
    lsp_send(s);
}

fn lsp_publish_empty(s: &mut LspSrv, uri: ptr<u8>, ulen: i64, ver: i64) {
    lsp_msg_notice(s, "textDocument/publishDiagnostics");
    lsp_buf_puts(&mut s.tmp, ",\"params\":{\"uri\":");
    lsp_json_put_str(&mut s.tmp, uri, ulen);
    lsp_buf_puts(&mut s.tmp, ",\"version\":");
    lsp_buf_putu(&mut s.tmp, ver);
    lsp_buf_puts(&mut s.tmp, ",\"diagnostics\":[]}}");
    lsp_send(s);
}

fn lsp_word_char(c: i64) -> i32 {
    if (c >= 65 && c <= 90) {
        return 1;
    }
    if (c >= 97 && c <= 122) {
        return 1;
    }
    if (c >= 48 && c <= 57) {
        return 1;
    }
    if (c == 95) {
        return 1;
    }
    return 0;
}

fn lsp_offset_at(text: ptr<u8>, len: i64, line: i64, ch: i64) -> i64 {
    var i: i64 = 0;
    var l: i64 = 0;
    var c: i64 = 0;
    while (i < len) {
        if (l == line && c >= ch) {
            return i;
        }
        let b: i64 = lsp_buf_byte(text, i);
        if (b == 13) {
            var nx: i64 = 0;
            if (i + 1 < len) {
                nx = lsp_buf_byte(text, i + 1);
            }
            if (l == line) {
                return i;
            }
            i += 1;
            if (nx == 10) {
                i += 1;
            }
            l += 1;
            c = 0;
            continue;
        }
        if (b == 10) {
            if (l == line) {
                return i;
            }
            i += 1;
            l += 1;
            c = 0;
            continue;
        }
        c += lsp_utf8_cols(text, len, i);
        i += lsp_utf8_span(text, len, i);
    }
    return len;
}

fn lsp_pos_at(text: ptr<u8>, len: i64, off: i64) -> LspPos {
    var p: LspPos = zero(LspPos);
    var i: i64 = 0;
    while (i < off && i < len) {
        let b: i64 = lsp_buf_byte(text, i);
        if (b == 13) {
            i += 1;
            if (i < len && lsp_buf_byte(text, i) == 10) {
                i += 1;
            }
            p.line += 1;
            p.col = 0;
            continue;
        }
        if (b == 10) {
            i += 1;
            p.line += 1;
            p.col = 0;
            continue;
        }
        p.col += lsp_utf8_cols(text, len, i);
        i += lsp_utf8_span(text, len, i);
    }
    return p;
}

fn lsp_word_doc(p: ptr<u8>, n: i64) -> ptr<u8> {
    if (lsp_word_is(p, n, "fn") == 1) {
        return "fn declares a function; extern fn binds a system symbol at link time";
    }
    if (lsp_word_is(p, n, "let") == 1) {
        return "let binds an immutable name, typed from the initialiser when unannotated";
    }
    if (lsp_word_is(p, n, "var") == 1) {
        return "var binds a mutable name; assignment and &mut both need one";
    }
    if (lsp_word_is(p, n, "const") == 1) {
        return "const is folded at compile time and usable as an array size";
    }
    if (lsp_word_is(p, n, "struct") == 1) {
        return "struct is an aggregate with named fields; a return comes back through a hidden pointer";
    }
    if (lsp_word_is(p, n, "enum") == 1) {
        return "enum is a tagged union; the tag is an i64 at offset 0, the payload starts at 8";
    }
    if (lsp_word_is(p, n, "match") == 1) {
        return "match compares the tag once and binds the payload into each arm";
    }
    if (lsp_word_is(p, n, "while") == 1) {
        return "while loops on a parenthesised condition";
    }
    if (lsp_word_is(p, n, "loop") == 1) {
        return "loop repeats without a condition; leave it with break";
    }
    if (lsp_word_is(p, n, "for") == 1) {
        return "for i in 0..n counts up half-open; 0..=n includes the last value";
    }
    if (lsp_word_is(p, n, "break") == 1) {
        return "break leaves the nearest loop";
    }
    if (lsp_word_is(p, n, "continue") == 1) {
        return "continue jumps to the next iteration of the nearest loop";
    }
    if (lsp_word_is(p, n, "return") == 1) {
        return "return leaves the function with its value";
    }
    if (lsp_word_is(p, n, "unsafe") == 1) {
        return "unsafe allows raw pointer reads, writes, indexing and arithmetic";
    }
    if (lsp_word_is(p, n, "include") == 1) {
        return "include splices another source file at this point";
    }
    if (lsp_word_is(p, n, "extern") == 1) {
        return "extern imports a symbol from a named library; extern fn is a C ABI function pointer";
    }
    if (lsp_word_is(p, n, "ptr") == 1) {
        return "ptr<T> is a raw pointer; touching it needs unsafe";
    }
    if (lsp_word_is(p, n, "Box") == 1) {
        return "Box<T> owns a heap allocation and frees it at scope exit";
    }
    if (lsp_word_is(p, n, "zero") == 1) {
        return "zero(T) is the zero value of T";
    }
    if (lsp_word_is(p, n, "sizeof") == 1) {
        return "sizeof(T) is the size of T in bytes, as u64";
    }
    if (lsp_word_is(p, n, "null") == 1) {
        return "null is the null pointer";
    }
    if (lsp_word_is(p, n, "as") == 1) {
        return "as is the explicit cast and the only conversion there is";
    }
    if (lsp_word_is(p, n, "true") == 1 || lsp_word_is(p, n, "false") == 1) {
        return "bool literal";
    }
    if (lsp_word_is(p, n, "i8") == 1 || lsp_word_is(p, n, "i16") == 1 || lsp_word_is(p, n, "i32") == 1 || lsp_word_is(p, n, "i64") == 1) {
        return "signed integer, two's complement";
    }
    if (lsp_word_is(p, n, "u8") == 1 || lsp_word_is(p, n, "u16") == 1 || lsp_word_is(p, n, "u32") == 1 || lsp_word_is(p, n, "u64") == 1) {
        return "unsigned integer";
    }
    if (lsp_word_is(p, n, "f32") == 1 || lsp_word_is(p, n, "f64") == 1) {
        return "IEEE 754 floating point";
    }
    if (lsp_word_is(p, n, "bool") == 1) {
        return "bool is true or false";
    }
    if (lsp_word_is(p, n, "void") == 1) {
        return "void is the empty return type";
    }
    return null;
}

fn lsp_on_initialize(s: &mut LspSrv, nodes: ptr<LspJv>, id: i64) {
    lsp_msg_begin(s, nodes, id);
    lsp_buf_puts(&mut s.tmp, ",\"result\":{\"capabilities\":{\"textDocumentSync\":{\"openClose\":true,\"change\":1},\"hoverProvider\":true,\"positionEncoding\":\"utf-16\"},\"serverInfo\":{\"name\":\"rsharp\",\"version\":\"1.2\"}}}");
    lsp_send(s);
}

fn lsp_on_open(s: &mut LspSrv, nodes: ptr<LspJv>) -> i32 {
    let params: i64 = lsp_jv_get(nodes, 1, "params");
    let td: i64 = lsp_jv_get(nodes, params, "textDocument");
    let uri: i64 = lsp_jv_get(nodes, td, "uri");
    let txt: i64 = lsp_jv_get(nodes, td, "text");
    if (uri == 0 || txt == 0) {
        return 0;
    }
    let idx: i64 = lsp_doc_open(s, lsp_jv_str(nodes, uri), lsp_jv_slen(nodes, uri), lsp_jv_str(nodes, txt), lsp_jv_slen(nodes, txt), lsp_jv_int(nodes, lsp_jv_get(nodes, td, "version")));
    if (idx >= 0) {
        lsp_publish(s, idx);
    }
    return 0;
}

fn lsp_on_change(s: &mut LspSrv, nodes: ptr<LspJv>) -> i32 {
    let params: i64 = lsp_jv_get(nodes, 1, "params");
    let td: i64 = lsp_jv_get(nodes, params, "textDocument");
    let uri: i64 = lsp_jv_get(nodes, td, "uri");
    if (uri == 0) {
        return 0;
    }
    let idx: i64 = lsp_doc_find(s, lsp_jv_str(nodes, uri), lsp_jv_slen(nodes, uri));
    if (idx < 0) {
        return 0;
    }
    let changes: i64 = lsp_jv_get(nodes, params, "contentChanges");
    let n: i64 = lsp_jv_count(nodes, changes);
    if (n == 0) {
        return 0;
    }
    let last: i64 = lsp_jv_at(nodes, changes, n - 1);
    let txt: i64 = lsp_jv_get(nodes, last, "text");
    if (txt == 0) {
        return 0;
    }
    if (lsp_doc_set_text(s, idx, lsp_jv_str(nodes, txt), lsp_jv_slen(nodes, txt)) != 0) {
        return 0;
    }
    s.docs[idx].version = lsp_jv_int(nodes, lsp_jv_get(nodes, td, "version"));
    lsp_publish(s, idx);
    return 0;
}

fn lsp_on_close(s: &mut LspSrv, nodes: ptr<LspJv>) -> i32 {
    let params: i64 = lsp_jv_get(nodes, 1, "params");
    let td: i64 = lsp_jv_get(nodes, params, "textDocument");
    let uri: i64 = lsp_jv_get(nodes, td, "uri");
    if (uri == 0) {
        return 0;
    }
    let up: ptr<u8> = lsp_jv_str(nodes, uri);
    let ul: i64 = lsp_jv_slen(nodes, uri);
    let idx: i64 = lsp_doc_find(s, up, ul);
    if (idx < 0) {
        return 0;
    }
    let ver: i64 = s.docs[idx].version;
    lsp_publish_empty(s, up, ul, ver);
    lsp_doc_close(s, up, ul);
    return 0;
}

fn lsp_on_hover(s: &mut LspSrv, nodes: ptr<LspJv>, id: i64) -> i32 {
    let params: i64 = lsp_jv_get(nodes, 1, "params");
    let td: i64 = lsp_jv_get(nodes, params, "textDocument");
    let pos: i64 = lsp_jv_get(nodes, params, "position");
    let uri: i64 = lsp_jv_get(nodes, td, "uri");
    let ln: i64 = lsp_jv_int(nodes, lsp_jv_get(nodes, pos, "line"));
    let ch: i64 = lsp_jv_int(nodes, lsp_jv_get(nodes, pos, "character"));
    var answer: ptr<u8> = null;
    var sl: i64 = 0;
    var sc: i64 = 0;
    var el: i64 = 0;
    var ec: i64 = 0;
    if (uri != 0) {
        let idx: i64 = lsp_doc_find(s, lsp_jv_str(nodes, uri), lsp_jv_slen(nodes, uri));
        if (idx >= 0) {
            let text: ptr<u8> = s.docs[idx].text;
            let tlen: i64 = s.docs[idx].tlen;
            let off: i64 = lsp_offset_at(text, tlen, ln, ch);
            var a: i64 = off;
            var b: i64 = off;
            while (a > 0) {
                var c: i64 = 0;
                unsafe { c = text[a - 1] as i64; }
                if (lsp_word_char(c) == 0) {
                    break;
                }
                a -= 1;
            }
            while (b < tlen) {
                var c: i64 = 0;
                unsafe { c = text[b] as i64; }
                if (lsp_word_char(c) == 0) {
                    break;
                }
                b += 1;
            }
            if (b > a) {
                var wp: ptr<u8> = null;
                unsafe { wp = text + a; }
                answer = lsp_word_doc(wp, b - a);
                if (answer != null) {
                    let pa: LspPos = lsp_pos_at(text, tlen, a);
                    let pb: LspPos = lsp_pos_at(text, tlen, b);
                    sl = pa.line;
                    sc = pa.col;
                    el = pb.line;
                    ec = pb.col;
                }
            }
        }
    }
    lsp_msg_begin(s, nodes, id);
    if (answer == null) {
        lsp_buf_puts(&mut s.tmp, ",\"result\":null}");
        lsp_send(s);
        return 0;
    }
    lsp_buf_puts(&mut s.tmp, ",\"result\":{\"contents\":{\"kind\":\"plaintext\",\"value\":");
    lsp_json_put_cstr(&mut s.tmp, answer);
    lsp_buf_puts(&mut s.tmp, "},\"range\":{\"start\":{\"line\":");
    lsp_buf_putu(&mut s.tmp, sl);
    lsp_buf_puts(&mut s.tmp, ",\"character\":");
    lsp_buf_putu(&mut s.tmp, sc);
    lsp_buf_puts(&mut s.tmp, "},\"end\":{\"line\":");
    lsp_buf_putu(&mut s.tmp, el);
    lsp_buf_puts(&mut s.tmp, ",\"character\":");
    lsp_buf_putu(&mut s.tmp, ec);
    lsp_buf_puts(&mut s.tmp, "}}}}");
    lsp_send(s);
    return 0;
}

fn lsp_error_method(s: &mut LspSrv, nodes: ptr<LspJv>, id: i64, name: ptr<u8>) {
    var mb: LspBuf = lsp_buf_new(64);
    lsp_buf_puts(&mut mb, "method not found: ");
    lsp_buf_puts(&mut mb, name);
    lsp_msg_begin(s, nodes, id);
    lsp_buf_puts(&mut s.tmp, ",\"error\":{\"code\":-32601,\"message\":");
    lsp_json_put_str(&mut s.tmp, mb.p, mb.len);
    lsp_buf_puts(&mut s.tmp, "}}");
    lsp_send(s);
    lsp_buf_free(&mut mb);
}

fn lsp_error_parse(s: &mut LspSrv) {
    lsp_buf_clear(&mut s.tmp);
    lsp_buf_puts(&mut s.tmp, "{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32700,\"message\":\"parse error\"}}");
    lsp_send(s);
}

fn lsp_handle(s: &mut LspSrv, jp: &LspJp) -> i32 {
    let nodes: ptr<LspJv> = jp.nodes;
    let m: i64 = lsp_jv_get(nodes, 1, "method");
    if (m == 0) {
        return 0;
    }
    let name: ptr<u8> = lsp_jv_str(nodes, m);
    if (name == null) {
        return 0;
    }
    let id: i64 = lsp_jv_get(nodes, 1, "id");
    var has_id: i32 = 0;
    if (id != 0 && lsp_jv_kind(nodes, id) != LSP_JV_NULL) {
        has_id = 1;
    }
    if (lsp_eq(name, "initialize") == 1) {
        if (has_id == 1) {
            lsp_on_initialize(s, nodes, id);
        }
        return 0;
    }
    if (lsp_eq(name, "initialized") == 1) {
        return 0;
    }
    if (lsp_eq(name, "shutdown") == 1) {
        if (has_id == 1) {
            lsp_msg_begin(s, nodes, id);
            lsp_buf_puts(&mut s.tmp, ",\"result\":null}");
            lsp_send(s);
        }
        s.shutdown = 1;
        return 0;
    }
    if (lsp_eq(name, "exit") == 1) {
        return 1;
    }
    if (lsp_eq(name, "$/cancelRequest") == 1) {
        return 0;
    }
    if (lsp_eq(name, "$/setTrace") == 1) {
        return 0;
    }
    if (lsp_eq(name, "textDocument/didOpen") == 1) {
        return lsp_on_open(s, nodes);
    }
    if (lsp_eq(name, "textDocument/didChange") == 1) {
        return lsp_on_change(s, nodes);
    }
    if (lsp_eq(name, "textDocument/didClose") == 1) {
        return lsp_on_close(s, nodes);
    }
    if (lsp_eq(name, "textDocument/hover") == 1) {
        if (has_id == 1) {
            return lsp_on_hover(s, nodes, id);
        }
        return 0;
    }
    if (has_id == 1) {
        lsp_error_method(s, nodes, id, name);
    }
    return 0;
}

fn lsp_serve(s: &mut LspSrv, r: &mut LspReader) -> i32 {
    var code: i32 = 0;
    var go: i32 = 1;
    while (go == 1) {
        var f: LspFrame = lsp_read_frame(r);
        if (f.ok != 1) {
            go = 0;
            if (f.ok != 0) {
                code = 1;
            }
        } else {
            var jp: LspJp = lsp_json_parse(f.p, f.len);
            if (jp.ok == 0) {
                lsp_error_parse(s);
            } else if (lsp_handle(s, &jp) == 1) {
                go = 0;
                if (s.shutdown == 0) {
                    code = 1;
                }
            }
            lsp_json_free(&mut jp);
            free(f.p);
        }
    }
    return code;
}

fn lsp_main() -> i32 {
    var s: LspSrv = lsp_srv_new();
    if (s.out.err == 1 || s.tmp.err == 1) {
        return 1;
    }
    var r: LspReader = lsp_reader_new();
    if (r.buf == null) {
        lsp_srv_free(&mut s);
        return 1;
    }
    let code: i32 = lsp_serve(&mut s, &mut r);
    lsp_reader_free(&mut r);
    lsp_srv_free(&mut s);
    return code;
}

