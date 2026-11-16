// pubnub.rsx — a PubNub client written in R#.
//
// There is no SDK download here and nothing to link but Windows itself. The
// client is WinHTTP for the socket and the TLS, a byte buffer for the URL, and
// a hand-rolled percent-encoder and JSON string writer, because R# has no
// string values to concatenate. Publish, subscribe, history and time, over the
// REST API at ps.pndsn.com.
//
// Build:
//   rsc.cmd sdk\pubnub\pubnub.rsx
// Run:
//   set PUBNUB_PUBLISH_KEY=demo
//   set PUBNUB_SUBSCRIBE_KEY=demo
//   set PUBNUB_CHANNEL=rsharp
//   sdk\pubnub\pubnub.exe
//
// Everything above `main` is the library. R# has no modules, so an app copies
// this file in and keeps its own `main`; the demo below shows the calls.

extern fn printf(fmt: ptr<u8>, ...) -> i32;

extern "kernel32" {
    fn GetStdHandle(kind: i32) -> i64;
    fn WriteFile(h: i64, buf: ptr<u8>, n: u32, wrote: ptr<u32>, ov: ptr<u8>) -> i32;
    fn MultiByteToWideChar(cp: u32, flags: u32, s: ptr<u8>, slen: i32, d: ptr<u16>, dlen: i32) -> i32;
    fn GetEnvironmentVariableA(name: ptr<u8>, buf: ptr<u8>, size: u32) -> u32;
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

const PATHMAX: i64 = 2048;
const BODYMAX: i64 = 8192;
const CFGMAX: i64 = 160;

const WINHTTP_ACCESS_TYPE_NO_PROXY: u32 = 1;
const WINHTTP_FLAG_SECURE: u32 = 0x00800000;
const WINHTTP_QUERY_STATUS_CODE: u32 = 0x20000013;

struct PubNub {
    pubkey: ptr<u8>,
    subkey: ptr<u8>,
    channel: ptr<u8>,
    uuid: ptr<u8>
}

// ── bytes ───────────────────────────────────────────────────────────────────

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

// RFC 3986 unreserved set stays literal, everything else becomes %XX.
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

// A JSON string: quotes and backslashes escaped, controls as \u00XX.
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

// Config from the environment, with the literal as the fallback.
fn load_cfg(name: ptr<u8>, dst: ptr<u8>, fallback: ptr<u8>, cap: u32) {
    var n: u32 = 0;
    unsafe { n = GetEnvironmentVariableA(name, dst, cap); }
    if (n == 0) {
        var at: i64 = 0;
        unsafe { put_into(dst, &at as ptr<i64>, fallback); }
    }
}

// ── transport ───────────────────────────────────────────────────────────────

fn wcopy(dst: ptr<u16>, cap: i32, src: ptr<u8>) -> i32 {
    return MultiByteToWideChar(65001, 0, src, -1, dst, cap);
}

// One GET. Writes the NUL terminated body into `out` and returns the HTTP
// status, or a negative number when a handle could not be opened.
fn pn_get(path: ptr<u8>, out: ptr<u8>, cap: i64) -> i64 {
    var agent: [u16; 64] = [0];
    var host: [u16; 64] = [0];
    var verb: [u16; 8] = [0];
    var wpath: [u16; PATHMAX] = [0];

    unsafe {
        wcopy(&agent[0] as ptr<u16>, 64, "rsharp-pubnub/1.0");
        wcopy(&host[0] as ptr<u16>, 64, "ps.pndsn.com");
        wcopy(&verb[0] as ptr<u16>, 8, "GET");
        wcopy(&wpath[0] as ptr<u16>, PATHMAX as i32, path);
    }

    var session: i64 = 0;
    unsafe { session = WinHttpOpen(&agent[0] as ptr<u16>, WINHTTP_ACCESS_TYPE_NO_PROXY, null, null, 0); }
    if (session == 0) {
        unsafe { out[0] = 0; }
        return -1;
    }
    unsafe { WinHttpSetTimeouts(session, 5000, 5000, 5000, 30000); }

    var conn: i64 = 0;
    unsafe { conn = WinHttpConnect(session, &host[0] as ptr<u16>, 443, 0); }
    if (conn == 0) {
        unsafe {
            out[0] = 0;
            WinHttpCloseHandle(session);
        }
        return -2;
    }

    var req: i64 = 0;
    unsafe {
        req = WinHttpOpenRequest(conn, &verb[0] as ptr<u16>, &wpath[0] as ptr<u16>,
                                 null, null, null, WINHTTP_FLAG_SECURE);
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
        WinHttpQueryHeaders(req, WINHTTP_QUERY_STATUS_CODE, null,
                            &code as ptr<u8>, &clen as ptr<u32>, null);
    }

    var total: i64 = 0;
    while (total < cap - 1) {
        var chunk: u32 = 0;
        unsafe {
            ok = WinHttpReadData(req, &out[total] as ptr<u8>, (cap - 1 - total) as u32,
                                 &chunk as ptr<u32>);
        }
        if (ok == 0 || chunk == 0) {
            break;
        }
        total = total + chunk as i64;
    }
    unsafe { out[total] = 0; }

    unsafe {
        WinHttpCloseHandle(req);
        WinHttpCloseHandle(conn);
        WinHttpCloseHandle(session);
    }
    return code as i64;
}

// Pull the next timetoken out of a subscribe body. Two shapes answer: the v2
// envelope carries {"t":{"t":"1699..."}}, the plain endpoint answers
// [[...messages...],"1699..."]. Try the labelled one, then the trailing one.
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

// ── the API ─────────────────────────────────────────────────────────────────

fn pn_publish(p: &PubNub, msg: ptr<u8>, out: ptr<u8>, cap: i64) -> i64 {
    var path: [u8; PATHMAX] = [0];
    var json: [u8; 1024] = [0];
    var at: i64 = 0;
    var jn: i64 = 0;

    unsafe { json_into(&json[0] as ptr<u8>, &jn as ptr<i64>, msg); }

    unsafe {
        put_into(&path[0] as ptr<u8>, &at as ptr<i64>, "/publish/");
        pct_into(&path[0] as ptr<u8>, &at as ptr<i64>, p.pubkey);
        put_into(&path[0] as ptr<u8>, &at as ptr<i64>, "/");
        pct_into(&path[0] as ptr<u8>, &at as ptr<i64>, p.subkey);
        put_into(&path[0] as ptr<u8>, &at as ptr<i64>, "/0/");
        pct_into(&path[0] as ptr<u8>, &at as ptr<i64>, p.channel);
        put_into(&path[0] as ptr<u8>, &at as ptr<i64>, "/0/");
        put_into(&path[0] as ptr<u8>, &at as ptr<i64>, &json[0] as ptr<u8>);
        put_into(&path[0] as ptr<u8>, &at as ptr<i64>, "?uuid=");
        pct_into(&path[0] as ptr<u8>, &at as ptr<i64>, p.uuid);
    }
    path[at] = 0;

    var st: i64 = 0;
    unsafe { st = pn_get(&path[0] as ptr<u8>, out, cap); }
    return st;
}

fn pn_history(p: &PubNub, count: i64, out: ptr<u8>, cap: i64) -> i64 {
    var path: [u8; PATHMAX] = [0];
    var at: i64 = 0;

    unsafe {
        put_into(&path[0] as ptr<u8>, &at as ptr<i64>, "/v2/history/sub-key/");
        pct_into(&path[0] as ptr<u8>, &at as ptr<i64>, p.subkey);
        put_into(&path[0] as ptr<u8>, &at as ptr<i64>, "/channel/");
        pct_into(&path[0] as ptr<u8>, &at as ptr<i64>, p.channel);
        put_into(&path[0] as ptr<u8>, &at as ptr<i64>, "?count=");
        num_into(&path[0] as ptr<u8>, &at as ptr<i64>, count);
    }
    path[at] = 0;

    var st: i64 = 0;
    unsafe { st = pn_get(&path[0] as ptr<u8>, out, cap); }
    return st;
}

fn pn_subscribe(p: &PubNub, tt: ptr<u8>, out: ptr<u8>, cap: i64) -> i64 {
    var path: [u8; PATHMAX] = [0];
    var at: i64 = 0;

    unsafe {
        put_into(&path[0] as ptr<u8>, &at as ptr<i64>, "/subscribe/");
        pct_into(&path[0] as ptr<u8>, &at as ptr<i64>, p.subkey);
        put_into(&path[0] as ptr<u8>, &at as ptr<i64>, "/");
        pct_into(&path[0] as ptr<u8>, &at as ptr<i64>, p.channel);
        put_into(&path[0] as ptr<u8>, &at as ptr<i64>, "/0/");
        put_into(&path[0] as ptr<u8>, &at as ptr<i64>, tt);
        put_into(&path[0] as ptr<u8>, &at as ptr<i64>, "?uuid=");
        pct_into(&path[0] as ptr<u8>, &at as ptr<i64>, p.uuid);
    }
    path[at] = 0;

    var st: i64 = 0;
    unsafe { st = pn_get(&path[0] as ptr<u8>, out, cap); }
    return st;
}

fn pn_time(p: &PubNub, out: ptr<u8>, cap: i64) -> i64 {
    var path: [u8; 64] = [0];
    var at: i64 = 0;
    unsafe {
        put_into(&path[0] as ptr<u8>, &at as ptr<i64>, "/time/0?uuid=");
        pct_into(&path[0] as ptr<u8>, &at as ptr<i64>, p.uuid);
    }
    path[at] = 0;

    var st: i64 = 0;
    unsafe { st = pn_get(&path[0] as ptr<u8>, out, cap); }
    return st;
}

// ── demo ────────────────────────────────────────────────────────────────────

// The demo is written in the brace-less form: a block is closed by `end;`
// instead of `}`, one terminator per statement. Braces still work and the two
// forms mix, so the library above keeps its own style.
fn main() -> i32
    var pubkey: [u8; CFGMAX] = [0];
    var subkey: [u8; CFGMAX] = [0];
    var chan: [u8; CFGMAX] = [0];
    var body: [u8; BODYMAX] = [0];
    var tt: [u8; 64] = [0];

    unsafe
        load_cfg("PUBNUB_PUBLISH_KEY", &pubkey[0] as ptr<u8>, "demo", CFGMAX as u32);
        load_cfg("PUBNUB_SUBSCRIBE_KEY", &subkey[0] as ptr<u8>, "demo", CFGMAX as u32);
        load_cfg("PUBNUB_CHANNEL", &chan[0] as ptr<u8>, "rsharp", CFGMAX as u32);
    end;

    var pn: PubNub = PubNub {
        pubkey: "demo",
        subkey: "demo",
        channel: "rsharp",
        uuid: "rsharp-demo"
    };

    var bodyp: ptr<u8> = null;
    var ttp: ptr<u8> = null;
    var st: i64 = 0;
    unsafe
        pn.pubkey = &pubkey[0] as ptr<u8>;
        pn.subkey = &subkey[0] as ptr<u8>;
        pn.channel = &chan[0] as ptr<u8>;
        bodyp = &body[0] as ptr<u8>;
        ttp = &tt[0] as ptr<u8>;
    end;

    printf("pubnub: channel %s\n", pn.channel);

    unsafe
        st = pn_time(&pn, bodyp, BODYMAX);
    end;
    printf("time       %lld  ", st);
    say(bodyp);

    unsafe
        st = pn_publish(&pn, "hello from rsharp", bodyp, BODYMAX);
    end;
    printf("publish    %lld  ", st);
    say(bodyp);

    unsafe
        st = pn_history(&pn, 5, bodyp, BODYMAX);
    end;
    printf("history    %lld  ", st);
    say(bodyp);

    unsafe
        tt[0] = 48;
        tt[1] = 0;
    end;

    // A first subscribe with tt 0 returns immediately and hands back the
    // server's current timetoken; every round after that publishes and then
    // asks from that point forward, so the message is already waiting.
    unsafe
        st = pn_subscribe(&pn, ttp, bodyp, BODYMAX);
    end;
    printf("subscribe  %lld  ", st);
    say(bodyp);
    unsafe
        tt_into(bodyp, ttp);
    end;
    printf("next tt    %s\n", ttp);

    var round: i64 = 0;
    while (round < 3)
        unsafe
            st = pn_publish(&pn, "ping from rsharp", bodyp, BODYMAX);
        end;
        printf("publish    %lld  ", st);
        say(bodyp);
        unsafe
            st = pn_subscribe(&pn, ttp, bodyp, BODYMAX);
        end;
        printf("subscribe  %lld  ", st);
        say(bodyp);
        unsafe
            tt_into(bodyp, ttp);
        end;
        printf("next tt    %s\n", ttp);
        round = round + 1;
    end;

    return 0;
end;
