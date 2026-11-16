include "rt.rsx";
include "transport_win.rsx";
include "quic_tls.rsx";
include "quic_conn.rsx";

const QC_OK: i32 = 0;
const QC_ERR: i32 = -1;
const QC_UNTRUSTED: i32 = -2;

const QC_INI: i64 = 0;
const QC_HND: i64 = 1;
const QC_APP: i64 = 2;

const QC_DCID_LEN: i64 = 8;
const QC_MIN_INITIAL: i64 = 1200;
const QC_MAX_DGRAM: i64 = 2048;
const QC_DEADLINE: i64 = 6;
const QC_MAX_STR: i64 = 32;

struct QcStr {
    id: i64,
    n: i64,
    b: HxBuf,
    fin: i32,
    used: i32
}

struct Qc {
    sock: u64,
    net: i32,
    closed: i32,
    err: i32,
    host: ptr<u8>,

    scid: [u8; 20],
    scid_len: i64,
    dcid: [u8; 20],
    dcid_len: i64,
    odcid: [u8; 20],
    odcid_len: i64,
    peer: [u8; 20],
    peer_len: i64,

    ckk: [u8; 48],
    cvv: [u8; 36],
    chh: [u8; 48],
    skk: [u8; 48],
    svv: [u8; 36],
    shh: [u8; 48],

    spn: [i64; 3],
    rpn: [i64; 3],
    rlo: [i64; 3],
    rhi: [i64; 3],
    rack: [i32; 3],
    have: [i32; 3],

    t: Tls13,
    ini: QcBuf,
    hnd: QcBuf,
    app: QcBuf,

    sh_ready: i32,
    flight_sent: i32,
    hs_done: i32,
    alpn_len: i64,
    verified: i32,
    strs: [QcStr; 32]
}

fn qc_init(q: &mut Qc, host: ptr<u8>, port: u16, to_ms: i32) -> i32 {
    q.sock = 0;
    q.net = 0;
    q.closed = 0;
    q.err = 0;
    q.host = host;
    q.sh_ready = 0;
    q.flight_sent = 0;
    q.hs_done = 0;
    q.alpn_len = 0;
    q.verified = 0;
    q.scid_len = QC_DCID_LEN;
    q.odcid_len = QC_DCID_LEN;
    q.dcid_len = QC_DCID_LEN;
    q.peer_len = 0;

    var i: i64 = 0;
    while (i < 3) {
        q.spn[i] = 0;
        q.rpn[i] = -1;
        q.rlo[i] = -1;
        q.rhi[i] = -1;
        q.rack[i] = 0;
        q.have[i] = 0;
        i += 1;
    }

    var sp: ptr<u8> = null;
    var op: ptr<u8> = null;
    var dp: ptr<u8> = null;
    unsafe {
        sp = &mut q.scid[0] as ptr<u8>;
        op = &mut q.odcid[0] as ptr<u8>;
        dp = &mut q.dcid[0] as ptr<u8>;
    }
    if (hx_random(sp, QC_DCID_LEN) != 0) {
        return QC_ERR;
    }
    if (hx_random(op, QC_DCID_LEN) != 0) {
        return QC_ERR;
    }
    rt_copy(dp, op, QC_DCID_LEN);

    var ik: [u8; 32] = [0];
    var cs: [u8; 32] = [0];
    var ss: [u8; 32] = [0];
    var ikp: ptr<u8> = null;
    var csp: ptr<u8> = null;
    var ssp: ptr<u8> = null;
    unsafe {
        ikp = &mut ik[0] as ptr<u8>;
        csp = &mut cs[0] as ptr<u8>;
        ssp = &mut ss[0] as ptr<u8>;
    }
    if (quic_initial_derive(op, QC_DCID_LEN, ikp, csp, ssp) != 0) {
        return QC_ERR;
    }

    var ck: ptr<u8> = null;
    var cv: ptr<u8> = null;
    var ch: ptr<u8> = null;
    var sk: ptr<u8> = null;
    var sv: ptr<u8> = null;
    var sh: ptr<u8> = null;
    unsafe {
        ck = &mut q.ckk[0] as ptr<u8>;
        cv = &mut q.cvv[0] as ptr<u8>;
        ch = &mut q.chh[0] as ptr<u8>;
        sk = &mut q.skk[0] as ptr<u8>;
        sv = &mut q.svv[0] as ptr<u8>;
        sh = &mut q.shh[0] as ptr<u8>;
    }
    if (quic_key_derive(csp, 32, ck, cv, ch) != 0) {
        return QC_ERR;
    }
    if (quic_key_derive(ssp, 32, sk, sv, sh) != 0) {
        return QC_ERR;
    }
    q.have[QC_INI] = 1;

    if (qcb_init(&mut q.ini, 8192) != QP_OK) {
        return QC_ERR;
    }
    if (qcb_init(&mut q.hnd, 16384) != QP_OK) {
        return QC_ERR;
    }
    if (qcb_init(&mut q.app, 131072) != QP_OK) {
        return QC_ERR;
    }

    q.t = zero(Tls13);
    q.t.phase = 0;
    q.t.tr = hxbuf_new(8192);
    q.t.hand = hxbuf_new(16384);
    q.t.inb = hxbuf_new(4096);
    q.t.certs = hxbuf_new(8192);
    if (q.t.tr.p == null || q.t.hand.p == null || q.t.inb.p == null || q.t.certs.p == null) {
        return QC_ERR;
    }

    if (hx_net_init() != 0) {
        return QC_ERR;
    }
    q.net = 1;
    q.sock = hx_udp_open(host, port, to_ms);
    if (q.sock == 0) {
        hx_net_shutdown();
        q.net = 0;
        return QC_ERR;
    }
    return QC_OK;
}

fn qc_free(q: &mut Qc) {
    if (q.sock != 0) {
        hx_udp_close(q.sock);
        q.sock = 0;
    }
    if (q.net == 1) {
        hx_net_shutdown();
        q.net = 0;
    }
    qcb_free(&mut q.ini);
    qcb_free(&mut q.hnd);
    qcb_free(&mut q.app);
    var si: i64 = 0;
    while (si < QC_MAX_STR) {
        if (q.strs[si].used == 1) {
            hxbuf_free(&mut q.strs[si].b);
            q.strs[si].used = 0;
            q.strs[si].n = 0;
        }
        si += 1;
    }
    hxbuf_free(&mut q.t.tr);
    hxbuf_free(&mut q.t.hand);
    hxbuf_free(&mut q.t.inb);
    hxbuf_free(&mut q.t.certs);
    q.closed = 1;
}

fn qc_send_long(q: &mut Qc, kind: i64, ty: i32, fr: ptr<u8>, flen: i64, pad_to: i64) -> i32 {
    if (flen < 0 || flen > 1300) {
        return QC_ERR;
    }
    var pn_len: i64 = 2;
    var body: [u8; 1400] = [0];
    var bp: ptr<u8> = null;
    unsafe { bp = &mut body[0] as ptr<u8>; }
    rt_copy(bp, fr, flen);
    var plen: i64 = flen;
    if (plen < 4) {
        plen = 4;
    }

    var dcp: ptr<u8> = null;
    var scp: ptr<u8> = null;
    unsafe {
        dcp = &mut q.dcid[0] as ptr<u8>;
        scp = &mut q.scid[0] as ptr<u8>;
    }

    var hdr: HxBuf = hxbuf_new(128);
    if (hdr.p == null) {
        return QC_ERR;
    }

    if (pad_to > 0) {
        var probe: HxBuf = hxbuf_new(128);
        if (probe.p == null) {
            hxbuf_free(&mut hdr);
            return QC_ERR;
        }
        let prc: i32 = qp_build_long(&mut probe, ty, dcp, q.dcid_len, scp, q.scid_len, null, 0, q.spn[kind], pn_len, plen);
        let head: i64 = probe.len;
        hxbuf_free(&mut probe);
        if (prc != QP_OK) {
            hxbuf_free(&mut hdr);
            return QC_ERR;
        }
        let want: i64 = pad_to - head - 16;
        if (want > plen) {
            if (want > 1300) {
                hxbuf_free(&mut hdr);
                return QC_ERR;
            }
            var k: i64 = plen;
            while (k < want) {
                rt_setbyte(bp, k, 0);
                k += 1;
            }
            plen = want;
        }
    }

    if (qp_build_long(&mut hdr, ty, dcp, q.dcid_len, scp, q.scid_len, null, 0, q.spn[kind], pn_len, plen) != QP_OK) {
        hxbuf_free(&mut hdr);
        return QC_ERR;
    }

    var out: [u8; 1500] = [0];
    var op: ptr<u8> = null;
    unsafe { op = &mut out[0] as ptr<u8>; }
    var kp: ptr<u8> = null;
    var vp: ptr<u8> = null;
    var hp: ptr<u8> = null;
    let ki: i64 = kind * 16;
    let vi: i64 = kind * 12;
    unsafe {
        kp = &mut q.ckk[ki] as ptr<u8>;
        vp = &mut q.cvv[vi] as ptr<u8>;
        hp = &mut q.chh[ki] as ptr<u8>;
    }
    let sealed: i64 = quic_seal(kp, vp, hp, hdr.p, hdr.len, pn_len, q.spn[kind], bp, plen, op);
    hxbuf_free(&mut hdr);
    if (sealed <= 0) {
        return QC_ERR;
    }
    q.spn[kind] += 1;
    let sent: i64 = hx_udp_send(q.sock, op, sealed);
    if (sent != sealed) {
        return QC_ERR;
    }
    return QC_OK;
}

fn qc_send_short(q: &mut Qc, fr: ptr<u8>, flen: i64) -> i32 {
    if (flen < 0 || flen > 1100) {
        return QC_ERR;
    }
    var pn_len: i64 = 1;
    var plen: i64 = flen;
    if (plen < 4) {
        plen = 4;
    }
    var body: [u8; 1400] = [0];
    var bp: ptr<u8> = null;
    unsafe { bp = &mut body[0] as ptr<u8>; }
    rt_copy(bp, fr, flen);

    var hdr: HxBuf = hxbuf_new(64);
    if (hdr.p == null) {
        return QC_ERR;
    }
    var dcp: ptr<u8> = null;
    unsafe { dcp = &mut q.dcid[0] as ptr<u8>; }
    if (qp_build_short(&mut hdr, dcp, q.dcid_len, q.spn[QC_APP], pn_len, plen) != QP_OK) {
        hxbuf_free(&mut hdr);
        return QC_ERR;
    }

    var out: [u8; 1500] = [0];
    var op: ptr<u8> = null;
    unsafe { op = &mut out[0] as ptr<u8>; }
    var kp: ptr<u8> = null;
    var vp: ptr<u8> = null;
    var hp: ptr<u8> = null;
    let ki: i64 = QC_APP * 16;
    let vi: i64 = QC_APP * 12;
    unsafe {
        kp = &mut q.ckk[ki] as ptr<u8>;
        vp = &mut q.cvv[vi] as ptr<u8>;
        hp = &mut q.chh[ki] as ptr<u8>;
    }
    let sealed: i64 = quic_seal(kp, vp, hp, hdr.p, hdr.len, pn_len, q.spn[QC_APP], bp, plen, op);
    hxbuf_free(&mut hdr);
    if (sealed <= 0) {
        return QC_ERR;
    }
    q.spn[QC_APP] += 1;
    let sent: i64 = hx_udp_send(q.sock, op, sealed);
    if (sent != sealed) {
        return QC_ERR;
    }
    return QC_OK;
}

fn qc_consume(q: &mut Qc, p: ptr<u8>, qq: &Qp, kind: i64, out: ptr<u8>, cap: i64) -> i64 {
    var scratch: [u8; 2048] = [0];
    var sp: ptr<u8> = null;
    unsafe { sp = &mut scratch[0] as ptr<u8>; }
    if (qq.pkt_len > 2048) {
        return -1;
    }
    rt_copy(sp, p, qq.pkt_len);

    var loc: Qp = zero(Qp);
    qp_copy(&mut loc, qq);

    let ki: i64 = kind * 16;
    let vi: i64 = kind * 12;
    var hp: ptr<u8> = null;
    unsafe { hp = &mut q.shh[ki] as ptr<u8>; }
    if (qp_classify(sp, &mut loc, hp) != QP_OK) {
        return -1;
    }
    let trunc: i64 = qp_unprotect(sp, &loc, hp);
    if (trunc < 0) {
        return -1;
    }
    if (loc.pn_len < 1 || loc.pn_len > 4) {
        return -1;
    }
    let pn: i64 = quic_pn_decode(trunc, loc.pn_len, q.rpn[kind]);
    if (pn < 0) {
        return -1;
    }

    var kp: ptr<u8> = null;
    var vp: ptr<u8> = null;
    unsafe {
        kp = &mut q.skk[ki] as ptr<u8>;
        vp = &mut q.svv[vi] as ptr<u8>;
    }
    let n: i64 = qp_aead_open(kp, vp, sp, loc.pkt_len, &loc, pn, out, cap);
    if (n < 0) {
        return -1;
    }

    if (q.rpn[kind] < pn) {
        q.rpn[kind] = pn;
    }
    if (q.rlo[kind] < 0 || pn < q.rlo[kind]) {
        q.rlo[kind] = pn;
    }
    if (pn > q.rhi[kind]) {
        q.rhi[kind] = pn;
    }
    q.rack[kind] = 1;
    return n;
}

fn qc_frames(q: &mut Qc, kind: i64, p: ptr<u8>, n: i64) -> i32 {
    var r: QF = zero(QF);
    qf_init(&mut r, p, n);
    var running: i32 = 1;
    while (running == 1) {
        let rc: i32 = qf_next(&mut r);
        if (rc == QF_END) {
            running = 0;
        } else if (rc != QF_OK) {
            return QC_ERR;
        } else if (r.ty == QF_CRYPTO) {
            var dp: ptr<u8> = null;
            unsafe { dp = p + r.data; }
            if (kind == QC_INI) {
                if (qcb_add(&mut q.ini, r.a, dp, r.dlen) != QP_OK) {
                    return QC_ERR;
                }
            } else if (kind == QC_HND) {
                if (qcb_add(&mut q.hnd, r.a, dp, r.dlen) != QP_OK) {
                    return QC_ERR;
                }
            } else {
                if (qcb_add(&mut q.app, r.a, dp, r.dlen) != QP_OK) {
                    return QC_ERR;
                }
            }
        } else if (r.ty >= QF_STREAM_BASE && r.ty <= QF_STREAM_END) {
            var sp: ptr<u8> = null;
            unsafe { sp = p + r.data; }
            if (qc_str_put(q, r.a, r.b, sp, r.dlen, r.fin) != QC_OK) {
                return QC_ERR;
            }
        } else if (r.ty == QF_HANDSHAKE_DONE) {
            q.hs_done = 1;
        } else if (r.ty == QF_CONNECTION_CLOSE) {
            q.err = 1;
            return QC_ERR;
        } else if (r.ty == QF_CONNECTION_CLOSE_APP) {
            q.err = 1;
            return QC_ERR;
        }
    }
    return QC_OK;
}

fn qc_peer(q: &mut Qc, p: ptr<u8>, qq: &Qp) {
    if (q.peer_len != 0) {
        return;
    }
    if (qq.scid_len <= 0 || qq.scid_len > 20) {
        return;
    }
    var i: i64 = 0;
    while (i < qq.scid_len) {
        q.peer[i] = rt_byte(p, qq.scid_off + i);
        q.dcid[i] = q.peer[i];
        i += 1;
    }
    q.peer_len = qq.scid_len;
    q.dcid_len = qq.scid_len;
}

fn qc_packet(q: &mut Qc, p: ptr<u8>, rem: i64) -> i64 {
    var qq: Qp = zero(Qp);
    var out: [u8; 2048] = [0];
    var op: ptr<u8> = null;
    unsafe { op = &mut out[0] as ptr<u8>; }

    if (q.have[QC_INI] == 1) {
        if (qp_scan(p, rem, q.dcid_len, QUIC_TYPE_INITIAL, &mut qq) == QP_OK) {
            let n: i64 = qc_consume(q, p, &qq, QC_INI, op, 2048);
            if (n >= 0) {
                qc_peer(q, p, &qq);
                if (qc_frames(q, QC_INI, op, n) != QC_OK) {
                    return -1;
                }
                return qq.pkt_len;
            }
        }
    }
    if (q.have[QC_HND] == 1) {
        if (qp_scan(p, rem, q.dcid_len, QUIC_TYPE_HANDSHAKE, &mut qq) == QP_OK) {
            let n: i64 = qc_consume(q, p, &qq, QC_HND, op, 2048);
            if (n >= 0) {
                if (qc_frames(q, QC_HND, op, n) != QC_OK) {
                    return -1;
                }
                return qq.pkt_len;
            }
        }
    }
    if (q.have[QC_APP] == 1) {
        if (qp_scan(p, rem, q.dcid_len, -1, &mut qq) == QP_OK) {
            if (qq.long == 0) {
                let n: i64 = qc_consume(q, p, &qq, QC_APP, op, 2048);
                if (n >= 0) {
                    if (qc_frames(q, QC_APP, op, n) != QC_OK) {
                        return -1;
                    }
                    return qq.pkt_len;
                }
            }
        }
    }
    return -1;
}

fn qc_datagram(q: &mut Qc, p: ptr<u8>, n: i64) -> i32 {
    var off: i64 = 0;
    while (off < n) {
        var cur: ptr<u8> = null;
        unsafe { cur = p + off; }
        let adv: i64 = qc_packet(q, cur, n - off);
        if (q.sh_ready == 0 && q.ini.n >= 4) {
            if (qc_do_sh(q) != QC_OK) {
                return QC_ERR;
            }
        }
        if (adv <= 0) {
            break;
        }
        off += adv;
    }
    return QC_OK;
}

fn qc_do_sh(q: &mut Qc) -> i32 {
    if (q.ini.n < 4) {
        return QC_OK;
    }
    var shared: [u8; 32] = [0];
    var sp: ptr<u8> = null;
    unsafe { sp = &mut shared[0] as ptr<u8>; }
    if (qt_server_hello(&mut q.t, q.ini.b.p, q.ini.n, sp) != QT_OK) {
        q.err = 1;
        return QC_ERR;
    }
    if (tls13_handshake_keys(&mut q.t, sp) != TLS_OK) {
        q.err = 1;
        return QC_ERR;
    }

    var kp: ptr<u8> = null;
    var vp: ptr<u8> = null;
    var hp: ptr<u8> = null;
    var ts: ptr<u8> = null;
    unsafe { ts = &mut q.t.c_hs_ts[0] as ptr<u8>; }
    unsafe {
        kp = &mut q.ckk[QC_HND * 16] as ptr<u8>;
        vp = &mut q.cvv[QC_HND * 12] as ptr<u8>;
        hp = &mut q.chh[QC_HND * 16] as ptr<u8>;
    }
    if (quic_key_derive(ts, 32, kp, vp, hp) != 0) {
        q.err = 1;
        return QC_ERR;
    }
    unsafe { ts = &mut q.t.s_hs_ts[0] as ptr<u8>; }
    unsafe {
        kp = &mut q.skk[QC_HND * 16] as ptr<u8>;
        vp = &mut q.svv[QC_HND * 12] as ptr<u8>;
        hp = &mut q.shh[QC_HND * 16] as ptr<u8>;
    }
    if (quic_key_derive(ts, 32, kp, vp, hp) != 0) {
        q.err = 1;
        return QC_ERR;
    }
    q.have[QC_HND] = 1;
    q.sh_ready = 1;
    return QC_OK;
}

fn qc_do_flight(q: &mut Qc, fl: i64) -> i32 {
    var tp: QtTp = zero(QtTp);
    if (qt_ee_tp(q.hnd.b.p, q.hnd.n, &mut tp) != QT_OK) {
        q.err = 1;
        return QC_ERR;
    }
    if (tp.odcid_len <= 0 || tp.odcid_len != q.odcid_len) {
        q.err = 1;
        return QC_ERR;
    }
    var i: i64 = 0;
    while (i < tp.odcid_len) {
        if (rt_byte(tp.base, tp.odcid_off + i) != q.odcid[i]) {
            q.err = 1;
            return QC_ERR;
        }
        i += 1;
    }
    if (tp.scid_len <= 0 || tp.scid_len != q.peer_len) {
        q.err = 1;
        return QC_ERR;
    }
    i = 0;
    while (i < tp.scid_len) {
        if (rt_byte(tp.base, tp.scid_off + i) != q.peer[i]) {
            q.err = 1;
            return QC_ERR;
        }
        i += 1;
    }

    q.t.hand.len = 0;
    if (hxbuf_put(&mut q.t.hand, q.hnd.b.p, fl) != 0) {
        q.err = 1;
        return QC_ERR;
    }
    if (tls13_read_encrypted(&mut q.t, q.host) != 1) {
        q.err = 1;
        return QC_ERR;
    }
    if (tls13_app_keys(&mut q.t) != TLS_OK) {
        q.err = 1;
        return QC_ERR;
    }
    q.alpn_len = q.t.alpn_len;

    var kp: ptr<u8> = null;
    var vp: ptr<u8> = null;
    var hp: ptr<u8> = null;
    var ts: ptr<u8> = null;
    unsafe { ts = &mut q.t.c_ap_ts[0] as ptr<u8>; }
    unsafe {
        kp = &mut q.ckk[QC_APP * 16] as ptr<u8>;
        vp = &mut q.cvv[QC_APP * 12] as ptr<u8>;
        hp = &mut q.chh[QC_APP * 16] as ptr<u8>;
    }
    if (quic_key_derive(ts, 32, kp, vp, hp) != 0) {
        q.err = 1;
        return QC_ERR;
    }
    unsafe { ts = &mut q.t.s_ap_ts[0] as ptr<u8>; }
    unsafe {
        kp = &mut q.skk[QC_APP * 16] as ptr<u8>;
        vp = &mut q.svv[QC_APP * 12] as ptr<u8>;
        hp = &mut q.shh[QC_APP * 16] as ptr<u8>;
    }
    if (quic_key_derive(ts, 32, kp, vp, hp) != 0) {
        q.err = 1;
        return QC_ERR;
    }
    q.have[QC_APP] = 1;

    var fin: HxBuf = hxbuf_new(64);
    if (fin.p == null) {
        q.err = 1;
        return QC_ERR;
    }
    if (qt_finished(&mut q.t, &mut fin) != QT_OK) {
        hxbuf_free(&mut fin);
        q.err = 1;
        return QC_ERR;
    }

    var w: QW = zero(QW);
    if (qw_init(&mut w, 256) != QF_OK) {
        hxbuf_free(&mut fin);
        q.err = 1;
        return QC_ERR;
    }
    if (q.rack[QC_HND] == 1) {
        qw_ack(&mut w, q.rhi[QC_HND], 0, q.rhi[QC_HND] - q.rlo[QC_HND]);
        q.rack[QC_HND] = 0;
    }
    qw_crypto(&mut w, 0, fin.p, fin.len);
    hxbuf_free(&mut fin);

    let rc: i32 = qc_send_long(q, QC_HND, QUIC_TYPE_HANDSHAKE, w.b.p, w.b.len, 0);
    qw_free(&mut w);
    if (rc != QC_OK) {
        q.err = 1;
        return QC_ERR;
    }
    q.flight_sent = 1;
    q.t.phase = 2;
    return QC_OK;
}

fn qc_step(q: &mut Qc) -> i32 {
    if (q.sh_ready == 0 && q.ini.n >= 4) {
        if (qc_do_sh(q) != QC_OK) {
            return QC_ERR;
        }
    }
    if (q.sh_ready == 1 && q.flight_sent == 0) {
        let fl: i64 = qt_flight_len(q.hnd.b.p, q.hnd.n);
        if (fl > 0) {
            if (qc_do_flight(q, fl) != QC_OK) {
                return QC_ERR;
            }
        }
    }
    return QC_OK;
}

fn qc_open(q: &mut Qc, host: ptr<u8>, port: u16, to_ms: i32) -> i32 {
    if (qc_init(q, host, port, to_ms) != QC_OK) {
        return QC_ERR;
    }

    var ch: HxBuf = hxbuf_new(1024);
    if (ch.p == null) {
        qc_free(q);
        return QC_ERR;
    }
    var sp: ptr<u8> = null;
    unsafe { sp = &mut q.scid[0] as ptr<u8>; }
    if (qt_client_hello(&mut q.t, host, sp, q.scid_len, &mut ch) != QT_OK) {
        hxbuf_free(&mut ch);
        qc_free(q);
        return QC_ERR;
    }
    if (hxbuf_put(&mut q.t.tr, ch.p, ch.len) != 0) {
        hxbuf_free(&mut ch);
        qc_free(q);
        return QC_ERR;
    }

    var w: QW = zero(QW);
    if (qw_init(&mut w, 1200) != QF_OK) {
        hxbuf_free(&mut ch);
        qc_free(q);
        return QC_ERR;
    }
    qw_crypto(&mut w, 0, ch.p, ch.len);
    hxbuf_free(&mut ch);

    let rc0: i32 = qc_send_long(q, QC_INI, QUIC_TYPE_INITIAL, w.b.p, w.b.len, QC_MIN_INITIAL);
    qw_free(&mut w);
    if (rc0 != QC_OK) {
        qc_free(q);
        return QC_ERR;
    }

    var rxb: [u8; 2048] = [0];
    var rp: ptr<u8> = null;
    unsafe { rp = &mut rxb[0] as ptr<u8>; }
    let deadline: i64 = rt_time() + QC_DEADLINE;

    var running: i32 = 1;
    while (running == 1) {
        let n: i64 = hx_udp_recv(q.sock, rp, QC_MAX_DGRAM);
        if (n > 0) {
            qc_datagram(q, rp, n);
            if (qc_step(q) != QC_OK) {
                qc_free(q);
                return QC_ERR;
            }
            if (q.err != 0) {
                qc_free(q);
                return QC_ERR;
            }
        }
        if (q.hs_done == 1) {
            running = 0;
        } else if (rt_time() > deadline) {
            running = 0;
        }
    }

    if (q.hs_done != 1) {
        qc_free(q);
        return QC_ERR;
    }
    return QC_OK;
}

fn qc_trust_anchor(q: &mut Qc, host: ptr<u8>, anchor: ptr<u8>, alen: i64) -> i32 {
    if (q.closed == 1 || anchor == null || alen <= 0) {
        return QC_ERR;
    }
    if (x509_chain_verify(&mut q.t.chain, anchor, alen, host, rt_len(host), rt_time()) != 1) {
        return QC_UNTRUSTED;
    }
    q.verified = 1;
    return QC_OK;
}

fn qc_alpn_len(q: &Qc) -> i64 {
    return q.alpn_len;
}

fn qc_alpn_is(q: &Qc, want: ptr<u8>) -> i32 {
    if (q.alpn_len <= 0) {
        return 0;
    }
    let n: i64 = rt_len(want);
    if (n != q.alpn_len) {
        return 0;
    }
    var i: i64 = 0;
    while (i < n) {
        if (q.t.alpn[i] != rt_byte(want, i)) {
            return 0;
        }
        i += 1;
    }
    return 1;
}

fn qc_ping(q: &mut Qc) -> i32 {
    var w: QW = zero(QW);
    if (qw_init(&mut w, 64) != QF_OK) {
        return QC_ERR;
    }
    qw_ping(&mut w);
    let rc: i32 = qc_send_short(q, w.b.p, w.b.len);
    qw_free(&mut w);
    return rc;
}

fn qc_str_find(q: &mut Qc, id: i64) -> i64 {
    var i: i64 = 0;
    while (i < QC_MAX_STR) {
        if (q.strs[i].used == 1 && q.strs[i].id == id) {
            return i;
        }
        i += 1;
    }
    return -1;
}

fn qc_str_slot(q: &mut Qc, id: i64) -> i64 {
    let f: i64 = qc_str_find(q, id);
    if (f >= 0) {
        return f;
    }
    var i: i64 = 0;
    while (i < QC_MAX_STR) {
        if (q.strs[i].used == 0) {
            q.strs[i].used = 1;
            q.strs[i].id = id;
            q.strs[i].n = 0;
            q.strs[i].fin = 0;
            q.strs[i].b = hxbuf_new(4096);
            if (q.strs[i].b.p == null) {
                q.strs[i].used = 0;
                return -1;
            }
            return i;
        }
        i += 1;
    }
    return -1;
}

fn qc_str_put(q: &mut Qc, id: i64, off: i64, p: ptr<u8>, n: i64, fin: i32) -> i32 {
    let s: i64 = qc_str_slot(q, id);
    if (s < 0) {
        return QC_ERR;
    }
    if (fin == 1) {
        q.strs[s].fin = 1;
    }
    if (n <= 0) {
        return QC_OK;
    }
    if (off > q.strs[s].n) {
        return QC_OK;
    }
    if (off + n <= q.strs[s].n) {
        return QC_OK;
    }
    var src: ptr<u8> = p;
    var take: i64 = n;
    if (off < q.strs[s].n) {
        let skip: i64 = q.strs[s].n - off;
        unsafe { src = p + skip; }
        take -= skip;
    }
    if (hxbuf_put(&mut q.strs[s].b, src, take) != 0) {
        return QC_ERR;
    }
    q.strs[s].n += take;
    return QC_OK;
}

fn qc_str_n(q: &mut Qc, id: i64) -> i64 {
    let s: i64 = qc_str_find(q, id);
    if (s < 0) {
        return 0;
    }
    return q.strs[s].n;
}

fn qc_str_p(q: &mut Qc, id: i64) -> ptr<u8> {
    let s: i64 = qc_str_find(q, id);
    if (s < 0) {
        return null;
    }
    return q.strs[s].b.p;
}

fn qc_str_fin(q: &mut Qc, id: i64) -> i32 {
    let s: i64 = qc_str_find(q, id);
    if (s < 0) {
        return 0;
    }
    return q.strs[s].fin;
}

fn qc_str_reset(q: &mut Qc, id: i64) -> i32 {
    let s: i64 = qc_str_find(q, id);
    if (s < 0) {
        return QC_ERR;
    }
    hxbuf_free(&mut q.strs[s].b);
    q.strs[s].used = 0;
    q.strs[s].id = -1;
    q.strs[s].n = 0;
    q.strs[s].fin = 0;
    return QC_OK;
}

fn qc_ack_app(q: &mut Qc) -> i32 {
    if (q.rack[QC_APP] != 1) {
        return QC_OK;
    }
    var w: QW = zero(QW);
    if (qw_init(&mut w, 32) != QF_OK) {
        return QC_ERR;
    }
    qw_ack(&mut w, q.rhi[QC_APP], 0, q.rhi[QC_APP] - q.rlo[QC_APP]);
    q.rack[QC_APP] = 0;
    let rc: i32 = qc_send_short(q, w.b.p, w.b.len);
    qw_free(&mut w);
    return rc;
}

fn qc_send_stream(q: &mut Qc, id: i64, off: i64, p: ptr<u8>, n: i64, fin: i32) -> i32 {
    if (n < 0 || n > 1000) {
        return QC_ERR;
    }
    var w: QW = zero(QW);
    if (qw_init(&mut w, n + 64) != QF_OK) {
        return QC_ERR;
    }
    if (qw_stream(&mut w, id, off, p, n, fin) != QF_OK) {
        qw_free(&mut w);
        return QC_ERR;
    }
    let rc: i32 = qc_send_short(q, w.b.p, w.b.len);
    qw_free(&mut w);
    return rc;
}

fn qc_recv(q: &mut Qc, buf: ptr<u8>, cap: i64) -> i64 {
    let n: i64 = hx_udp_recv(q.sock, buf, cap);
    if (n <= 0) {
        return n;
    }
    if (qc_datagram(q, buf, n) != QC_OK) {
        return -1;
    }
    return n;
}
