// work/http/t_roots.rsx — read the Windows root store and parse every entry.
include "../../modules/http/roots_win.rsx";
include "../../modules/http/trust.rsx";

fn main() -> i32 {
    var s: TrustStats = zero(TrustStats);
    let rc: i32 = trust_store_stats(&mut s);
    printf("open rc=%d\n", rc);
    printf("count=%lld parsed=%lld\n", s.count, s.parsed);
    if (rc != 0) {
        return 1;
    }
    if (s.count <= 0) {
        return 1;
    }
    if (s.parsed != s.count) {
        printf("parse failures=%lld\n", s.count - s.parsed);
        return 1;
    }
    printf("roots_ok\n");
    return 0;
}
