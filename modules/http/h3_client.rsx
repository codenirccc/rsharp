include "rt.rsx";
include "transport_win.rsx";
include "quic_tls.rsx";
include "quic_conn.rsx";
include "quic_client.rsx";
include "qpack.rsx";

const H3_OK: i32 = 0;
const H3_ERR: i32 = -1;
const H3_UNTRUSTED: i32 = -2;

const H3_DATA: i64 = 0x00;
const H3_HEADERS: i64 = 0x01;
const H3_CANCEL_PUSH: i64 = 0x03;
const H3_SETTINGS: i64 = 0x04;
const H3_PUSH_PROMISE: i64 = 0x05;
const H3_GOAWAY: i64 = 0x07;
const H3_MAX_PUSH_ID: i64 = 0x0d;

const H3_ST_CONTROL: i64 = 0x00;
const H3_ST_QPACK_ENC: i64 = 0x02;
const H3_ST_QPACK_DEC: i64 = 0x03;

const H3_SET_QPACK_MAX_TABLE_CAPACITY: i64 = 0x01;
const H3_SET_MAX_FIELD_SECTION_SIZE: i64 = 0x06;
const H3_SET_QPACK_BLOCKED_STREAMS: i64 = 0x07;

const H3_SID_CONTROL: i64 = 0x02;
const H3_SID_QPACK_ENC: i64 = 0x06;
const H3_SID_QPACK_DEC: i64 = 0x0a;

const H3_MAX_REQ: i64 = 4;
const H3_MAX_BODY: i64 = 1048576;
const H3_CHUNK: i64 = 900;

struct H3Req {
    id: i64,
    used: i32,
    got_hdr: i32,
    fin: i32,
    roff: i64,
    body: HxBuf,
    hdr: HpOut
}

struct H3 {
    q: Qc,
    qp: Qpack,
    ctl: i64,
    enc: i64,
    dec: i64,
    coff: i64,
    eoff: i64,
    doff: i64,
    nxt: i64,
    nreq: i64,
    err: i32,
    reqs: [H3Req; 4]
}

fn h3_new() -> H3 {
    var h: H3 = zero(H3);
    h.qp = qpack_new();
    h.ctl = H3_SID_CONTROL;
    h.enc = H3_SID_QPACK_ENC;
    h.dec = H3_SID_QPACK_DEC;
    h.nxt = 0;
    h.nreq = 0;
    h.err = 0;
    var i: i64 = 0;
    while (i < H3_MAX_REQ) {
        h.reqs[i].id = -1;
        h.reqs[i].used = 0;
        h.reqs[i].got_hdr = 0;
        h.reqs[i].fin = 0;
        h.reqs[i].roff = 0;
        h.reqs[i].body = hxbuf_new(256);
        h.reqs[i].hdr = hp_out_new();
        i += 1;
    }
    return h;
}

fn h3_free(h: &mut H3) {
    var i: i64 = 0;
    while (i < H3_MAX_REQ) {
        hxbuf_free(&mut h.reqs[i].body);
        hp_out_free(&mut h.reqs[i].hdr);
        i += 1;
    }
    qpack_free(&mut h.qp);
    qc_free(&mut h.q);
}

fn h3_frame(out: &mut HxBuf, ty: i64, p: ptr<u8>, n: i64) -> i32 {
    if (hx_put_varint(out, ty) != 0) {
        return H3_ERR;
    }
    if (hx_put_varint(out, n) != 0) {
        return H3_ERR;
    }
    if (n > 0 && hxbuf_put(out, p, n) != 0) {
        return H3_ERR;
    }
    return H3_OK;
}

fn h3_send_uni(h: &mut H3, sid: i64, ty: i64, extra: &mut HxBuf) -> i32 {
    var b: HxBuf = hxbuf_new(128);
    if (b.p == null) {
        return H3_ERR;
    }
    if (hx_put_varint(&mut b, ty) != 0) {
        hxbuf_free(&mut b);
        return H3_ERR;
    }
    if (extra.len > 0) {
        if (hxbuf_put(&mut b, extra.p, extra.len) != 0) {
            hxbuf_free(&mut b);
            return H3_ERR;
        }
    }
    let rc: i32 = qc_send_stream(&mut h.q, sid, 0, b.p, b.len, 0);
    hxbuf_free(&mut b);
    return rc;
}

fn h3_setup(h: &mut H3) -> i32 {
    var st: HxBuf = hxbuf_new(64);
    if (st.p == null) {
        return H3_ERR;
    }
    hx_put_varint(&mut st, H3_SET_QPACK_MAX_TABLE_CAPACITY);
    hx_put_varint(&mut st, 0);
    hx_put_varint(&mut st, H3_SET_QPACK_BLOCKED_STREAMS);
    hx_put_varint(&mut st, 0);
    hx_put_varint(&mut st, H3_SET_MAX_FIELD_SECTION_SIZE);
    hx_put_varint(&mut st, 65536);

    var ctl: HxBuf = hxbuf_new(96);
    if (ctl.p == null) {
        hxbuf_free(&mut st);
        return H3_ERR;
    }
    if (h3_frame(&mut ctl, H3_SETTINGS, st.p, st.len) != H3_OK) {
        hxbuf_free(&mut st);
        hxbuf_free(&mut ctl);
        return H3_ERR;
    }
    hxbuf_free(&mut st);

    let r0: i32 = h3_send_uni(h, h.ctl, H3_ST_CONTROL, &mut ctl);
    hxbuf_free(&mut ctl);
    if (r0 != H3_OK) {
        return H3_ERR;
    }
    var none: HxBuf = hxbuf_new(16);
    if (h3_send_uni(h, h.enc, H3_ST_QPACK_ENC, &mut none) != H3_OK) {
        hxbuf_free(&mut none);
        return H3_ERR;
    }
    if (h3_send_uni(h, h.dec, H3_ST_QPACK_DEC, &mut none) != H3_OK) {
        hxbuf_free(&mut none);
        return H3_ERR;
    }
    hxbuf_free(&mut none);
    h.coff = 0;
    h.eoff = 0;
    h.doff = 0;
    return H3_OK;
}

fn h3_open(h: &mut H3, host: ptr<u8>, port: u16, to_ms: i32) -> i32 {
    if (qpack_ready(&mut h.qp) != 1) {
        return H3_ERR;
    }
    if (qc_open(&mut h.q, host, port, to_ms) != QC_OK) {
        return H3_ERR;
    }
    if (h3_setup(h) != H3_OK) {
        qc_free(&mut h.q);
        return H3_ERR;
    }
    return H3_OK;
}

fn h3_trust_anchor(h: &mut H3, host: ptr<u8>, anchor: ptr<u8>, alen: i64) -> i32 {
    if (anchor == null || alen <= 0) {
        return H3_ERR;
    }
    if (x509_chain_verify(&mut h.q.t.chain, anchor, alen, host, rt_len(host), rt_time()) != 1) {
        return H3_UNTRUSTED;
    }
    h.q.verified = 1;
    return H3_OK;
}

fn h3_alpn_is(h: &mut H3, want: ptr<u8>) -> i32 {
    return qc_alpn_is(&h.q, want);
}

fn h3_slot(h: &mut H3) -> i64 {
    var i: i64 = 0;
    while (i < H3_MAX_REQ) {
        if (h.reqs[i].used == 0) {
            return i;
        }
        i += 1;
    }
    return -1;
}

fn h3_hdr_add(o: &mut HpOut, name: ptr<u8>, value: ptr<u8>) -> i32 {
    return hp_out_add(o, name, rt_len(name), value, rt_len(value));
}

fn h3_requestx(h: &mut H3, method: ptr<u8>, path: ptr<u8>, host: ptr<u8>, extra: &mut HpOut, body: ptr<u8>, blen: i64) -> i64 {
    let s: i64 = h3_slot(h);
    if (s < 0 || body == null && blen > 0) {
        return -1;
    }
    if (blen < 0 || blen > H3_CHUNK) {
        return -1;
    }

    h.reqs[s].used = 1;
    h.reqs[s].got_hdr = 0;
    h.reqs[s].fin = 0;
    h.reqs[s].roff = 0;
    h.reqs[s].body.len = 0;
    hp_out_clear(&mut h.reqs[s].hdr);
    h.reqs[s].id = h.nxt * 4;
    h.nxt += 1;
    h.nreq += 1;

    var hd: HpOut = hp_out_new();
    h3_hdr_add(&mut hd, ":method", method);
    h3_hdr_add(&mut hd, ":scheme", "https");
    h3_hdr_add(&mut hd, ":path", path);
    h3_hdr_add(&mut hd, ":authority", host);
    if (blen > 0) {
        var have_ct: i32 = 0;
        if (hp_out_find(extra, "content-type", 12) >= 0) {
            have_ct = 1;
        }
        if (have_ct == 0) {
            h3_hdr_add(&mut hd, "content-type", "text/plain");
        }
    }
    if (extra.n > 0) {
        var xi: i64 = 0;
        while (xi < extra.n) {
            let xnp: ptr<u8> = hp_out_name(extra, xi);
            let xnl: i64 = hp_out_nlen(extra, xi);
            let xvp: ptr<u8> = hp_out_value(extra, xi);
            let xvl: i64 = hp_out_vlen(extra, xi);
            hp_out_add(&mut hd, xnp, xnl, xvp, xvl);
            xi += 1;
        }
    }

    var qb: HxBuf = hxbuf_new(512);
    var fr: HxBuf = hxbuf_new(640);
    if (qb.p == null || fr.p == null) {
        hxbuf_free(&mut qb);
        hxbuf_free(&mut fr);
        hp_out_free(&mut hd);
        h.reqs[s].used = 0;
        return -1;
    }
    if (qpk_block(&mut hd, &mut qb) != QPACK_OK) {
        hxbuf_free(&mut qb);
        hxbuf_free(&mut fr);
        hp_out_free(&mut hd);
        h.reqs[s].used = 0;
        return -1;
    }
    hp_out_free(&mut hd);
    if (h3_frame(&mut fr, H3_HEADERS, qb.p, qb.len) != H3_OK) {
        hxbuf_free(&mut qb);
        hxbuf_free(&mut fr);
        h.reqs[s].used = 0;
        return -1;
    }
    hxbuf_free(&mut qb);

    let sid: i64 = h.reqs[s].id;
    let fin0: i32 = 0;
    if (qc_send_stream(&mut h.q, sid, 0, fr.p, fr.len, fin0) != QC_OK) {
        hxbuf_free(&mut fr);
        h.reqs[s].used = 0;
        return -1;
    }
    var off: i64 = fr.len;
    hxbuf_free(&mut fr);

    if (blen > 0) {
        var db: HxBuf = hxbuf_new(blen + 32);
        if (db.p == null) {
            h.reqs[s].used = 0;
            return -1;
        }
        if (h3_frame(&mut db, H3_DATA, body, blen) != H3_OK) {
            hxbuf_free(&mut db);
            h.reqs[s].used = 0;
            return -1;
        }
        if (qc_send_stream(&mut h.q, sid, off, db.p, db.len, fin0) != QC_OK) {
            hxbuf_free(&mut db);
            h.reqs[s].used = 0;
            return -1;
        }
        off += db.len;
        hxbuf_free(&mut db);
    }

    if (qc_send_stream(&mut h.q, sid, off, null, 0, 1) != QC_OK) {
        h.reqs[s].used = 0;
        return -1;
    }
    return s;
}

fn h3_request(h: &mut H3, method: ptr<u8>, path: ptr<u8>, host: ptr<u8>, body: ptr<u8>, blen: i64) -> i64 {
    var none: HpOut = hp_out_new();
    if (none.buf.p == null) {
        return -1;
    }
    let rc: i64 = h3_requestx(h, method, path, host, &mut none, body, blen);
    hp_out_free(&mut none);
    return rc;
}

fn h3_stream_p(h: &mut H3, sid: i64) -> ptr<u8> {
    return qc_str_p(&mut h.q, sid);
}

fn h3_stream_n(h: &mut H3, sid: i64) -> i64 {
    return qc_str_n(&mut h.q, sid);
}

fn h3_parse_ctl(h: &mut H3) -> i32 {
    var go: i32 = 1;
    while (go == 1) {
        let p: ptr<u8> = h3_stream_p(h, h.ctl);
        let total: i64 = h3_stream_n(h, h.ctl);
        let off: i64 = h.coff;
        if (p == null || total - off < 2) {
            return H3_OK;
        }
        let ty: i64 = quic_varint_get(p, off);
        let tl: i64 = quic_varint_hdr_len(rt_byte(p, off));
        if (off + tl >= total) {
            return H3_OK;
        }
        let len: i64 = quic_varint_get(p, off + tl);
        let ll: i64 = quic_varint_hdr_len(rt_byte(p, off + tl));
        let end: i64 = off + tl + ll + len;
        if (end > total) {
            return H3_OK;
        }
        if (ty == H3_GOAWAY) {
            h.err = 1;
        }
        h.coff = end;
        if (h.coff >= total) {
            go = 0;
        }
    }
    return H3_OK;
}

fn h3_parse_aux(h: &mut H3, sid: i64, which: i64) -> i32 {
    var go: i32 = 1;
    while (go == 1) {
        let p: ptr<u8> = h3_stream_p(h, sid);
        let total: i64 = h3_stream_n(h, sid);
        var off: i64 = h.eoff;
        if (which == 1) {
            off = h.doff;
        }
        if (p == null || total - off < 2) {
            return H3_OK;
        }
        let tl: i64 = quic_varint_hdr_len(rt_byte(p, off));
        if (off + tl >= total) {
            return H3_OK;
        }
        let len: i64 = quic_varint_get(p, off + tl);
        let ll: i64 = quic_varint_hdr_len(rt_byte(p, off + tl));
        let end: i64 = off + tl + ll + len;
        if (end > total) {
            return H3_OK;
        }
        if (which == 1) {
            h.doff = end;
        } else {
            h.eoff = end;
        }
        if (end >= total) {
            go = 0;
        }
    }
    return H3_OK;
}

fn h3_parse_req(h: &mut H3, ri: i64) -> i32 {
    var go: i32 = 1;
    while (go == 1) {
        let sid: i64 = h.reqs[ri].id;
        let p: ptr<u8> = h3_stream_p(h, sid);
        let total: i64 = h3_stream_n(h, sid);
        let off: i64 = h.reqs[ri].roff;
        if (p == null || total - off < 2) {
            return H3_OK;
        }
        let ty: i64 = quic_varint_get(p, off);
        let tl: i64 = quic_varint_hdr_len(rt_byte(p, off));
        if (off + tl >= total) {
            return H3_OK;
        }
        let len: i64 = quic_varint_get(p, off + tl);
        let ll: i64 = quic_varint_hdr_len(rt_byte(p, off + tl));
        let db: i64 = off + tl + ll;
        let end: i64 = db + len;        if (end > total) {
            return H3_OK;
        }
        if (ty == H3_HEADERS) {
            var hb: ptr<u8> = null;
            unsafe { hb = p + (off + tl + ll); }
            if (qpk_decode(&mut h.qp, hb, len) != QPACK_OK) {
                h.err = 1;
                return H3_ERR;
            }
            h.reqs[ri].got_hdr = 1;
            hp_out_clear(&mut h.reqs[ri].hdr);
            let cnt: i64 = qpack_count(&mut h.qp);
            var j: i64 = 0;
            while (j < cnt) {
                let np: ptr<u8> = qpack_name(&mut h.qp, j);
                let nl: i64 = qpack_namelen(&mut h.qp, j);
                let vp: ptr<u8> = qpack_value(&mut h.qp, j);
                let vl: i64 = qpack_vallen(&mut h.qp, j);
                hp_out_add(&mut h.reqs[ri].hdr, np, nl, vp, vl);
                j += 1;
            }
        } else if (ty == H3_DATA) {
            var dp: ptr<u8> = null;
            unsafe { dp = p + (off + tl + ll); }
            if (h.reqs[ri].body.len + len > H3_MAX_BODY) {
                h.err = 1;
                return H3_ERR;
            }
            if (len > 0 && hxbuf_put(&mut h.reqs[ri].body, dp, len) != 0) {
                h.err = 1;
                return H3_ERR;
            }
        }
        h.reqs[ri].roff = end;
        if (h.reqs[ri].roff >= total) {
            go = 0;
        }
    }
    if (qc_str_fin(&mut h.q, h.reqs[ri].id) == 1) {
        h.reqs[ri].fin = 1;
    }
    return H3_OK;
}

fn h3_drain(h: &mut H3) -> i32 {
    if (h3_parse_ctl(h) != H3_OK) {
        return H3_ERR;
    }
    if (h3_parse_aux(h, h.enc, 0) != H3_OK) {
        return H3_ERR;
    }
    if (h3_parse_aux(h, h.dec, 1) != H3_OK) {
        return H3_ERR;
    }
    var i: i64 = 0;
    while (i < H3_MAX_REQ) {
        if (h.reqs[i].used == 1) {
            if (h3_parse_req(h, i) != H3_OK) {
                return H3_ERR;
            }
        }
        i += 1;
    }
    return H3_OK;
}

fn h3_recv(h: &mut H3) -> i64 {
    var rxb: [u8; 2048] = [0];
    var rp: ptr<u8> = null;
    unsafe { rp = &mut rxb[0] as ptr<u8>; }
    let n: i64 = qc_recv(&mut h.q, rp, 2048);
    if (n <= 0) {
        return n;
    }
    if (h3_drain(h) != H3_OK) {
        return -1;
    }
    qc_ack_app(&mut h.q);
    return n;
}

fn h3_pump(h: &mut H3) -> i32 {
    var got: i32 = 0;
    var go: i32 = 1;
    while (go == 1 && got < 64) {
        let n: i64 = h3_recv(h);
        if (n > 0) {
            got += 1;
        } else {
            go = 0;
        }
    }
    return got;
}

fn h3_done(h: &mut H3, ri: i64) -> i32 {
    if (ri < 0 || ri >= H3_MAX_REQ || h.reqs[ri].used == 0) {
        return 0;
    }
    if (h.reqs[ri].got_hdr == 0) {
        return 0;
    }
    return h.reqs[ri].fin;
}

fn h3_wait(h: &mut H3, ri: i64, ms: i64) -> i32 {
    var secs: i64 = (ms + 999) / 1000;
    if (secs < 1) {
        secs = 1;
    }
    let deadline: i64 = rt_time() + secs;
    var go: i32 = 1;
    while (go == 1) {
        if (h3_done(h, ri) == 1) {
            return H3_OK;
        }
        if (h.err != 0 || h.q.err != 0) {
            return H3_ERR;
        }
        h3_pump(h);
        if (rt_time() > deadline) {
            go = 0;
        }
    }
    if (h3_done(h, ri) == 1) {
        return H3_OK;
    }
    return H3_ERR;
}

fn h3_status(h: &mut H3, ri: i64) -> i64 {
    if (ri < 0 || ri >= H3_MAX_REQ) {
        return 0;
    }
    let j: i64 = hp_out_find(&mut h.reqs[ri].hdr, ":status", 7);
    if (j < 0) {
        return 0;
    }
    let vp: ptr<u8> = hp_out_value(&mut h.reqs[ri].hdr, j);
    let vl: i64 = hp_out_vlen(&mut h.reqs[ri].hdr, j);
    var v: i64 = 0;
    var k: i64 = 0;
    while (k < vl) {
        let b: u8 = rt_byte(vp, k);
        if (b < 48 || b > 57) {
            return 0;
        }
        v = v * 10 + ((b as i64) - 48);
        k += 1;
    }
    return v;
}

fn h3_hcount(h: &mut H3, ri: i64) -> i64 {
    if (ri < 0 || ri >= H3_MAX_REQ) {
        return 0;
    }
    return h.reqs[ri].hdr.n;
}

fn h3_hname(h: &mut H3, ri: i64, i: i64) -> ptr<u8> {
    if (ri < 0 || ri >= H3_MAX_REQ) {
        return null;
    }
    return hp_out_name(&mut h.reqs[ri].hdr, i);
}

fn h3_hnlen(h: &mut H3, ri: i64, i: i64) -> i64 {
    if (ri < 0 || ri >= H3_MAX_REQ) {
        return 0;
    }
    return hp_out_nlen(&mut h.reqs[ri].hdr, i);
}

fn h3_hvalue(h: &mut H3, ri: i64, i: i64) -> ptr<u8> {
    if (ri < 0 || ri >= H3_MAX_REQ) {
        return null;
    }
    return hp_out_value(&mut h.reqs[ri].hdr, i);
}

fn h3_hvlen(h: &mut H3, ri: i64, i: i64) -> i64 {
    if (ri < 0 || ri >= H3_MAX_REQ) {
        return 0;
    }
    return hp_out_vlen(&mut h.reqs[ri].hdr, i);
}

fn h3_hfind(h: &mut H3, ri: i64, name: ptr<u8>) -> i64 {
    if (ri < 0 || ri >= H3_MAX_REQ) {
        return -1;
    }
    return hp_out_find(&mut h.reqs[ri].hdr, name, rt_len(name));
}

fn h3_his(h: &mut H3, ri: i64, name: ptr<u8>, value: ptr<u8>) -> i32 {
    let j: i64 = h3_hfind(h, ri, name);
    if (j < 0) {
        return 0;
    }
    let vp: ptr<u8> = hp_out_value(&mut h.reqs[ri].hdr, j);
    let vl: i64 = hp_out_vlen(&mut h.reqs[ri].hdr, j);
    let wl: i64 = rt_len(value);
    if (vl != wl) {
        return 0;
    }
    if (vl == 0) {
        return 1;
    }
    return rt_bytes_eq(vp, value, vl);
}

fn h3_body(h: &mut H3, ri: i64) -> ptr<u8> {
    if (ri < 0 || ri >= H3_MAX_REQ) {
        return null;
    }
    return h.reqs[ri].body.p;
}

fn h3_body_len(h: &mut H3, ri: i64) -> i64 {
    if (ri < 0 || ri >= H3_MAX_REQ) {
        return 0;
    }
    return h.reqs[ri].body.len;
}

fn h3_release(h: &mut H3, ri: i64) -> i32 {
    if (ri < 0 || ri >= H3_MAX_REQ || h.reqs[ri].used == 0) {
        return H3_ERR;
    }
    h.reqs[ri].used = 0;
    h.reqs[ri].fin = 0;
    h.reqs[ri].got_hdr = 0;
    h.reqs[ri].roff = 0;
    h.reqs[ri].body.len = 0;
    return H3_OK;
}
