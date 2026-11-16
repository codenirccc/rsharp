include "rt.rsx";
include "transport_win.rsx";
include "roots_win.rsx";
include "trust.rsx";
include "tls13.rsx";

const HTTPS_OK: i32 = 0;
const HTTPS_ERR: i32 = -1;
const HTTPS_UNTRUSTED: i32 = -2;

struct Https {
    sock: u64,
    t: Tls13,
    open: i32,
    net: i32,
    verified: i32,
    proxied: i32,
    plain: i32
}

fn https_begin(h: &mut Https) -> i32 {
    h.sock = 0;
    h.open = 0;
    h.net = 0;
    h.verified = 0;
    h.proxied = 0;
    h.plain = 0;
    if (hx_net_init() != 0) {
        return HTTPS_ERR;
    }
    h.net = 1;
    return HTTPS_OK;
}

fn https_dial(h: &mut Https, host: ptr<u8>, port: u16, to_ms: i32) -> i32 {
    if (h.net != 1 || h.sock != 0) {
        return HTTPS_ERR;
    }
    let s: u64 = hx_connect(host, port, to_ms, to_ms);
    if (s == 0) {
        return HTTPS_ERR;
    }
    h.sock = s;
    return HTTPS_OK;
}

fn https_dial_proxy(h: &mut Https, proxy: ptr<u8>, pport: u16, host: ptr<u8>, port: u16, to_ms: i32) -> i32 {
    if (h.net != 1 || h.sock != 0) {
        return HTTPS_ERR;
    }
    let s: u64 = hx_connect(proxy, pport, to_ms, to_ms);
    if (s == 0) {
        return HTTPS_ERR;
    }
    if (hx_proxy_connect(s, host, port) != 0) {
        hx_close(s);
        return HTTPS_ERR;
    }
    h.sock = s;
    h.proxied = 1;
    return HTTPS_OK;
}

fn https_handshake(h: &mut Https, host: ptr<u8>) -> i32 {
    if (h.sock == 0 || h.open != 0) {
        return HTTPS_ERR;
    }
    if (tls13_connect(&mut h.t, h.sock, host) != TLS_OK) {
        return HTTPS_ERR;
    }
    h.open = 1;
    return HTTPS_OK;
}

fn https_trust_os(h: &mut Https, host: ptr<u8>) -> i32 {
    if (h.open != 1) {
        return HTTPS_ERR;
    }
    if (trust_verify(&mut h.t.chain, host, rt_len(host), rt_time()) != 1) {
        return HTTPS_UNTRUSTED;
    }
    h.verified = 1;
    return HTTPS_OK;
}

fn https_trust_anchor(h: &mut Https, host: ptr<u8>, anchor: ptr<u8>, alen: i64) -> i32 {
    if (h.open != 1 || anchor == null || alen <= 0) {
        return HTTPS_ERR;
    }
    if (x509_chain_verify(&mut h.t.chain, anchor, alen, host, rt_len(host), rt_time()) != 1) {
        return HTTPS_UNTRUSTED;
    }
    h.verified = 1;
    return HTTPS_OK;
}

fn https_open(h: &mut Https, host: ptr<u8>, port: u16, to_ms: i32) -> i32 {
    if (https_begin(h) != HTTPS_OK) {
        return HTTPS_ERR;
    }
    if (https_dial(h, host, port, to_ms) != HTTPS_OK) {
        https_close(h);
        return HTTPS_ERR;
    }
    if (https_handshake(h, host) != HTTPS_OK) {
        https_close(h);
        return HTTPS_ERR;
    }
    if (https_trust_os(h, host) != HTTPS_OK) {
        https_close(h);
        return HTTPS_UNTRUSTED;
    }
    return HTTPS_OK;
}

fn https_open_anchor(h: &mut Https, host: ptr<u8>, port: u16, to_ms: i32, anchor: ptr<u8>, alen: i64) -> i32 {
    if (https_begin(h) != HTTPS_OK) {
        return HTTPS_ERR;
    }
    if (https_dial(h, host, port, to_ms) != HTTPS_OK) {
        https_close(h);
        return HTTPS_ERR;
    }
    if (https_handshake(h, host) != HTTPS_OK) {
        https_close(h);
        return HTTPS_ERR;
    }
    if (https_trust_anchor(h, host, anchor, alen) != HTTPS_OK) {
        https_close(h);
        return HTTPS_UNTRUSTED;
    }
    return HTTPS_OK;
}

fn https_open_proxy(h: &mut Https, proxy: ptr<u8>, pport: u16, host: ptr<u8>, port: u16, to_ms: i32) -> i32 {
    if (https_begin(h) != HTTPS_OK) {
        return HTTPS_ERR;
    }
    if (https_dial_proxy(h, proxy, pport, host, port, to_ms) != HTTPS_OK) {
        https_close(h);
        return HTTPS_ERR;
    }
    if (https_handshake(h, host) != HTTPS_OK) {
        https_close(h);
        return HTTPS_ERR;
    }
    if (https_trust_os(h, host) != HTTPS_OK) {
        https_close(h);
        return HTTPS_UNTRUSTED;
    }
    return HTTPS_OK;
}

fn https_alpn_offer(h: &mut Https, mode: i32) {
    h.t.alpn_mode = mode;
}

fn https_open_proxy_anchor(h: &mut Https, proxy: ptr<u8>, pport: u16, host: ptr<u8>, port: u16, to_ms: i32, anchor: ptr<u8>, alen: i64) -> i32 {
    if (https_begin(h) != HTTPS_OK) {
        return HTTPS_ERR;
    }
    if (https_dial_proxy(h, proxy, pport, host, port, to_ms) != HTTPS_OK) {
        https_close(h);
        return HTTPS_ERR;
    }
    if (https_handshake(h, host) != HTTPS_OK) {
        https_close(h);
        return HTTPS_ERR;
    }
    if (https_trust_anchor(h, host, anchor, alen) != HTTPS_OK) {
        https_close(h);
        return HTTPS_UNTRUSTED;
    }
    return HTTPS_OK;
}

fn https_open_plain(h: &mut Https, host: ptr<u8>, port: u16, to_ms: i32) -> i32 {
    if (https_begin(h) != HTTPS_OK) {
        return HTTPS_ERR;
    }
    if (https_dial(h, host, port, to_ms) != HTTPS_OK) {
        https_close(h);
        return HTTPS_ERR;
    }
    h.plain = 1;
    h.open = 1;
    h.verified = 1;
    return HTTPS_OK;
}

fn https_write(h: &mut Https, p: ptr<u8>, n: i64) -> i64 {
    if (h.open != 1) {
        return HTTPS_ERR as i64;
    }
    if (h.plain == 1) {
        return hx_send(h.sock, p, n);
    }
    return tls13_write(&mut h.t, p, n);
}

fn https_read(h: &mut Https, out: ptr<u8>, cap: i64) -> i64 {
    if (h.open != 1) {
        return HTTPS_ERR as i64;
    }
    if (h.plain == 1) {
        return hx_recv(h.sock, out, cap);
    }
    return tls13_read(&mut h.t, out, cap);
}

fn https_alpn(h: &mut Https, out: ptr<u8>) -> i64 {
    var src: ptr<u8> = null;
    unsafe { src = &mut h.t.alpn[0] as ptr<u8>; }
    rt_copy(out, src, h.t.alpn_len);
    rt_setbyte(out, h.t.alpn_len, 0);
    return h.t.alpn_len;
}

fn https_close(h: &mut Https) {
    if (h.open == 1) {
        if (h.plain == 0) {
            tls13_close(&mut h.t);
        }
        h.open = 0;
    }
    h.plain = 0;
    if (h.sock != 0) {
        hx_close(h.sock);
        h.sock = 0;
    }
    if (h.net == 1) {
        hx_net_shutdown();
        h.net = 0;
    }
    h.verified = 0;
    h.proxied = 0;
}
