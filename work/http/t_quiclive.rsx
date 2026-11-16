include "../../modules/http/quic_client.rsx";
include "../../modules/http/trust.rsx";
include "../../modules/http/roots_win.rsx";
include "https_anchor.rsx";

const T_PORT: i64 = 4445;

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

fn drain(sock: u64, want: i64) -> i64 {
    var rxb: [u8; 2048] = [0];
    var rp: ptr<u8> = null;
    unsafe { rp = &mut rxb[0] as ptr<u8>; }
    let n: i64 = hx_udp_recv(sock, rp, 2048);
    if (n <= 0) {
        return -1;
    }
    if (want > 0 && n != want) {
        return n;
    }
    return n;
}

fn main() -> i32 {
    var t: Tally = zero(Tally);
    t.pass = 0;
    t.total = 0;

    var anchor: [u8; 2048] = [0];
    var ap: ptr<u8> = null;
    unsafe { ap = &mut anchor[0] as ptr<u8>; }
    let alen: i64 = https_anchor_rsa(ap, 2048);
    t_ok(&mut t, "anchor loaded", alen > 0);

    var c: Qc = zero(Qc);
    let rc: i32 = qc_open(&mut c, "localhost", T_PORT as u16, 400);
    t_ok(&mut t, "handshake", rc == QC_OK);
    t_ok(&mut t, "handshake done", c.hs_done == 1);
    t_ok(&mut t, "alpn is h3", qc_alpn_is(&c, "h3") == 1);
    t_ok(&mut t, "1rtt keys derived", c.have[QC_APP] == 1);
    t_ok(&mut t, "peer cid captured", c.peer_len == 8);

    if (rc == QC_OK) {
        let tv: i32 = qc_trust_anchor(&mut c, "localhost", ap, alen);
        t_ok(&mut t, "chain verified against anchor", tv == QC_OK);
        t_ok(&mut t, "verified flag", c.verified == 1);
    }

    if (rc == QC_OK) {
        t_ok(&mut t, "ping sent", qc_ping(&mut c) == QC_OK);
        let n: i64 = drain(c.sock, 0);
        t_ok(&mut t, "1rtt round trip", n > 0);
    }

    if (rc == QC_OK) {
        qc_free(&mut c);
    }

    printf("quiclive_passed=%lld of %lld\n", t.pass, t.total);
    if (t.pass == t.total) {
        return 0;
    }
    return 1;
}
