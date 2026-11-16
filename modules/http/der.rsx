include "rt.rsx";

const DER_CLASS_UNIVERSAL: i32 = 0;
const DER_TAG_BOOLEAN: u8 = 1;
const DER_TAG_INTEGER: u8 = 2;
const DER_TAG_BITSTRING: u8 = 3;
const DER_TAG_OCTETSTRING: u8 = 4;
const DER_TAG_NULL: u8 = 5;
const DER_TAG_OID: u8 = 6;
const DER_TAG_UTF8STRING: u8 = 12;
const DER_TAG_SEQUENCE: u8 = 48;
const DER_TAG_SET: u8 = 49;
const DER_TAG_PRINTABLESTRING: u8 = 19;
const DER_TAG_T61STRING: u8 = 20;
const DER_TAG_IA5STRING: u8 = 22;
const DER_TAG_UTCTIME: u8 = 23;
const DER_TAG_GENERALIZEDTIME: u8 = 24;
const DER_TAG_BMPSTRING: u8 = 30;

struct Der {
    p: ptr<u8>,
    len: i64,
    off: i64
}

struct Tlv {
    tag: u8,
    p: ptr<u8>,
    len: i64,
    start: i64,
    hdr: i64
}

fn der_init(d: &mut Der, p: ptr<u8>, len: i64) {
    d.p = p;
    d.len = len;
    d.off = 0;
}

fn der_remaining(d: &mut Der) -> i64 {
    return d.len - d.off;
}

fn der_tlv_at(d: &mut Der, at: i64, t: &mut Tlv) -> i32 {
    if (at < 0 || at >= d.len) {
        return -1;
    }
    var base: ptr<u8> = null;
    unsafe { base = d.p + at; }
    var tag: u8 = 0;
    unsafe { tag = base[0]; }
    if ((tag & 31) == 31) {
        return -1;
    }

    var pos: i64 = 1;
    var avail: i64 = d.len - at;
    if (pos >= avail) {
        return -1;
    }
    var l0: u8 = 0;
    unsafe { l0 = base[pos]; }
    pos += 1;

    var clen: i64 = 0;
    if (l0 < 128) {
        clen = l0 as i64;
    } else {
        let nb: i64 = (l0 & 127) as i64;
        if (nb < 1 || nb > 4) {
            return -1;
        }
        if (pos + nb > avail) {
            return -1;
        }
        var i: i64 = 0;
        while (i < nb) {
            var b: u8 = 0;
            unsafe { b = base[pos + i]; }
            clen = (clen << 8) | (b as i64);
            i += 1;
        }
        pos += nb;
        if (clen < 0) {
            return -1;
        }
    }
    if (clen > avail - pos) {
        return -1;
    }

    var content: ptr<u8> = null;
    unsafe { content = base + pos; }
    t.tag = tag;
    t.p = content;
    t.len = clen;
    t.start = at;
    t.hdr = pos;
    return 0;
}

fn der_next(d: &mut Der, t: &mut Tlv) -> i32 {
    if (der_tlv_at(d, d.off, t) != 0) {
        return -1;
    }
    d.off = d.off + t.hdr + t.len;
    return 0;
}

fn der_peek(d: &mut Der, t: &mut Tlv) -> i32 {
    return der_tlv_at(d, d.off, t);
}

fn der_skip(d: &mut Der) -> i32 {
    var t: Tlv = zero(Tlv);
    let rc: i32 = der_next(d, &mut t);
    return rc;
}

fn der_skip_n(d: &mut Der, n: i64) -> i32 {
    var i: i64 = 0;
    while (i < n) {
        if (der_skip(d) != 0) {
            return -1;
        }
        i += 1;
    }
    return 0;
}

fn der_expect(d: &mut Der, tag: u8, t: &mut Tlv) -> i32 {
    if (der_next(d, t) != 0) {
        return -1;
    }
    if (t.tag != tag) {
        return -1;
    }
    return 0;
}

fn der_sub(t: &mut Tlv, d: &mut Der) {
    der_init(d, t.p, t.len);
}

fn der_bytes_eq(a: ptr<u8>, b: ptr<u8>, n: i64) -> i32 {
    return rt_bytes_eq(a, b, n);
}

fn der_uint(t: &mut Tlv, out: ptr<u8>, maxn: i64) -> i64 {
    if (t.tag != DER_TAG_INTEGER) {
        return -1;
    }
    if (t.len <= 0) {
        return -1;
    }
    var off: i64 = 0;
    while (off < t.len - 1) {
        var b: u8 = 0;
        unsafe { b = t.p[off]; }
        if (b != 0) {
            break;
        }
        off += 1;
    }
    let n: i64 = t.len - off;
    if (n > maxn) {
        return -1;
    }
    rt_copy(out, rt_add(t.p, off), n);
    return n;
}

fn der_uint_fixed(t: &mut Tlv, out: ptr<u8>, width: i64) -> i32 {
    if (t.tag != DER_TAG_INTEGER) {
        return -1;
    }
    if (t.len <= 0 || t.len > width) {
        return -1;
    }
    var off: i64 = 0;
    while (off < t.len - 1) {
        var b: u8 = 0;
        unsafe { b = t.p[off]; }
        if (b != 0) {
            break;
        }
        off += 1;
    }
    let n: i64 = t.len - off;
    if (n > width) {
        return -1;
    }
    rt_zero(out, width);
    rt_copy(rt_add(out, width - n), rt_add(t.p, off), n);
    return 0;
}

fn der_oid_eq(t: &mut Tlv, oid: ptr<u8>, n: i64) -> i32 {
    if (t.tag != DER_TAG_OID) {
        return 0;
    }
    if (t.len != n) {
        return 0;
    }
    return rt_bytes_eq(t.p, oid, n);
}

fn der_is_constructed(t: &mut Tlv) -> i32 {
    if ((t.tag & 32) != 0) {
        return 1;
    }
    return 0;
}

fn der_digit(p: ptr<u8>, i: i64) -> i64 {
    var c: u8 = 0;
    unsafe { c = p[i]; }
    if (c < 48 || c > 57) {
        return -1;
    }
    return (c - 48) as i64;
}

fn der_num2(p: ptr<u8>, i: i64) -> i64 {
    let a: i64 = der_digit(p, i);
    let b: i64 = der_digit(p, i + 1);
    if (a < 0 || b < 0) {
        return -1;
    }
    return a * 10 + b;
}

fn der_days_from_civil(y: i64, m: i64, d: i64) -> i64 {
    var yy: i64 = y;
    if (m <= 2) {
        yy -= 1;
    }
    var era: i64 = yy;
    if (era < 0) {
        era -= 399;
    }
    era = era / 400;
    let yoe: i64 = yy - era * 400;
    var mp: i64 = m - 3;
    if (m <= 2) {
        mp = m + 9;
    }
    let doy: i64 = (153 * mp + 2) / 5 + d - 1;
    let doe: i64 = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    return era * 146097 + doe - 719468;
}

fn der_time(t: &mut Tlv) -> i64 {
    var y: i64 = 0;
    var i: i64 = 0;
    if (t.tag == DER_TAG_UTCTIME) {
        if (t.len != 13) {
            return -1;
        }
        let yy: i64 = der_num2(t.p, 0);
        if (yy < 0) {
            return -1;
        }
        if (yy < 50) {
            y = 2000 + yy;
        } else {
            y = 1900 + yy;
        }
        i = 2;
    } else if (t.tag == DER_TAG_GENERALIZEDTIME) {
        if (t.len != 15) {
            return -1;
        }
        if (der_digit(t.p, 0) < 0) {
            return -1;
        }
        y = der_num2(t.p, 0) * 100 + der_num2(t.p, 2);
        i = 4;
    } else {
        return -1;
    }

    let mo: i64 = der_num2(t.p, i);
    let da: i64 = der_num2(t.p, i + 2);
    let hh: i64 = der_num2(t.p, i + 4);
    let mi: i64 = der_num2(t.p, i + 6);
    let ss: i64 = der_num2(t.p, i + 8);
    if (mo < 1 || mo > 12 || da < 1 || da > 31 || hh < 0 || hh > 23 || mi < 0 || mi > 59 || ss < 0 || ss > 60) {
        return -1;
    }
    var z: u8 = 0;
    unsafe { z = t.p[t.len - 1]; }
    if (z != 90) {
        return -1;
    }
    return der_days_from_civil(y, mo, da) * 86400 + hh * 3600 + mi * 60 + ss;
}
