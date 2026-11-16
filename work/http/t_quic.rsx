include "../../modules/http/quic_crypto.rsx";
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

fn t_match(got: ptr<u8>, n: i64, hex: ptr<u8>) -> bool {
    if (got == null || n <= 0) {
        return false;
    }
    var eb: [u8; 2048] = [0];
    var ep: ptr<u8> = null;
    unsafe { ep = &mut eb[0] as ptr<u8>; }
    let en: i64 = rt_parse_hex(hex, ep, 2048);
    if (en != n) {
        return false;
    }
    return rt_bytes_eq(got, ep, n) == 1;
}

fn phase_initial(t: &mut Tally) {
    var dcid: [u8; 32] = [0];
    var dp: ptr<u8> = null;
    unsafe { dp = &mut dcid[0] as ptr<u8>; }
    let dn: i64 = rt_parse_hex(qvec_dcid_a(), dp, 32);
    if (dn != 8) {
        t_ok(t, "dcid parsed", false);
        return;
    }

    var ib: [u8; 32] = [0];
    var cb: [u8; 32] = [0];
    var sb: [u8; 32] = [0];
    var ip: ptr<u8> = null;
    var cp: ptr<u8> = null;
    var sp: ptr<u8> = null;
    unsafe { ip = &mut ib[0] as ptr<u8>; cp = &mut cb[0] as ptr<u8>; sp = &mut sb[0] as ptr<u8>; }
    let rc: i32 = quic_initial_derive(dp, dn, ip, cp, sp);
    t_ok(t, "initial derive", rc == 0);
    t_ok(t, "initial secret", t_match(ip, 32, qvec_initial_a()));
    t_ok(t, "client in secret", t_match(cp, 32, qvec_client_secret_a()));
    t_ok(t, "server in secret", t_match(sp, 32, qvec_server_secret_a()));

    var kb: [u8; 16] = [0];
    var vb: [u8; 12] = [0];
    var hb: [u8; 16] = [0];
    var kp: ptr<u8> = null;
    var vp: ptr<u8> = null;
    var hp: ptr<u8> = null;
    unsafe { kp = &mut kb[0] as ptr<u8>; vp = &mut vb[0] as ptr<u8>; hp = &mut hb[0] as ptr<u8>; }
    t_ok(t, "client key derive", quic_key_derive(cp, 32, kp, vp, hp) == 0);
    t_ok(t, "client key", t_match(kp, 16, qvec_client_key_a()));
    t_ok(t, "client iv", t_match(vp, 12, qvec_client_iv_a()));
    t_ok(t, "client hp", t_match(hp, 16, qvec_client_hp_a()));

    var k2: [u8; 16] = [0];
    var v2: [u8; 12] = [0];
    var h2: [u8; 16] = [0];
    var k2p: ptr<u8> = null;
    var v2p: ptr<u8> = null;
    var h2p: ptr<u8> = null;
    unsafe { k2p = &mut k2[0] as ptr<u8>; v2p = &mut v2[0] as ptr<u8>; h2p = &mut h2[0] as ptr<u8>; }
    t_ok(t, "server key derive", quic_key_derive(sp, 32, k2p, v2p, h2p) == 0);
    t_ok(t, "server key", t_match(k2p, 16, qvec_server_key_a()));
    t_ok(t, "server iv", t_match(v2p, 12, qvec_server_iv_a()));
    t_ok(t, "server hp", t_match(h2p, 16, qvec_server_hp_a()));

    var db: [u8; 32] = [0];
    var dbp: ptr<u8> = null;
    unsafe { dbp = &mut db[0] as ptr<u8>; }
    let dnb: i64 = rt_parse_hex(qvec_dcid_b(), dbp, 32);
    var ib2: [u8; 32] = [0];
    var cb2: [u8; 32] = [0];
    var sb2: [u8; 32] = [0];
    var ip2: ptr<u8> = null;
    var cp2: ptr<u8> = null;
    var sp2: ptr<u8> = null;
    unsafe { ip2 = &mut ib2[0] as ptr<u8>; cp2 = &mut cb2[0] as ptr<u8>; sp2 = &mut sb2[0] as ptr<u8>; }
    t_ok(t, "initial derive b", quic_initial_derive(dbp, dnb, ip2, cp2, sp2) == 0);
    t_ok(t, "initial secret b", t_match(ip2, 32, qvec_initial_b()));
}

fn phase_nonce(t: &mut Tally) {
    var ivb: [u8; 12] = [0];
    var ivp: ptr<u8> = null;
    unsafe { ivp = &mut ivb[0] as ptr<u8>; }
    if (rt_parse_hex(qvec_client_iv_a(), ivp, 12) != 12) {
        t_ok(t, "iv parsed", false);
        return;
    }
    var nb: [u8; 12] = [0];
    var np: ptr<u8> = null;
    unsafe { np = &mut nb[0] as ptr<u8>; }
    quic_nonce(ivp, 2, np);
    t_ok(t, "nonce pn 2", t_match(np, 12, "fa044b2f42a3fd3b46fb255e"));
    quic_nonce(ivp, 4660, np);
    t_ok(t, "nonce pn 4660", t_match(np, 12, "fa044b2f42a3fd3b46fb3768"));
    quic_nonce(ivp, 0, np);
    t_ok(t, "nonce pn 0", t_match(np, 12, qvec_client_iv_a()));
}

fn phase_varint(t: &mut Tally) {
    var vb: [u8; 32] = [0];
    var vp: ptr<u8> = null;
    unsafe { vp = &mut vb[0] as ptr<u8>; }
    t_ok(t, "varint 0 is 1 byte", quic_varint_len(0) == 1);
    t_ok(t, "varint 63 is 1 byte", quic_varint_len(63) == 1);
    t_ok(t, "varint 64 is 2 bytes", quic_varint_len(64) == 2);
    t_ok(t, "varint 16383 is 2 bytes", quic_varint_len(16383) == 2);
    t_ok(t, "varint 16384 is 4 bytes", quic_varint_len(16384) == 4);
    t_ok(t, "varint 2^62-1 is 8 bytes", quic_varint_len(4611686018427387903) == 8);

    t_ok(t, "encode 0", quic_varint_put(vp, 0, 0) == 1);
    t_ok(t, "decode 0", quic_varint_get(vp, 0) == 0);
    t_ok(t, "encode 63", quic_varint_put(vp, 0, 63) == 1);
    t_ok(t, "decode 63", quic_varint_get(vp, 0) == 63);
    t_ok(t, "encode 15293", quic_varint_put(vp, 0, 15293) == 2);
    t_ok(t, "decode 15293", quic_varint_get(vp, 0) == 15293);
    t_ok(t, "encode 494878333", quic_varint_put(vp, 0, 494878333) == 4);
    t_ok(t, "decode 494878333", quic_varint_get(vp, 0) == 494878333);
    t_ok(t, "encode 2^62-1", quic_varint_put(vp, 0, 4611686018427387903) == 8);
    t_ok(t, "decode 2^62-1", quic_varint_get(vp, 0) == 4611686018427387903);
    t_ok(t, "wire bytes", t_match(vp, 8, "ffffffffffffffff"));

    t_ok(t, "hdr len 1", quic_varint_hdr_len(0x25) == 1);
    t_ok(t, "hdr len 2", quic_varint_hdr_len(0x40) == 2);
    t_ok(t, "hdr len 4", quic_varint_hdr_len(0x80) == 4);
    t_ok(t, "hdr len 8", quic_varint_hdr_len(0xc0) == 8);
}

fn phase_case(t: &mut Tally, i: i64) {
    var db: [u8; 32] = [0];
    var dp: ptr<u8> = null;
    unsafe { dp = &mut db[0] as ptr<u8>; }
    let dn: i64 = rt_parse_hex(qvec_dcid(i), dp, 32);

    var ib: [u8; 32] = [0];
    var cb: [u8; 32] = [0];
    var sb: [u8; 32] = [0];
    var ip: ptr<u8> = null;
    var cp: ptr<u8> = null;
    var sp: ptr<u8> = null;
    unsafe { ip = &mut ib[0] as ptr<u8>; cp = &mut cb[0] as ptr<u8>; sp = &mut sb[0] as ptr<u8>; }
    if (quic_initial_derive(dp, dn, ip, cp, sp) != 0) {
        t_ok(t, "case secret", false);
        return;
    }

    var kb: [u8; 16] = [0];
    var vb: [u8; 12] = [0];
    var hb: [u8; 16] = [0];
    var kp: ptr<u8> = null;
    var vp: ptr<u8> = null;
    var hp: ptr<u8> = null;
    unsafe { kp = &mut kb[0] as ptr<u8>; vp = &mut vb[0] as ptr<u8>; hp = &mut hb[0] as ptr<u8>; }
    if (quic_key_derive(cp, 32, kp, vp, hp) != 0) {
        t_ok(t, "case key", false);
        return;
    }

    var hdr: [u8; 512] = [0];
    var pay: [u8; 512] = [0];
    var hdp: ptr<u8> = null;
    var pyp: ptr<u8> = null;
    unsafe { hdp = &mut hdr[0] as ptr<u8>; pyp = &mut pay[0] as ptr<u8>; }
    let hn: i64 = rt_parse_hex(qvec_header(i), hdp, 512);
    let pl: i64 = rt_parse_hex(qvec_payload(i), pyp, 512);
    let pnlen: i64 = quic_pnlen(hdp);
    let pnum: i64 = qvec_pn(i);

    let off: i64 = quic_pn_offset(hdp, hn, dn);
    t_ok(t, "pn offset", off == hn - pnlen);
    if (quic_is_long(hdp) == 1) {
        t_ok(t, "long header flag", true);
        t_ok(t, "version 1", quic_version(hdp) == 1);
    } else {
        t_ok(t, "short header in case set", true);
        t_ok(t, "short version unavailable", quic_version(hdp) == -1);
    }

    var out: [u8; 2048] = [0];
    var op: ptr<u8> = null;
    unsafe { op = &mut out[0] as ptr<u8>; }
    let got: i64 = quic_seal(kp, vp, hp, hdp, hn, pnlen, pnum, pyp, pl, op);
    t_ok(t, "seal length", got == hn + pl + 16);
    t_ok(t, "seal bytes match aioquic", t_match(op, got, qvec_packet(i)));

    var wb: [u8; 2048] = [0];
    var wp: ptr<u8> = null;
    unsafe { wp = &mut wb[0] as ptr<u8>; }
    let wn: i64 = rt_parse_hex(qvec_packet(i), wp, 2048);
    if (wn != got) {
        t_ok(t, "packet parsed", false);
        return;
    }
    let poff: i64 = quic_pn_offset(wp, wn, dn);
    t_ok(t, "protected pn offset", poff == off);

    var pb: [u8; 2048] = [0];
    var pp: ptr<u8> = null;
    unsafe { pp = &mut pb[0] as ptr<u8>; }
    let olen: i64 = quic_open(kp, vp, hp, wp, wn, poff, pnlen, pnum, pp, 2048);
    t_ok(t, "open length", olen == pl);
    t_ok(t, "open payload", t_match(pp, olen, qvec_payload(i)));
    t_ok(t, "open header restored", rt_bytes_eq(wp, hdp, hn) == 1);
    t_ok(t, "open flips first byte back", rt_byte(wp, 0) == rt_byte(hdp, 0));

    var tb: [u8; 2048] = [0];
    var tp: ptr<u8> = null;
    unsafe { tp = &mut tb[0] as ptr<u8>; }
    rt_parse_hex(qvec_packet(i), tp, 2048);
    let last: i64 = wn - 1;
    rt_setbyte(tp, last, rt_byte(tp, last) ^ 1);
    let bad: i64 = quic_open(kp, vp, hp, tp, wn, poff, pnlen, pnum, pp, 2048);
    t_ok(t, "forged tag rejected", bad == -1);
}

fn phase_short(t: &mut Tally) {
    let i: i64 = 2;
    var db: [u8; 32] = [0];
    var dp: ptr<u8> = null;
    unsafe { dp = &mut db[0] as ptr<u8>; }
    let dn: i64 = rt_parse_hex(qvec_dcid(i), dp, 32);

    var hdr: [u8; 512] = [0];
    var hdp: ptr<u8> = null;
    unsafe { hdp = &mut hdr[0] as ptr<u8>; }
    let hn: i64 = rt_parse_hex(qvec_header(i), hdp, 512);
    t_ok(t, "short header flag", quic_is_long(hdp) == 0);
    t_ok(t, "short has no type", quic_pkt_type(hdp) == -1);
    t_ok(t, "short pn len", quic_pnlen(hdp) == 1);
    t_ok(t, "short pn offset", quic_pn_offset(hdp, hn, dn) == 1 + dn);

    var wb: [u8; 2048] = [0];
    var wp: ptr<u8> = null;
    unsafe { wp = &mut wb[0] as ptr<u8>; }
    let wn: i64 = rt_parse_hex(qvec_packet(i), wp, 2048);
    t_ok(t, "short spin bit masked", rt_byte(wp, 0) != rt_byte(hdp, 0));
}

fn phase_pndecode(t: &mut Tally) {
    t_ok(t, "pn decode exact", quic_pn_decode(7, 1, 7) == 7);
    t_ok(t, "pn decode next byte", quic_pn_decode(0, 1, 255) == 256);
    t_ok(t, "pn decode back", quic_pn_decode(255, 1, 256) == 255);
    t_ok(t, "pn decode 2 byte", quic_pn_decode(4660, 2, 4660) == 4660);
    t_ok(t, "pn decode 4 byte", quic_pn_decode(2, 4, 2) == 2);
    t_ok(t, "pn decode reject 5 byte", quic_pn_decode(2, 5, 2) == -1);
}

fn main() -> i32 {
    var t: Tally = zero(Tally);
    t.pass = 0;
    t.total = 0;

    phase_initial(&mut t);
    phase_nonce(&mut t);
    phase_varint(&mut t);
    phase_pndecode(&mut t);

    var i: i64 = 0;
    while (i < qvec_cases()) {
        phase_case(&mut t, i);
        i += 1;
    }
    phase_short(&mut t);

    printf("quic_passed=%lld of %lld\n", t.pass, t.total);
    if (t.pass == t.total) {
        return 0;
    }
    return 1;
}
