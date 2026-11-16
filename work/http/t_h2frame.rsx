include "../../modules/http/rt.rsx";
include "../../modules/http/transport_win.rsx";
include "../../modules/http/http2.rsx";

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

fn part_basic(t: &mut Tally) {
    var pre: HxBuf = hxbuf_new(64);
    var fr: HxBuf = hxbuf_new(256);
    let prc: i32 = h2_put_preface(&mut pre);
    let hrc: i32 = h2_put_headers(&mut fr, 1, pre.p, 5, 1);
    t_ok(t, "preface bytes", prc == H2_OK && pre.len == H2_PREFACE);
    t_ok(t, "headers frame len", hrc == H2_OK && fr.len == 14);

    var hh: H2Hdr = zero(H2Hdr);
    let hpr: i32 = h2_hdr_parse(fr.p, fr.len, &mut hh);
    t_ok(t, "parse header", hpr == H2_OK && hh.len == 5 && hh.stream == 1);
    t_ok(t, "flags end_headers+end_stream", hh.flags == 5);
    t_ok(t, "type headers", hh.ty == H2_HEADERS);

    var hbody: H2Body = zero(H2Body);
    let pbr: i32 = h2_payload(fr.p, fr.len, &mut hh, &mut hbody);
    t_ok(t, "payload plain", pbr == H2_OK && hbody.off == 9 && hbody.len == 5);

    var need: H2Hdr = zero(H2Hdr);
    t_ok(t, "short header needs more", h2_hdr_parse(fr.p, 5, &mut need) == H2_NEED);
    t_ok(t, "short body needs more", h2_hdr_parse(fr.p, 12, &mut need) == H2_NEED);

    var small: HxBuf = hxbuf_new(128);
    let bp: ptr<u8> = pre.p;
    h2_put_headers_split(&mut small, 9, bp, 20, 1, 64);
    var smh: H2Hdr = zero(H2Hdr);
    h2_hdr_parse(small.p, small.len, &mut smh);
    t_ok(t, "single headers fits", small.len == 29 && smh.flags == 5);

    hxbuf_free(&mut small);
    hxbuf_free(&mut fr);
    hxbuf_free(&mut pre);
}

fn part_padding(t: &mut Tally) {
    var pad: HxBuf = hxbuf_new(64);
    hxbuf_putc(&mut pad, 3);
    hxbuf_putc(&mut pad, 7);
    hxbuf_putc(&mut pad, 8);
    hxbuf_putc(&mut pad, 9);
    hxbuf_putc(&mut pad, 0);
    hxbuf_putc(&mut pad, 0);
    hxbuf_putc(&mut pad, 0);
    hxbuf_putc(&mut pad, 0);

    var padf: HxBuf = hxbuf_new(64);
    let pfc: i32 = h2_put_frame(&mut padf, H2_DATA, H2_F_PADDED, 3, pad.p, pad.len);

    var ph: H2Hdr = zero(H2Hdr);
    var pb: H2Body = zero(H2Body);
    let pfr: i32 = h2_hdr_parse(padf.p, padf.len, &mut ph);
    let pfr2: i32 = h2_payload(padf.p, padf.len, &mut ph, &mut pb);
    t_ok(t, "padded data frame", pfc == H2_OK && pfr == H2_OK && pfr2 == H2_OK);
    t_ok(t, "padding stripped", pb.len == 4 && pb.off == 10);

    var hb2: HxBuf = hxbuf_new(64);
    hxbuf_putc(&mut hb2, 0);
    hxbuf_putc(&mut hb2, 0);
    hxbuf_putc(&mut hb2, 0);
    hxbuf_putc(&mut hb2, 8);
    hxbuf_putc(&mut hb2, 200);
    hxbuf_putc(&mut hb2, 1);
    hxbuf_putc(&mut hb2, 2);
    hxbuf_putc(&mut hb2, 3);

    var prf: HxBuf = hxbuf_new(64);
    let p2c: i32 = h2_put_frame(&mut prf, H2_HEADERS, H2_F_PRIORITY, 5, hb2.p, hb2.len);
    var p2h: H2Hdr = zero(H2Hdr);
    var p2b: H2Body = zero(H2Body);
    let p2r: i32 = h2_hdr_parse(prf.p, prf.len, &mut p2h);
    let p2r2: i32 = h2_hblock(prf.p, prf.len, &mut p2h, &mut p2b);
    t_ok(t, "priority block strip", p2c == H2_OK && p2r == H2_OK && p2r2 == H2_OK);
    t_ok(t, "priority offsets", p2b.len == 3 && p2b.off == 14);

    hxbuf_free(&mut prf);
    hxbuf_free(&mut hb2);
    hxbuf_free(&mut padf);
    hxbuf_free(&mut pad);
}

fn part_control(t: &mut Tally) {
    var st: HxBuf = hxbuf_new(128);
    let stc: i32 = h2_put_settings(&mut st, 4096, 0, 65535, 16384);
    t_ok(t, "settings frame size", stc == H2_OK && st.len == 33);

    var sth: H2Hdr = zero(H2Hdr);
    let strp: i32 = h2_hdr_parse(st.p, st.len, &mut sth);
    var sb: H2Body = zero(H2Body);
    let str2: i32 = h2_payload(st.p, st.len, &mut sth, &mut sb);

    var pl: ptr<u8> = null;
    unsafe { pl = st.p + sb.off; }
    var sout: [i64; 8] = [0, 0, 0, 0, 0, 0, 0, 0];
    let sr: i32 = h2_settings_read(pl, sb.len, &mut sout);
    t_ok(t, "settings parse", strp == H2_OK && str2 == H2_OK && sr == H2_OK);
    t_ok(t, "settings values", sout[1] == 0 && sout[3] == 65535 && sout[4] == 16384);
    t_ok(t, "settings table size", sout[0] == 4096);

    var ack: HxBuf = hxbuf_new(32);
    h2_put_settings_ack(&mut ack);
    var ah: H2Hdr = zero(H2Hdr);
    h2_hdr_parse(ack.p, ack.len, &mut ah);
    t_ok(t, "settings ack", ack.len == 9 && ah.ty == H2_SETTINGS && ah.flags == H2_F_ACK && ah.stream == 0);

    var ctl: HxBuf = hxbuf_new(256);
    let w1: i32 = h2_put_window(&mut ctl, 3, 1024);
    let g1: i32 = h2_put_goaway(&mut ctl, 5, H2_E_NO_ERROR);
    let r1: i32 = h2_put_rst(&mut ctl, 7, H2_E_CANCEL);
    t_ok(t, "control frames size", w1 == H2_OK && g1 == H2_OK && r1 == H2_OK && ctl.len == 43);

    var gp: ptr<u8> = null;
    unsafe { gp = ctl.p + 13; }
    var ga: H2Hdr = zero(H2Hdr);
    h2_hdr_parse(gp, ctl.len - 13, &mut ga);
    let last: i64 = h2_rd32(gp, 9);
    let code: i64 = h2_rd32(gp, 13);
    t_ok(t, "goaway body", ga.ty == H2_GOAWAY && ga.len == 8 && last == 5 && code == H2_E_NO_ERROR);

    t_ok(t, "stream frame classes", h2_is_stream_frame(H2_DATA) == 1 && h2_is_stream_frame(H2_PING) == 0);

    hxbuf_free(&mut ctl);
    hxbuf_free(&mut ack);
    hxbuf_free(&mut st);
}

fn part_split(t: &mut Tally) {
    var split: HxBuf = hxbuf_new(512);
    var blk: [u8; 100] = [0];
    var bp: ptr<u8> = null;
    unsafe { bp = &mut blk[0] as ptr<u8>; }
    let spc: i32 = h2_put_headers_split(&mut split, 7, bp, 100, 0, 40);
    t_ok(t, "split headers size", spc == H2_OK && split.len == 127);

    var sh1: H2Hdr = zero(H2Hdr);
    var sh2: H2Hdr = zero(H2Hdr);
    var sh3: H2Hdr = zero(H2Hdr);
    h2_hdr_parse(split.p, split.len, &mut sh1);
    var o2: ptr<u8> = null;
    var o3: ptr<u8> = null;
    unsafe {
        o2 = split.p + 49;
        o3 = split.p + 98;
    }
    let r2: i32 = h2_hdr_parse(o2, split.len - 49, &mut sh2);
    let r3: i32 = h2_hdr_parse(o3, split.len - 98, &mut sh3);
    t_ok(t, "split first frame", sh1.ty == H2_HEADERS && sh1.len == 40 && sh1.flags == 0);
    t_ok(t, "split middle frame", r2 == H2_OK && sh2.ty == H2_CONT && sh2.len == 40);
    t_ok(t, "split last frame", r3 == H2_OK && sh3.ty == H2_CONT && sh3.len == 20 && sh3.flags == H2_F_END_HEADERS);

    hxbuf_free(&mut split);
}

fn main() -> i32 {
    var t: Tally = zero(Tally);
    part_basic(&mut t);
    part_padding(&mut t);
    part_control(&mut t);
    part_split(&mut t);
    printf("h2frame_passed=%lld of %lld\n", t.pass, t.total);
    fflush(null);
    if (t.pass != t.total) {
        return 3;
    }
    return 0;
}
