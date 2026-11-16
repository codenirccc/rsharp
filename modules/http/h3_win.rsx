include "h3_client.rsx";
include "trust.rsx";
include "roots_win.rsx";

fn h3_trust_os(h: &mut H3, host: ptr<u8>) -> i32 {
    if (h.q.closed == 1) {
        return H3_ERR;
    }
    if (trust_verify(&mut h.q.t.chain, host, rt_len(host), rt_time()) != 1) {
        return H3_UNTRUSTED;
    }
    h.q.verified = 1;
    return H3_OK;
}

fn h3_open_os(h: &mut H3, host: ptr<u8>, port: u16, to_ms: i32) -> i32 {
    let rc: i32 = h3_open(h, host, port, to_ms);
    if (rc != H3_OK) {
        return rc;
    }
    let tr: i32 = h3_trust_os(h, host);
    if (tr != H3_OK) {
        h3_free(h);
        return tr;
    }
    return H3_OK;
}
