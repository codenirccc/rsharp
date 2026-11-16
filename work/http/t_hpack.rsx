include "../../modules/http/rt.rsx";
include "../../modules/http/transport_win.rsx";
include "../../modules/http/hpack.rsx";
include "hpack_vec.rsx";

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

fn main() -> i32 {
    var t: Tally = zero(Tally);
    var hk: Hpack = hpack_new();
    if (hk.tree.nodes <= 0) {
        printf("tree init failed\n");
        fflush(null);
        return 1;
    }
    t_ok(&mut t, "huffman tree builds", hk.tree.nodes == 513);

    var blkb: [u8; 4096] = [0];
    var bp: ptr<u8> = null;
    unsafe { bp = &mut blkb[0] as ptr<u8>; }
    var wb: [u8; 4096] = [0];
    var wp: ptr<u8> = null;
    unsafe { wp = &mut wb[0] as ptr<u8>; }

    let cases: i64 = hvec_cases();
    var ci: i64 = 0;
    var bad: i64 = 0;
    var hdr_total: i64 = 0;
    while (ci < cases) {
        let blen: i64 = rt_parse_hex(hvec_blk(ci), bp, 4096);
        if (blen <= 0) {
            printf("case %lld: bad vector\n", ci);
            bad += 1;
            ci += 1;
            continue;
        }
        let rc: i32 = hpack_decode(&mut hk, bp, blen);
        let got: i64 = hpack_count(&mut hk);
        let first: i64 = hvec_off(ci);
        let last: i64 = hvec_off(ci + 1);
        let want: i64 = last - first;
        var good: bool = rc == HPACK_OK && got == want;
        var j: i64 = 0;
        while (good && j < want) {
            let nn: i64 = rt_parse_hex(hvec_nm(first + j), wp, 4096);
            let np: ptr<u8> = hpack_name(&mut hk, j);
            let nlen: i64 = hpack_namelen(&mut hk, j);
            let name_ok: bool = np != null && nlen == nn && rt_bytes_eq(np, wp, nn) == 1;
            if (!name_ok) {
                printf("case %lld hdr %lld: name mismatch\n", ci, j);
            }
            let vn: i64 = rt_parse_hex(hvec_vl(first + j), wp, 4096);
            let vp: ptr<u8> = hpack_value(&mut hk, j);
            let vlen: i64 = hpack_vallen(&mut hk, j);
            let val_ok: bool = vp != null && vlen == vn && rt_bytes_eq(vp, wp, vn) == 1;
            if (!val_ok) {
                printf("case %lld hdr %lld: value mismatch\n", ci, j);
            }
            good = name_ok && val_ok;
            j += 1;
        }
        if (!good) {
            printf("case %lld: FAIL rc=%d got=%lld want=%lld\n", ci, rc, got, want);
            bad += 1;
        }
        hdr_total += got;
        ci += 1;
    }
    t_ok(&mut t, "decode all blocks", bad == 0);
    t_ok(&mut t, "header count", hdr_total == hvec_hn());

    let st: i64 = hpack_find(&mut hk, ":status", 7);
    t_ok(&mut t, "pseudo header found", st >= 0);

    var hc: i64 = 0;
    var hbad: i64 = 0;
    let nh: i64 = hvec_hnuff();
    while (hc < nh) {
        let hn: i64 = rt_parse_hex(hvec_huff(hc), bp, 4096);
        var acc: HxBuf = hxbuf_new(1024);
        if (acc.p == null) {
            hbad += 1;
            hc += 1;
            continue;
        }
        let got: i64 = hp_huff(bp, hn, &mut hk.tree, &mut acc);
        let wn: i64 = rt_parse_hex(hvec_hwant(hc), wp, 4096);
        let good: bool = got == wn && acc.p != null && rt_bytes_eq(acc.p, wp, wn) == 1;
        if (!good) {
            printf("huff %lld: got=%lld want=%lld\n", hc, got, wn);
            hbad += 1;
        }
        hxbuf_free(&mut acc);
        hc += 1;
    }
    t_ok(&mut t, "huffman strings", hbad == 0);

    var enc: HxBuf = hxbuf_new(256);
    let ok1: i32 = hpack_put_kv(&mut enc, ":method", "GET");
    let ok2: i32 = hpack_put_kv(&mut enc, ":path", "/x");
    let ok3: i32 = hpack_put_kv(&mut enc, "x-custom", "v1");
    let good_enc: bool = ok1 == 0 && ok2 == 0 && ok3 == 0 && enc.len == 18;
    t_ok(&mut t, "encode indexed plus literal", good_enc);

    let back: i32 = hpack_decode(&mut hk, enc.p, enc.len);
    let n3: i64 = hpack_count(&mut hk);
    t_ok(&mut t, "encode round trip", back == 0 && n3 == 3);

    var upd: HxBuf = hxbuf_new(16);
    hpack_put_size_update(&mut upd, 0);
    let drop: i32 = hpack_decode(&mut hk, upd.p, upd.len);
    t_ok(&mut t, "size update to zero", drop == 0 && hk.dyn.max == 0 && hk.dyn.n == 0);
    hxbuf_free(&mut upd);

    hxbuf_free(&mut enc);
    hpack_free(&mut hk);

    printf("hpack_passed=%lld of %lld\n", t.pass, t.total);
    fflush(null);
    if (t.pass != t.total) {
        return 3;
    }
    return 0;
}
