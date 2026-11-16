extern "ws2_32" fn WSAStartup(wVersion: u16, lpWSAData: ptr<u8>) -> i32;
extern "ws2_32" fn WSACleanup() -> i32;
extern "ws2_32" fn socket(af: i32, ty: i32, proto: i32) -> u64;
extern "ws2_32" fn connect(s: u64, name: ptr<u8>, namelen: i32) -> i32;
extern "ws2_32" fn send(s: u64, buf: ptr<u8>, len: i32, flags: i32) -> i32;
extern "ws2_32" fn recv(s: u64, buf: ptr<u8>, len: i32, flags: i32) -> i32;
extern "ws2_32" fn closesocket(s: u64) -> i32;
extern "ws2_32" fn htons(v: u16) -> u16;
extern "ws2_32" fn getaddrinfo(node: ptr<u8>, service: ptr<u8>, hints: ptr<u8>, res: ptr<u8>) -> i32;
extern "ws2_32" fn freeaddrinfo(p: ptr<u8>) -> void;
extern "ws2_32" fn setsockopt(s: u64, level: i32, name: i32, val: ptr<u8>, len: i32) -> i32;

extern "bcrypt" fn BCryptGenRandom(h: u64, buf: ptr<u8>, len: u32, flags: u32) -> i32;
extern "msvcrt" fn fflush(p: ptr<u8>) -> i32;

const HX_ERR: i32 = -1;
const HX_TIMEOUT: i32 = -2;

const AF_INET: i32 = 2;
const SOCK_STREAM: i32 = 1;
const SOCK_DGRAM: i32 = 2;
const IPPROTO_TCP: i32 = 6;
const IPPROTO_UDP: i32 = 17;
const SOL_SOCKET: i32 = 65535;
const SO_RCVTIMEO: i32 = 4102;
const SO_SNDTIMEO: i32 = 4103;

struct HxAddrInfo {
    ai_flags: i32,
    ai_family: i32,
    ai_socktype: i32,
    ai_protocol: i32,
    ai_addrlen: u64,
    ai_canonname: ptr<u8>,
    ai_addr: ptr<u8>,
    ai_next: ptr<u8>
}

struct HxPtrBox {
    p: ptr<u8>
}

fn hx_net_init() -> i32 {
    var ws: [u8; 512] = [0];
    var wp: ptr<u8> = null;
    unsafe { wp = &mut ws[0] as ptr<u8>; }
    return WSAStartup(514, wp);
}

fn hx_net_shutdown() -> i32 {
    return WSACleanup();
}

fn hx_strlen(s: ptr<u8>) -> i64 {
    return strlen(s) as i64;
}

fn hx_random(buf: ptr<u8>, len: i64) -> i32 {
    if (len <= 0) {
        return 0;
    }
    let rc: i32 = BCryptGenRandom(0, buf, len as u32, 2);
    if (rc != 0) {
        return HX_ERR;
    }
    return 0;
}

fn hx_dial_addr(host: ptr<u8>, port: u16, sty: i32, proto: i32, rcv_to_ms: i32, snd_to_ms: i32) -> u64 {
    var portbuf: [u8; 16] = [0];
    var pp: ptr<u8> = null;
    unsafe { pp = &mut portbuf[0] as ptr<u8>; }
    sprintf(pp, "%u", port as u32);

    var hints: HxAddrInfo = zero(HxAddrInfo);
    hints.ai_family = AF_INET;
    hints.ai_socktype = sty;
    hints.ai_protocol = proto;

    var hp: ptr<u8> = null;
    unsafe { hp = &mut hints as ptr<u8>; }

    var out: HxPtrBox = zero(HxPtrBox);
    var op: ptr<u8> = null;
    unsafe { op = &mut out as ptr<u8>; }

    let gai: i32 = getaddrinfo(host, pp, hp, op);
    if (gai != 0) {
        return 0;
    }

    var head: ptr<u8> = out.p;
    if (head == null) {
        return 0;
    }

    var bad: u64 = 0;
    bad -= 1;

    var node: ptr<HxAddrInfo> = null;
    unsafe { node = head as ptr<HxAddrInfo>; }
    var s: u64 = 0;
    while (node != null) {
        var fam: i32 = 0;
        var ty: i32 = 0;
        var proto: i32 = 0;
        var alen: u64 = 0;
        var aaddr: ptr<u8> = null;
        var anext: ptr<u8> = null;
        unsafe {
            fam = node.ai_family;
            ty = node.ai_socktype;
            proto = node.ai_protocol;
            alen = node.ai_addrlen;
            aaddr = node.ai_addr;
            anext = node.ai_next;
        }
        s = socket(fam, ty, proto);
        if (s != 0 && s != bad) {
            if (rcv_to_ms > 0) {
                var tv: [u8; 8] = [0];
                var tvp: ptr<u8> = null;
                unsafe {
                    tvp = &mut tv[0] as ptr<u8>;
                    tv[0] = (rcv_to_ms & 255) as u8;
                    tv[1] = ((rcv_to_ms >> 8) & 255) as u8;
                    tv[2] = ((rcv_to_ms >> 16) & 255) as u8;
                    tv[3] = ((rcv_to_ms >> 24) & 255) as u8;
                }
                setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, tvp, 4);
            }
            if (snd_to_ms > 0) {
                var tv2: [u8; 8] = [0];
                var tv2p: ptr<u8> = null;
                unsafe {
                    tv2p = &mut tv2[0] as ptr<u8>;
                    tv2[0] = (snd_to_ms & 255) as u8;
                    tv2[1] = ((snd_to_ms >> 8) & 255) as u8;
                    tv2[2] = ((snd_to_ms >> 16) & 255) as u8;
                    tv2[3] = ((snd_to_ms >> 24) & 255) as u8;
                }
                setsockopt(s, SOL_SOCKET, SO_SNDTIMEO, tv2p, 4);
            }
            let cr: i32 = connect(s, aaddr, alen as i32);
            if (cr == 0) {
                freeaddrinfo(head);
                return s;
            }
            closesocket(s);
        }
        unsafe { node = anext as ptr<HxAddrInfo>; }
    }
    freeaddrinfo(head);
    return 0;
}

fn hx_connect(host: ptr<u8>, port: u16, rcv_to_ms: i32, snd_to_ms: i32) -> u64 {
    return hx_dial_addr(host, port, SOCK_STREAM, IPPROTO_TCP, rcv_to_ms, snd_to_ms);
}

fn hx_udp_open(host: ptr<u8>, port: u16, to_ms: i32) -> u64 {
    return hx_dial_addr(host, port, SOCK_DGRAM, IPPROTO_UDP, to_ms, to_ms);
}

fn hx_udp_send(s: u64, buf: ptr<u8>, len: i64) -> i64 {
    if (len < 0 || len > 65507) {
        return HX_ERR as i64;
    }
    let n: i32 = send(s, buf, len as i32, 0);
    if (n < 0) {
        return HX_ERR as i64;
    }
    return n as i64;
}

fn hx_udp_recv(s: u64, buf: ptr<u8>, cap: i64) -> i64 {
    if (cap <= 0) {
        return 0;
    }
    let n: i32 = recv(s, buf, cap as i32, 0);
    if (n < 0) {
        return HX_ERR as i64;
    }
    return n as i64;
}

fn hx_udp_close(s: u64) -> i32 {
    return closesocket(s);
}

fn hx_send(s: u64, buf: ptr<u8>, len: i64) -> i64 {
    var off: i64 = 0;
    while (off < len) {
        var chunk: ptr<u8> = null;
        unsafe { chunk = buf + off; }
        let n: i32 = send(s, chunk, (len - off) as i32, 0);
        if (n <= 0) {
            if (n == -1) {
                return HX_TIMEOUT as i64;
            }
            return HX_ERR as i64;
        }
        off += n as i64;
    }
    return off;
}

fn hx_recv(s: u64, buf: ptr<u8>, len: i64) -> i64 {
    if (len <= 0) {
        return 0;
    }
    let n: i32 = recv(s, buf, len as i32, 0);
    if (n == 0) {
        return 0;
    }
    if (n < 0) {
        return HX_TIMEOUT as i64;
    }
    return n as i64;
}

fn hx_read_until(s: u64, buf: ptr<u8>, cap: i64, d0: u8, d1: u8, d2: u8, d3: u8) -> i64 {
    var have: i64 = 0;
    while (have < cap) {
        var tail: ptr<u8> = null;
        unsafe { tail = buf + have; }
        let n: i64 = hx_recv(s, tail, 1);
        if (n <= 0) {
            return HX_ERR as i64;
        }
        have += 1;
        if (have >= 4) {
            var m: i32 = 0;
            unsafe {
                if (buf[have - 4] == d0) {
                    m += 1;
                }
                if (buf[have - 3] == d1) {
                    m += 1;
                }
                if (buf[have - 2] == d2) {
                    m += 1;
                }
                if (buf[have - 1] == d3) {
                    m += 1;
                }
            }
            if (m == 4) {
                return have;
            }
        }
    }
    return HX_ERR as i64;
}

fn hx_close(s: u64) -> i32 {
    if (s == 0) {
        return 0;
    }
    return closesocket(s);
}

fn hx_proxy_connect(s: u64, host: ptr<u8>, port: u16) -> i32 {
    var req: [u8; 512] = [0];
    var rp: ptr<u8> = null;
    unsafe { rp = &mut req[0] as ptr<u8>; }
    let n: i32 = sprintf(rp, "CONNECT %s:%u HTTP/1.1\r\nHost: %s:%u\r\nProxy-Connection: keep-alive\r\n\r\n", host, port as u32, host, port as u32);
    if (n <= 0) {
        return HX_ERR;
    }
    let sent: i64 = hx_send(s, rp, n as i64);
    if (sent != n as i64) {
        return HX_ERR;
    }

    var resp: [u8; 1024] = [0];
    var sp: ptr<u8> = null;
    unsafe { sp = &mut resp[0] as ptr<u8>; }
    let got: i64 = hx_read_until(s, sp, 1023, 13, 10, 13, 10);
    if (got <= 0) {
        return HX_ERR;
    }
    var code: i32 = 0;
    unsafe {
        if (got >= 12) {
            let c0: u8 = resp[9];
            let c1: u8 = resp[10];
            let c2: u8 = resp[11];
            code = ((c0 - 48) as i32) * 100 + ((c1 - 48) as i32) * 10 + ((c2 - 48) as i32);
        }
    }
    if (code != 200) {
        return HX_ERR;
    }
    return 0;
}
