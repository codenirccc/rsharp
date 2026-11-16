include "quic_client.rsx";
include "trust.rsx";
include "roots_win.rsx";

fn qc_trust_os(q: &mut Qc, host: ptr<u8>) -> i32 {
    if (q.closed == 1) {
        return QC_ERR;
    }
    if (trust_verify(&mut q.t.chain, host, rt_len(host), rt_time()) != 1) {
        return QC_UNTRUSTED;
    }
    q.verified = 1;
    return QC_OK;
}

fn qc_open_os(q: &mut Qc, host: ptr<u8>, port: u16, to_ms: i32) -> i32 {
    let rc: i32 = qc_open(q, host, port, to_ms);
    if (rc != QC_OK) {
        return rc;
    }
    let tr: i32 = qc_trust_os(q, host);
    if (tr != QC_OK) {
        qc_free(q);
        return tr;
    }
    return QC_OK;
}
