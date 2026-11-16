include "x509.rsx";

fn trust_verify(ch: &mut X509Chain, host: ptr<u8>, hlen: i64, now: i64) -> i32 {
    if (ch.n < 1) {
        return 0;
    }

    var leaf: X509 = zero(X509);
    if (x509_chain_parse(ch, 0, &mut leaf) != 0) {
        return 0;
    }
    if (x509_leaf_ok(&mut leaf, now) != 1) {
        return 0;
    }
    if (x509_check_host(&mut leaf, host, hlen) != 1) {
        return 0;
    }

    var i: i64 = 1;
    while (i < ch.n) {
        var child: X509 = zero(X509);
        var parent: X509 = zero(X509);
        if (x509_chain_parse(ch, i - 1, &mut child) != 0) {
            return 0;
        }
        if (x509_chain_parse(ch, i, &mut parent) != 0) {
            return 0;
        }
        if (x509_signed_by(&mut child, &mut parent, now) != 1) {
            return 0;
        }
        i += 1;
    }

    var top: X509 = zero(X509);
    if (x509_chain_parse(ch, ch.n - 1, &mut top) != 0) {
        return 0;
    }

    var roots: Roots = zero(Roots);
    if (roots_open(&mut roots) != 0) {
        return 0;
    }

    var blob: RtBlob = zero(RtBlob);
    var trust: i32 = 0;
    var st: i32 = 1;
    while (st != 0) {
        st = roots_next(&mut roots, &mut blob);
        if (st == 1) {
            var anchor: X509 = zero(X509);
            if (x509_parse(&mut anchor, blob.p, blob.len) == 0) {
                if (x509_name_matches(&mut top, &mut anchor) == 1) {
                    if (x509_signed_by(&mut top, &mut anchor, now) == 1) {
                        trust = 1;
                    }
                }
            }
        }
    }
    roots_close(&mut roots);
    return trust;
}

struct TrustStats {
    count: i64,
    parsed: i64
}

fn trust_store_stats(s: &mut TrustStats) -> i32 {
    s.count = 0;
    s.parsed = 0;
    var roots: Roots = zero(Roots);
    if (roots_open(&mut roots) != 0) {
        return -1;
    }
    var blob: RtBlob = zero(RtBlob);
    var st: i32 = 1;
    while (st != 0) {
        st = roots_next(&mut roots, &mut blob);
        if (st == 1) {
            s.count += 1;
            var anchor: X509 = zero(X509);
            if (x509_parse(&mut anchor, blob.p, blob.len) == 0) {
                s.parsed += 1;
            }
        }
    }
    roots_close(&mut roots);
    return 0;
}
