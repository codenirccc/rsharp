include "../../modules/http/rt.rsx";
include "../../modules/http/transport_win.rsx";
include "../../modules/http/qpack.rsx";
include "qpack_vec.rsx";

struct Tally {
    pass: i64,
    total: i64
}

fn t_ok(t: &mut Tally, name: ptr<u8>, good: bool) {
    t.total += 1;
    if (good) {
        t.pass += 1;
    } else {
        printf("FAIL %s\n", name);
    }
}

fn hdr_is(q: &mut Qpack, i: i64, name: ptr<u8>, value: ptr<u8>) -> bool {
    return qpack_header_is(q, i, name, value) == 1;
}

fn dec_hex(q: &mut Qpack, hex: ptr<u8>, buf: ptr<u8>, cap: i64) -> i32 {
    let n: i64 = rt_parse_hex(hex, buf, cap);
    if (n <= 0) {
        return QPACK_ERR;
    }
    return qpk_decode(q, buf, n);
}

fn main() -> i32 {
    var t: Tally = zero(Tally);
    var q: Qpack = qpack_new();
    t_ok(&mut t, "huffman tree builds", qpack_ready(&mut q) == 1);
    t_ok(&mut t, "tree node count", q.tree.nodes == 513);

    t_ok(&mut t, "static count is 99", QPACK_STATIC_N == 99);
    var sp: ptr<u8> = qpack_static_name(17);
    var sv: ptr<u8> = qpack_static_value(17);
    t_ok(&mut t, "static 17 name", rt_eq(sp, ":method") == 1);
    t_ok(&mut t, "static 17 value", rt_eq(sv, "GET") == 1);
    t_ok(&mut t, "static 0 name", rt_eq(qpack_static_name(0), ":authority") == 1);
    t_ok(&mut t, "static 0 value empty", rt_len(qpack_static_value(0)) == 0);
    t_ok(&mut t, "static 98 name", rt_eq(qpack_static_name(98), "x-frame-options") == 1);
    t_ok(&mut t, "static 98 value", rt_eq(qpack_static_value(98), "sameorigin") == 1);
    t_ok(&mut t, "static 25 status", rt_eq(qpack_static_value(25), "200") == 1);

    var blkb: [u8; 4096] = [0];
    var bp: ptr<u8> = null;
    unsafe { bp = &mut blkb[0] as ptr<u8>; }

    var vec_bad: i64 = 0;
    var hdr_total: i64 = 0;
    var vi: i64 = 0;
    while (vi < QPACK_VEC_N) {
        let rc: i32 = dec_hex(&mut q, qvec_block(vi), bp, 4096);
        let want: i64 = qvec_hn(vi);
        let first: i64 = qvec_hoff(vi);
        var good: bool = rc == QPACK_OK && qpack_count(&mut q) == want;
        var j: i64 = 0;
        while (good && j < want) {
            let np: ptr<u8> = qvec_hname(first + j);
            let vp: ptr<u8> = qvec_hval(first + j);
            if (!hdr_is(&mut q, j, np, vp)) {
                good = false;
                printf("vector %lld header %lld mismatch\n", vi, j);
            } else {
                hdr_total += 1;
            }
            j += 1;
        }
        if (!good) {
            vec_bad += 1;
            printf("vector %lld failed\n", vi);
        }
        vi += 1;
    }
    t_ok(&mut t, "all reference vectors decode", vec_bad == 0);
    t_ok(&mut t, "vector header count", hdr_total == QPACK_VEC_H);

    let r1: i32 = dec_hex(&mut q, "0000d1", bp, 4096);
    t_ok(&mut t, "indexed :method get", r1 == QPACK_OK && qpack_count(&mut q) == 1);
    t_ok(&mut t, "indexed :method get value", hdr_is(&mut q, 0, ":method", "GET"));

    let r2: i32 = dec_hex(&mut q, "0000d9", bp, 4096);
    t_ok(&mut t, "indexed :status 200", r2 == QPACK_OK && hdr_is(&mut q, 0, ":status", "200"));

    let r3: i32 = dec_hex(&mut q, "0000c0", bp, 4096);
    t_ok(&mut t, "indexed empty value", r3 == QPACK_OK && hdr_is(&mut q, 0, ":authority", ""));

    let r4: i32 = dec_hex(&mut q, "0000500178", bp, 4096);
    t_ok(&mut t, "name ref literal value", r4 == QPACK_OK && hdr_is(&mut q, 0, ":authority", "x"));

    let r5: i32 = dec_hex(&mut q, "00002701782d7273686172700131", bp, 4096);
    t_ok(&mut t, "literal name and value", r5 == QPACK_OK && hdr_is(&mut q, 0, "x-rsharp", "1"));

    let r6: i32 = dec_hex(&mut q, "0000", bp, 4096);
    t_ok(&mut t, "empty field section", r6 == QPACK_OK && qpack_count(&mut q) == 0);

    let r7: i32 = dec_hex(&mut q, "0001d1", bp, 4096);
    t_ok(&mut t, "nonzero delta base rejected", r7 == QPACK_ERR);

    let r8: i32 = dec_hex(&mut q, "0100d1", bp, 4096);
    t_ok(&mut t, "nonzero insert count rejected", r8 == QPACK_ERR);

    let r9: i32 = dec_hex(&mut q, "000081", bp, 4096);
    t_ok(&mut t, "dynamic indexed rejected", r9 == QPACK_ERR);

    let r10: i32 = dec_hex(&mut q, "000041", bp, 4096);
    t_ok(&mut t, "dynamic name ref rejected", r10 == QPACK_ERR);

    let r11: i32 = dec_hex(&mut q, "000011", bp, 4096);
    t_ok(&mut t, "post base indexed rejected", r11 == QPACK_ERR);

    let r12: i32 = dec_hex(&mut q, "000001", bp, 4096);
    t_ok(&mut t, "post base name ref rejected", r12 == QPACK_ERR);

    let r13: i32 = dec_hex(&mut q, "0000ff25", bp, 4096);
    t_ok(&mut t, "out of range static index rejected", r13 == QPACK_ERR);

    let r14: i32 = dec_hex(&mut q, "00", bp, 4096);
    t_ok(&mut t, "truncated prefix rejected", r14 == QPACK_ERR);

    var none: [u8; 4] = [0];
    var np0: ptr<u8> = null;
    unsafe { np0 = &mut none[0] as ptr<u8>; }
    t_ok(&mut t, "null block rejected", qpk_decode(&mut q, np0, 0) == QPACK_ERR);

    var src: HpOut = hp_out_new();
    hp_out_add(&mut src, ":method", 7, "GET", 3);
    hp_out_add(&mut src, ":scheme", 7, "https", 5);
    hp_out_add(&mut src, ":path", 5, "/index.html", 11);
    hp_out_add(&mut src, ":authority", 10, "example.com", 11);
    hp_out_add(&mut src, ":status", 7, "200", 3);
    hp_out_add(&mut src, "content-type", 12, "application/json", 16);
    hp_out_add(&mut src, "x-rsharp-enc", 12, "round trip", 10);
    hp_out_add(&mut src, "x-rsharp-dup", 12, "round trip", 10);

    var enc: HxBuf = hxbuf_new(1024);
    let erc: i32 = qpk_block(&mut src, &mut enc);
    t_ok(&mut t, "encode builds a block", erc == QPACK_OK && enc.len > 2);
    t_ok(&mut t, "encode writes zero prefix", (rt_byte(enc.p, 0) as i64) == 0 && (rt_byte(enc.p, 1) as i64) == 0);

    let drc: i32 = qpk_decode(&mut q, enc.p, enc.len);
    t_ok(&mut t, "round trip decodes", drc == QPACK_OK && qpack_count(&mut q) == 8);
    t_ok(&mut t, "round trip method", hdr_is(&mut q, 0, ":method", "GET"));
    t_ok(&mut t, "round trip scheme", hdr_is(&mut q, 1, ":scheme", "https"));
    t_ok(&mut t, "round trip path", hdr_is(&mut q, 2, ":path", "/index.html"));
    t_ok(&mut t, "round trip authority", hdr_is(&mut q, 3, ":authority", "example.com"));
    t_ok(&mut t, "round trip status", hdr_is(&mut q, 4, ":status", "200"));
    t_ok(&mut t, "round trip content type", hdr_is(&mut q, 5, "content-type", "application/json"));
    t_ok(&mut t, "round trip literal name", hdr_is(&mut q, 6, "x-rsharp-enc", "round trip"));
    t_ok(&mut t, "round trip duplicate", hdr_is(&mut q, 7, "x-rsharp-dup", "round trip"));

    t_ok(&mut t, "find by name", qpack_find(&mut q, "x-rsharp-enc", 12) == 6);
    t_ok(&mut t, "find missing name", qpack_find(&mut q, "x-absent", 8) == -1);
    t_ok(&mut t, "header index out of range", qpack_header_is(&mut q, 99, ":method", "GET") == 0);

    var single: HpOut = hp_out_new();
    hp_out_add(&mut single, ":method", 7, "POST", 4);
    var enc2: HxBuf = hxbuf_new(64);
    qpk_block(&mut single, &mut enc2);
    t_ok(&mut t, "single header compresses to 3 bytes", enc2.len == 3);
    t_ok(&mut t, "single header uses static index", (rt_byte(enc2.p, 2) as i64) == 0xd4);
    let s2: i32 = qpk_decode(&mut q, enc2.p, enc2.len);
    t_ok(&mut t, "single header round trip", s2 == QPACK_OK && hdr_is(&mut q, 0, ":method", "POST"));

    var refs: HpOut = hp_out_new();
    hp_out_add(&mut refs, "server", 6, "rsharp-h3", 9);
    var enc3: HxBuf = hxbuf_new(64);
    qpk_block(&mut refs, &mut enc3);
    t_ok(&mut t, "name ref path used", enc3.len == 14);
    let s3: i32 = qpk_decode(&mut q, enc3.p, enc3.len);
    t_ok(&mut t, "name ref round trip", s3 == QPACK_OK && hdr_is(&mut q, 0, "server", "rsharp-h3"));

    hp_out_free(&mut src);
    hp_out_free(&mut single);
    hp_out_free(&mut refs);
    hxbuf_free(&mut enc);
    hxbuf_free(&mut enc2);
    hxbuf_free(&mut enc3);
    qpack_free(&mut q);

    printf("qpack_passed=%lld of %lld\n", t.pass, t.total);
    if (t.pass == t.total) {
        return 0;
    }
    return 1;
}
