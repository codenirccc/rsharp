extern fn printf(fmt: ptr<u8>, ...) -> i32;

extern "kernel32" {
    fn GetEnvironmentVariableA(name: ptr<u8>, buf: ptr<u8>, size: u32) -> u32;
    fn MultiByteToWideChar(cp: u32, flags: u32, s: ptr<u8>, slen: i32, d: ptr<u16>, dlen: i32) -> i32;
}

extern "winhttp" {
    fn WinHttpOpen(agent: ptr<u16>, access: u32, proxy: ptr<u16>, bypass: ptr<u16>, flags: u32) -> i64;
    fn WinHttpConnect(session: i64, host: ptr<u16>, port: u16, reserved: i64) -> i64;
    fn WinHttpOpenRequest(conn: i64, verb: ptr<u16>, path: ptr<u16>, version: ptr<u16>,
                          referrer: ptr<u16>, types: ptr<u16>, flags: u32) -> i64;
    fn WinHttpSetTimeouts(h: i64, resolve: i32, connect: i32, send: i32, receive: i32) -> i32;
    fn WinHttpSendRequest(req: i64, headers: ptr<u16>, hlen: u32, optional: ptr<u8>,
                          olen: u32, total: u32, ctx: i64) -> i32;
    fn WinHttpReceiveResponse(req: i64, reserved: ptr<u8>) -> i32;
    fn WinHttpQueryHeaders(req: i64, info: u32, name: ptr<u16>, buf: ptr<u8>,
                           len: ptr<u32>, index: ptr<u32>) -> i32;
    fn WinHttpReadData(req: i64, buf: ptr<u8>, want: u32, got: ptr<u32>) -> i32;
    fn WinHttpCloseHandle(h: i64) -> i32;
}

const PATHSZ: i64 = 2048;
const BODYSZ: i64 = 8192;
const CFGSZ: u32 = 160;

const ACCESS_NO_PROXY: u32 = 1;
const FLAG_SECURE: u32 = 0x00800000;
const QUERY_STATUS: u32 = 0x20000013;

struct PubNub {
    pubkey: ptr<u8>,
    subkey: ptr<u8>,
    channel: ptr<u8>,
    uuid: ptr<u8>
}

fn hexd(v: u8) -> u8 {
    if (v < 10) {
        return v + 48;
    }
    return v + 55;
}

fn put_into(dst: ptr<u8>, at: ptr<i64>, src: ptr<u8>) {
    unsafe {
        var i: i64 = 0;
        while (src[i] != 0) {
            dst[at[0]] = src[i];
            at[0] = at[0] + 1;
            i = i + 1;
        }
    }
}

fn num_into(dst: ptr<u8>, at: ptr<i64>, v: i64) {
    var tmp: [u8; 24] = [0];
    var i: i64 = 0;
    var n: i64 = v;
    var neg: bool = false;
    if (n < 0) {
        neg = true;
        n = 0 - n;
    }
    if (n == 0) {
        unsafe {
            dst[at[0]] = 48;
            at[0] = at[0] + 1;
        }
        return;
    }
    while (n > 0) {
        tmp[i] = (48 + (n % 10)) as u8;
        i = i + 1;
        n = n / 10;
    }
    if (neg) {
        unsafe {
            dst[at[0]] = 45;
            at[0] = at[0] + 1;
        }
    }
    while (i > 0) {
        i = i - 1;
        unsafe {
            dst[at[0]] = tmp[i];
            at[0] = at[0] + 1;
        }
    }
}

fn pct_into(dst: ptr<u8>, at: ptr<i64>, src: ptr<u8>) {
    unsafe {
        var i: i64 = 0;
        while (src[i] != 0) {
            let c: u8 = src[i];
            var keep: bool = false;
            if (c >= 65 && c <= 90) {
                keep = true;
            }
            if (c >= 97 && c <= 122) {
                keep = true;
            }
            if (c >= 48 && c <= 57) {
                keep = true;
            }
            if (c == 45 || c == 46 || c == 95 || c == 126) {
                keep = true;
            }
            if (keep) {
                dst[at[0]] = c;
                at[0] = at[0] + 1;
            } else {
                dst[at[0]] = 37;
                at[0] = at[0] + 1;
                dst[at[0]] = hexd(c / 16);
                at[0] = at[0] + 1;
                dst[at[0]] = hexd(c % 16);
                at[0] = at[0] + 1;
            }
            i = i + 1;
        }
    }
}

fn json_into(dst: ptr<u8>, at: ptr<i64>, src: ptr<u8>) {
    unsafe {
        dst[at[0]] = 34;
        at[0] = at[0] + 1;
        var i: i64 = 0;
        while (src[i] != 0) {
            let c: u8 = src[i];
            if (c == 34 || c == 92) {
                dst[at[0]] = 92;
                at[0] = at[0] + 1;
                dst[at[0]] = c;
                at[0] = at[0] + 1;
            } else if (c < 32) {
                dst[at[0]] = 92;
                at[0] = at[0] + 1;
                dst[at[0]] = 117;
                at[0] = at[0] + 1;
                dst[at[0]] = 48;
                at[0] = at[0] + 1;
                dst[at[0]] = 48;
                at[0] = at[0] + 1;
                dst[at[0]] = hexd(c / 16);
                at[0] = at[0] + 1;
                dst[at[0]] = hexd(c % 16);
                at[0] = at[0] + 1;
            } else {
                dst[at[0]] = c;
                at[0] = at[0] + 1;
            }
            i = i + 1;
        }
        dst[at[0]] = 34;
        at[0] = at[0] + 1;
        dst[at[0]] = 0;
    }
}

fn say(s: ptr<u8>) {
    printf("%s\n", s);
}

fn load_cfg(name: ptr<u8>, dst: ptr<u8>, fallback: ptr<u8>, cap: u32) {
    var n: u32 = 0;
    unsafe {
        n = GetEnvironmentVariableA(name, dst, cap);
    }
    if (n == 0) {
        var at: i64 = 0;
        unsafe {
            put_into(dst, &mut at as ptr<i64>, fallback);
            dst[at] = 0;
        }
    }
}

fn wcopy(dst: ptr<u16>, cap: i32, src: ptr<u8>) -> i32 {
    return MultiByteToWideChar(65001, 0, src, -1, dst, cap);
}

fn pn_get(path: ptr<u8>, out: ptr<u8>, cap: i64) -> i64 {
    var agent: [u16; 64] = [0];
    var host: [u16; 64] = [0];
    var verb: [u16; 8] = [0];
    var wpath: [u16; 2048] = [0];

    unsafe {
        wcopy(&mut agent[0] as ptr<u16>, 64, "rsharp-pubnub/1.0" as ptr<u8>);
        wcopy(&mut host[0] as ptr<u16>, 64, "ps.pndsn.com" as ptr<u8>);
        wcopy(&mut verb[0] as ptr<u16>, 8, "GET" as ptr<u8>);
        wcopy(&mut wpath[0] as ptr<u16>, PATHSZ as i32, path);
    }

    var session: i64 = 0;
    unsafe {
        session = WinHttpOpen(&mut agent[0] as ptr<u16>, ACCESS_NO_PROXY, null, null, 0);
    }
    if (session == 0) {
        unsafe {
            out[0] = 0;
        }
        return -1;
    }
    unsafe {
        WinHttpSetTimeouts(session, 5000, 5000, 5000, 30000);
    }

    var conn: i64 = 0;
    unsafe {
        conn = WinHttpConnect(session, &mut host[0] as ptr<u16>, 443, 0);
    }
    if (conn == 0) {
        unsafe {
            out[0] = 0;
            WinHttpCloseHandle(session);
        }
        return -2;
    }

    var req: i64 = 0;
    unsafe {
        req = WinHttpOpenRequest(conn, &mut verb[0] as ptr<u16>, &mut wpath[0] as ptr<u16>,
                                 null, null, null, FLAG_SECURE);
    }
    if (req == 0) {
        unsafe {
            out[0] = 0;
            WinHttpCloseHandle(conn);
            WinHttpCloseHandle(session);
        }
        return -3;
    }

    var ok: i32 = 0;
    unsafe {
        ok = WinHttpSendRequest(req, null, 0, null, 0, 0, 0);
        if (ok != 0) {
            ok = WinHttpReceiveResponse(req, null);
        }
    }
    if (ok == 0) {
        unsafe {
            out[0] = 0;
            WinHttpCloseHandle(req);
            WinHttpCloseHandle(conn);
            WinHttpCloseHandle(session);
        }
        return -4;
    }

    var code: u32 = 0;
    var clen: u32 = 4;
    unsafe {
        WinHttpQueryHeaders(req, QUERY_STATUS, null, &mut code as ptr<u8>, &mut clen as ptr<u32>, null);
    }

    var total: i64 = 0;
    while (total < cap - 1) {
        var chunk: u32 = 0;
        unsafe {
            ok = WinHttpReadData(req, out + total, (cap - 1 - total) as u32, &mut chunk as ptr<u32>);
        }
        if (ok == 0 || chunk == 0) {
            break;
        }
        total = total + chunk as i64;
    }
    unsafe {
        out[total] = 0;
    }

    unsafe {
        WinHttpCloseHandle(req);
        WinHttpCloseHandle(conn);
        WinHttpCloseHandle(session);
    }
    return code as i64;
}

fn tt_into(body: ptr<u8>, dst: ptr<u8>) {
    unsafe {
        var i: i64 = 0;
        var done: bool = false;
        while (body[i] != 0 && !done) {
            if (body[i] == 34 && body[i + 1] == 116 && body[i + 2] == 34
                && body[i + 3] == 58 && body[i + 4] == 34) {
                var j: i64 = 0;
                var k: i64 = i + 5;
                while (body[k] >= 48 && body[k] <= 57) {
                    dst[j] = body[k];
                    j = j + 1;
                    k = k + 1;
                }
                dst[j] = 0;
                done = true;
            }
            i = i + 1;
        }
        if (done) {
            return;
        }

        i = 0;
        while (body[i] != 0 && !done) {
            if (body[i] == 93 && body[i + 1] == 44 && body[i + 2] == 34) {
                var j: i64 = 0;
                var k: i64 = i + 3;
                while (body[k] >= 48 && body[k] <= 57) {
                    dst[j] = body[k];
                    j = j + 1;
                    k = k + 1;
                }
                if (j > 0) {
                    dst[j] = 0;
                    done = true;
                }
            }
            i = i + 1;
        }
        if (!done) {
            dst[0] = 0;
        }
    }
}

fn pn_publish(p: &PubNub, msg: ptr<u8>, out: ptr<u8>, cap: i64) -> i64 {
    var path: [u8; 2048] = [0];
    var json: [u8; 1024] = [0];
    var at: i64 = 0;
    var jn: i64 = 0;
    unsafe {
        json_into(&mut json[0] as ptr<u8>, &mut jn as ptr<i64>, msg);
        put_into(&mut path[0] as ptr<u8>, &mut at as ptr<i64>, "/publish/" as ptr<u8>);
        pct_into(&mut path[0] as ptr<u8>, &mut at as ptr<i64>, p.pubkey);
        put_into(&mut path[0] as ptr<u8>, &mut at as ptr<i64>, "/" as ptr<u8>);
        pct_into(&mut path[0] as ptr<u8>, &mut at as ptr<i64>, p.subkey);
        put_into(&mut path[0] as ptr<u8>, &mut at as ptr<i64>, "/0/" as ptr<u8>);
        pct_into(&mut path[0] as ptr<u8>, &mut at as ptr<i64>, p.channel);
        put_into(&mut path[0] as ptr<u8>, &mut at as ptr<i64>, "/0/" as ptr<u8>);
        put_into(&mut path[0] as ptr<u8>, &mut at as ptr<i64>, &mut json[0] as ptr<u8>);
        put_into(&mut path[0] as ptr<u8>, &mut at as ptr<i64>, "?uuid=" as ptr<u8>);
        pct_into(&mut path[0] as ptr<u8>, &mut at as ptr<i64>, p.uuid);
        path[at] = 0;
    }
    var st: i64 = 0;
    unsafe {
        st = pn_get(&mut path[0] as ptr<u8>, out, cap);
    }
    return st;
}

fn pn_history(p: &PubNub, count: i64, out: ptr<u8>, cap: i64) -> i64 {
    var path: [u8; 2048] = [0];
    var at: i64 = 0;
    unsafe {
        put_into(&mut path[0] as ptr<u8>, &mut at as ptr<i64>, "/v2/history/sub-key/" as ptr<u8>);
        pct_into(&mut path[0] as ptr<u8>, &mut at as ptr<i64>, p.subkey);
        put_into(&mut path[0] as ptr<u8>, &mut at as ptr<i64>, "/channel/" as ptr<u8>);
        pct_into(&mut path[0] as ptr<u8>, &mut at as ptr<i64>, p.channel);
        put_into(&mut path[0] as ptr<u8>, &mut at as ptr<i64>, "?count=" as ptr<u8>);
        num_into(&mut path[0] as ptr<u8>, &mut at as ptr<i64>, count);
        path[at] = 0;
    }
    var st: i64 = 0;
    unsafe {
        st = pn_get(&mut path[0] as ptr<u8>, out, cap);
    }
    return st;
}

fn pn_subscribe(p: &PubNub, tt: ptr<u8>, out: ptr<u8>, cap: i64) -> i64 {
    var path: [u8; 2048] = [0];
    var at: i64 = 0;
    unsafe {
        put_into(&mut path[0] as ptr<u8>, &mut at as ptr<i64>, "/subscribe/" as ptr<u8>);
        pct_into(&mut path[0] as ptr<u8>, &mut at as ptr<i64>, p.subkey);
        put_into(&mut path[0] as ptr<u8>, &mut at as ptr<i64>, "/" as ptr<u8>);
        pct_into(&mut path[0] as ptr<u8>, &mut at as ptr<i64>, p.channel);
        put_into(&mut path[0] as ptr<u8>, &mut at as ptr<i64>, "/0/" as ptr<u8>);
        put_into(&mut path[0] as ptr<u8>, &mut at as ptr<i64>, tt);
        put_into(&mut path[0] as ptr<u8>, &mut at as ptr<i64>, "?uuid=" as ptr<u8>);
        pct_into(&mut path[0] as ptr<u8>, &mut at as ptr<i64>, p.uuid);
        path[at] = 0;
    }
    var st: i64 = 0;
    unsafe {
        st = pn_get(&mut path[0] as ptr<u8>, out, cap);
    }
    return st;
}

fn pn_time(p: &PubNub, out: ptr<u8>, cap: i64) -> i64 {
    var path: [u8; 64] = [0];
    var at: i64 = 0;
    unsafe {
        put_into(&mut path[0] as ptr<u8>, &mut at as ptr<i64>, "/time/0?uuid=" as ptr<u8>);
        pct_into(&mut path[0] as ptr<u8>, &mut at as ptr<i64>, p.uuid);
        path[at] = 0;
    }
    var st: i64 = 0;
    unsafe {
        st = pn_get(&mut path[0] as ptr<u8>, out, cap);
    }
    return st;
}

fn main() -> i32 {
    var pubkey: [u8; 160] = [0];
    var subkey: [u8; 160] = [0];
    var chan: [u8; 160] = [0];
    var body: [u8; 8192] = [0];
    var tt: [u8; 64] = [0];

    unsafe {
        load_cfg("PUBNUB_PUBLISH_KEY" as ptr<u8>, &mut pubkey[0] as ptr<u8>, "demo" as ptr<u8>, CFGSZ);
        load_cfg("PUBNUB_SUBSCRIBE_KEY" as ptr<u8>, &mut subkey[0] as ptr<u8>, "demo" as ptr<u8>, CFGSZ);
        load_cfg("PUBNUB_CHANNEL" as ptr<u8>, &mut chan[0] as ptr<u8>, "rsharp" as ptr<u8>, CFGSZ);
    }

    var pn: PubNub = zero(PubNub);
    pn.pubkey = "demo" as ptr<u8>;
    pn.subkey = "demo" as ptr<u8>;
    pn.channel = "rsharp" as ptr<u8>;
    pn.uuid = "rsharp-demo" as ptr<u8>;

    var bodyp: ptr<u8> = null;
    var ttp: ptr<u8> = null;
    var st: i64 = 0;
    unsafe {
        pn.pubkey = &mut pubkey[0] as ptr<u8>;
        pn.subkey = &mut subkey[0] as ptr<u8>;
        pn.channel = &mut chan[0] as ptr<u8>;
        bodyp = &mut body[0] as ptr<u8>;
        ttp = &mut tt[0] as ptr<u8>;
    }

    printf("pubnub: channel %s\n", pn.channel);

    unsafe {
        st = pn_time(&pn, bodyp, BODYSZ);
    }
    printf("time       %lld  ", st);
    say(bodyp);

    unsafe {
        st = pn_publish(&pn, "hello from rsharp" as ptr<u8>, bodyp, BODYSZ);
    }
    printf("publish    %lld  ", st);
    say(bodyp);

    unsafe {
        st = pn_history(&pn, 5, bodyp, BODYSZ);
    }
    printf("history    %lld  ", st);
    say(bodyp);

    unsafe {
        tt[0] = 48;
        tt[1] = 0;
        st = pn_subscribe(&pn, ttp, bodyp, BODYSZ);
    }
    printf("subscribe  %lld  ", st);
    say(bodyp);
    unsafe {
        tt_into(bodyp, ttp);
    }
    printf("next tt    %s\n", ttp);

    var round: i64 = 0;
    while (round < 3) {
        unsafe {
            st = pn_publish(&pn, "ping from rsharp" as ptr<u8>, bodyp, BODYSZ);
        }
        printf("publish    %lld  ", st);
        say(bodyp);
        unsafe {
            st = pn_subscribe(&pn, ttp, bodyp, BODYSZ);
        }
        printf("subscribe  %lld  ", st);
        say(bodyp);
        unsafe {
            tt_into(bodyp, ttp);
        }
        printf("next tt    %s\n", ttp);
        round = round + 1;
    }

    return 0;
}
