include "../../modules/http/rt.rsx";
include "../../modules/http/transport_win.rsx";
include "../../modules/http/quic_conn.rsx";
include "quic_vec.rsx";

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

fn t_hex(dst: ptr<u8>, cap: i64, hex: ptr<u8>) -> i64 {
    return rt_parse_hex(hex, dst, cap);
}

fn phase_real(t: &mut Tally) {
    var i: i64 = 0;
    while (i < qvec_cases()) {
        var pk: [u8; 2048] = [0];
        var pp: ptr<u8> = null;
        unsafe { pp = &mut pk[0] as ptr<u8>; }
        let pn: i64 = t_hex(pp, 2048, qvec_packet(i));

        var db: [u8; 32] = [0];
        var dp: ptr<u8> = null;
        unsafe { dp = &mut db[0] as ptr<u8>; }
        let dn: i64 = t_hex(dp, 32, qvec_dcid(i));

        var ik: [u8; 32] = [0];
        var cs: [u8; 32] = [0];
        var ss: [u8; 32] = [0];
        var ikp: ptr<u8> = null;
        var csp: ptr<u8> = null;
        var ssp: ptr<u8> = null;
        unsafe { ikp = &mut ik[0] as ptr<u8>; csp = &mut cs[0] as ptr<u8>; ssp = &mut ss[0] as ptr<u8>; }
        t_ok(t, "case initial derive", quic_initial_derive(dp, dn, ikp, csp, ssp) == 0);

        var kb: [u8; 16] = [0];
        var vb: [u8; 12] = [0];
        var hb: [u8; 16] = [0];
        var kp: ptr<u8> = null;
        var vp: ptr<u8> = null;
        var hpp: ptr<u8> = null;
        unsafe { kp = &mut kb[0] as ptr<u8>; vp = &mut vb[0] as ptr<u8>; hpp = &mut hb[0] as ptr<u8>; }
        t_ok(t, "case client keys", quic_key_derive(csp, 32, kp, vp, hpp) == 0);

        var q: Qp = zero(Qp);
        let exp: i32 = qvec_ty(i);
        let rc: i32 = qp_scan(pp, pn, dn, exp, &mut q);
        t_ok(t, "real packet scans", rc == QP_OK);
        t_ok(t, "real packet consumes datagram", q.pkt_len == pn);
        t_ok(t, "real packet pn off inside", q.pn_off > 0 && q.pn_off < pn);

        t_ok(t, "classify", qp_classify(pp, &mut q, hpp) == QP_OK);
        t_ok(t, "pn len after unmask", q.pn_len == qvec_pnlen(i));
        if (i < 2) {
            t_ok(t, "type after unmask", q.ty == QUIC_TYPE_INITIAL);
        } else {
            t_ok(t, "short stays typeless", q.ty == -1 && q.long == 0);
        }

        var hb2: [u8; 512] = [0];
        var hp2: ptr<u8> = null;
        unsafe { hp2 = &mut hb2[0] as ptr<u8>; }
        let hn: i64 = t_hex(hp2, 512, qvec_header(i));
        t_ok(t, "real header pn off matches", q.pn_off == hn - q.pn_len);

        var back: [u8; 2048] = [0];
        var bp: ptr<u8> = null;
        unsafe { bp = &mut back[0] as ptr<u8>; }
        let got: i64 = quic_open(kp, vp, hpp, pp, pn, q.pn_off, q.pn_len, qvec_pn(i), bp, 2048);
        t_ok(t, "real packet opens", got > 0);

        var pb: [u8; 2048] = [0];
        var plp: ptr<u8> = null;
        unsafe { plp = &mut pb[0] as ptr<u8>; }
        let pln: i64 = t_hex(plp, 2048, qvec_payload(i));
        t_ok(t, "real payload length", got == pln);
        t_ok(t, "real payload matches", rt_bytes_eq(bp, plp, pln) == 1);
        i += 1;
    }
}

fn phase_roundtrip(t: &mut Tally) {
    var dcid: [u8; 8] = [0];
    var scid: [u8; 8] = [0];
    var dp: ptr<u8> = null;
    var sp: ptr<u8> = null;
    unsafe { dp = &mut dcid[0] as ptr<u8>; sp = &mut scid[0] as ptr<u8>; }
    t_hex(dp, 8, "8394c8f03e515708");
    t_hex(sp, 8, "aabbccddeeff0011");

    var key: [u8; 16] = [0];
    var iv: [u8; 12] = [0];
    var hpk: [u8; 16] = [0];
    var kp: ptr<u8> = null;
    var ip: ptr<u8> = null;
    var hp: ptr<u8> = null;
    unsafe { kp = &mut key[0] as ptr<u8>; ip = &mut iv[0] as ptr<u8>; hp = &mut hpk[0] as ptr<u8>; }
    t_hex(kp, 16, "1f369613dd76d5467730efcbe3b1a22d");
    t_hex(ip, 12, "fa044b2f42a3fd3b46fb255c");
    t_hex(hp, 16, "9f50449e04a0e810283a1e9933adedd2");

    var pay: [u8; 256] = [0];
    var pp: ptr<u8> = null;
    unsafe { pp = &mut pay[0] as ptr<u8>; }
    let pl: i64 = t_hex(pp, 256, "0600400102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20");

    var hdr: HxBuf = hxbuf_new(256);
    if (qp_build_long(&mut hdr, QUIC_TYPE_INITIAL, dp, 8, sp, 8, null, 0, 4660, 2, pl) != QP_OK) {
        t_ok(t, "build long", false);
        return;
    }
    t_ok(t, "build long produced header", hdr.len > 0);

    var out: [u8; 512] = [0];
    var op: ptr<u8> = null;
    unsafe { op = &mut out[0] as ptr<u8>; }
    let sealed: i64 = quic_seal(kp, ip, hp, hdr.p, hdr.len, 2, 4660, pp, pl, op);
    t_ok(t, "seal after build", sealed == hdr.len + pl + 16);

    var q: Qp = zero(Qp);
    let rc: i32 = qp_scan(op, sealed, 8, QUIC_TYPE_INITIAL, &mut q);
    t_ok(t, "scan own packet", rc == QP_OK);
    t_ok(t, "scan own is long", q.long == 1);
    t_ok(t, "scan own type initial", q.ty == QUIC_TYPE_INITIAL);
    t_ok(t, "scan own version", q.version == 1);
    t_ok(t, "scan own dcid len", q.dcid_len == 8);
    t_ok(t, "scan own scid len", q.scid_len == 8);
    t_ok(t, "scan own pn off", q.pn_off == hdr.len - 2);
    t_ok(t, "classify own", qp_classify(op, &mut q, hp) == QP_OK);
    t_ok(t, "scan own pn len", q.pn_len == 2);
    t_ok(t, "scan own ty survives unmask", q.ty == QUIC_TYPE_INITIAL);
    t_ok(t, "scan own pkt len", q.pkt_len == sealed);

    var back: [u8; 512] = [0];
    var bp: ptr<u8> = null;
    unsafe { bp = &mut back[0] as ptr<u8>; }
    let got: i64 = quic_open(kp, ip, hp, op, sealed, q.pn_off, q.pn_len, 4660, bp, 512);
    t_ok(t, "open own packet", got == pl);
    t_ok(t, "open own payload", rt_bytes_eq(bp, pp, pl) == 1);
    hxbuf_free(&mut hdr);
}

fn phase_coalesce(t: &mut Tally) {
    var dcid: [u8; 4] = [0];
    var scid: [u8; 4] = [0];
    var dp: ptr<u8> = null;
    var sp: ptr<u8> = null;
    unsafe { dp = &mut dcid[0] as ptr<u8>; sp = &mut scid[0] as ptr<u8>; }
    t_hex(dp, 4, "01020304");
    t_hex(sp, 4, "05060708");

    var key: [u8; 16] = [0];
    var iv: [u8; 12] = [0];
    var hpk: [u8; 16] = [0];
    var kp: ptr<u8> = null;
    var ip: ptr<u8> = null;
    var hp: ptr<u8> = null;
    unsafe { kp = &mut key[0] as ptr<u8>; ip = &mut iv[0] as ptr<u8>; hp = &mut hpk[0] as ptr<u8>; }
    t_hex(kp, 16, "1f369613dd76d5467730efcbe3b1a22d");
    t_hex(ip, 12, "fa044b2f42a3fd3b46fb255c");
    t_hex(hp, 16, "9f50449e04a0e810283a1e9933adedd2");

    var p1b: [u8; 64] = [0];
    var p2b: [u8; 64] = [0];
    var p3b: [u8; 64] = [0];
    var p1: ptr<u8> = null;
    var p2: ptr<u8> = null;
    var p3: ptr<u8> = null;
    unsafe { p1 = &mut p1b[0] as ptr<u8>; p2 = &mut p2b[0] as ptr<u8>; p3 = &mut p3b[0] as ptr<u8>; }
    let n1: i64 = t_hex(p1, 64, "0102030405060708090a0b0c0d0e");
    let n2: i64 = t_hex(p2, 64, "1112131415161718");
    let n3: i64 = t_hex(p3, 64, "21222324252627282930");

    var dg: [u8; 1024] = [0];
    var dgp: ptr<u8> = null;
    unsafe { dgp = &mut dg[0] as ptr<u8>; }
    var t1: [u8; 256] = [0];
    var t2: [u8; 256] = [0];
    var t3: [u8; 256] = [0];
    var q1: ptr<u8> = null;
    var q2: ptr<u8> = null;
    var q3: ptr<u8> = null;
    unsafe { q1 = &mut t1[0] as ptr<u8>; q2 = &mut t2[0] as ptr<u8>; q3 = &mut t3[0] as ptr<u8>; }

    var h1: HxBuf = hxbuf_new(256);
    qp_build_long(&mut h1, QUIC_TYPE_INITIAL, dp, 4, sp, 4, null, 0, 1, 1, n1);
    let s1: i64 = quic_seal(kp, ip, hp, h1.p, h1.len, 1, 1, p1, n1, q1);

    var h2: HxBuf = hxbuf_new(256);
    qp_build_long(&mut h2, QUIC_TYPE_HANDSHAKE, dp, 4, sp, 4, null, 0, 2, 1, n2);
    let s2: i64 = quic_seal(kp, ip, hp, h2.p, h2.len, 1, 2, p2, n2, q2);

    var h3: HxBuf = hxbuf_new(256);
    qp_build_short(&mut h3, dp, 4, 3, 1, n3);
    let s3: i64 = quic_seal(kp, ip, hp, h3.p, h3.len, 1, 3, p3, n3, q3);

    t_ok(t, "three packets sealed", s1 > 0 && s2 > 0 && s3 > 0);
    rt_copy(dgp, q1, s1);
    var o2: ptr<u8> = null;
    var o3: ptr<u8> = null;
    unsafe { o2 = dgp + s1; o3 = dgp + s1 + s2; }
    rt_copy(o2, q2, s2);
    rt_copy(o3, q3, s3);
    let total: i64 = s1 + s2 + s3;

    var q: Qp = zero(Qp);
    var off: i64 = 0;
    var seen: i64 = 0;
    while (off < total) {
        var cur: ptr<u8> = null;
        unsafe { cur = dgp + off; }
        var exp: i32 = -1;
        if (seen == 0) {
            exp = QUIC_TYPE_INITIAL;
        }
        if (seen == 1) {
            exp = QUIC_TYPE_HANDSHAKE;
        }
        let rc: i32 = qp_scan(cur, total - off, 4, exp, &mut q);
        if (rc != QP_OK) {
            t_ok(t, "coalesced scan", false);
            break;
        }
        t_ok(t, "coalesced classify", qp_classify(cur, &mut q, hp) == QP_OK);
        t_ok(t, "coalesced pn len", q.pn_len == 1);
        if (seen == 0) {
            t_ok(t, "coalesced first is initial", q.ty == QUIC_TYPE_INITIAL && q.long == 1);
            t_ok(t, "coalesced first length", q.pkt_len == s1);
        }
        if (seen == 1) {
            t_ok(t, "coalesced second is handshake", q.ty == QUIC_TYPE_HANDSHAKE && q.long == 1);
            t_ok(t, "coalesced second length", q.pkt_len == s2);
        }
        if (seen == 2) {
            t_ok(t, "coalesced third is short", q.long == 0);
            t_ok(t, "coalesced third length", q.pkt_len == s3);
        }
        off += q.pkt_len;
        seen += 1;
    }
    t_ok(t, "coalesced saw three", seen == 3);

    hxbuf_free(&mut h1);
    hxbuf_free(&mut h2);
    hxbuf_free(&mut h3);
}

fn phase_reassembly(t: &mut Tally) {
    var s: QcBuf = zero(QcBuf);
    if (qcb_init(&mut s, 128) != QP_OK) {
        t_ok(t, "qcb init", false);
        return;
    }
    var a: [u8; 16] = [0];
    var b: [u8; 16] = [0];
    var ap: ptr<u8> = null;
    var bp: ptr<u8> = null;
    unsafe { ap = &mut a[0] as ptr<u8>; bp = &mut b[0] as ptr<u8>; }
    let an: i64 = t_hex(ap, 16, "0102030405");
    let bn: i64 = t_hex(bp, 16, "060708090a0b");

    t_ok(t, "append at zero", qcb_add(&mut s, 0, ap, an) == QP_OK);
    t_ok(t, "append after", qcb_add(&mut s, an, bp, bn) == QP_OK);
    t_ok(t, "contiguous length", s.n == an + bn);
    t_ok(t, "contiguous bytes", rt_bytes_eq(s.b.p, ap, an) == 1);

    let before: i64 = s.n;
    t_ok(t, "duplicate ignored", qcb_add(&mut s, 0, ap, an) == QP_OK);
    t_ok(t, "duplicate did not grow", s.n == before);

    var c: [u8; 16] = [0];
    var cp: ptr<u8> = null;
    unsafe { cp = &mut c[0] as ptr<u8>; }
    let cn: i64 = t_hex(cp, 16, "11121314151617");
    t_ok(t, "overlap accepted", qcb_add(&mut s, 8, cp, cn) == QP_OK);
    t_ok(t, "overlap trimmed to new tail", s.n == 15);
    t_ok(t, "overlap tail byte", rt_byte(s.b.p, s.n - 1) == 0x17);

    t_ok(t, "gap rejected", qcb_add(&mut s, s.n + 4, ap, an) == QP_ERR);
    qcb_free(&mut s);
}

fn main() -> i32 {
    var t: Tally = zero(Tally);
    t.pass = 0;
    t.total = 0;

    phase_real(&mut t);
    phase_roundtrip(&mut t);
    phase_coalesce(&mut t);
    phase_reassembly(&mut t);

    printf("quicconn_passed=%lld of %lld\n", t.pass, t.total);
    if (t.pass == t.total) {
        return 0;
    }
    return 1;
}
