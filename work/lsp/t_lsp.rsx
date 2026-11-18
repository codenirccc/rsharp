include "../../modules/lsp/lsp_win.rsx";
include "session.rsx";

extern fn printf(fmt: ptr<u8>, ...) -> i32;

fn t_json() -> i32 {
    var fails: i32 = 0;
    let src: ptr<u8> = "{\"a\":1,\"b\":[true,false,null],\"c\":{\"d\":\"x\\u00e9\",\"e\":\"\\ud83d\\ude00\"},\"f\":-12}";
    var jp: LspJp = lsp_json_parse(src, strlen(src) as i64);
    if (jp.ok == 0) {
        printf("json: parse rejected valid input\n");
        lsp_json_free(&mut jp);
        return 1;
    }
    let nodes: ptr<LspJv> = jp.nodes;
    if (lsp_jv_int(nodes, lsp_jv_get(nodes, 1, "a")) != 1) {
        printf("json: int member\n");
        fails += 1;
    }
    if (lsp_jv_int(nodes, lsp_jv_get(nodes, 1, "f")) != -12) {
        printf("json: negative member\n");
        fails += 1;
    }
    let b: i64 = lsp_jv_get(nodes, 1, "b");
    if (lsp_jv_count(nodes, b) != 3) {
        printf("json: array count\n");
        fails += 1;
    }
    if (lsp_jv_kind(nodes, lsp_jv_at(nodes, b, 0)) != LSP_JV_BOOL) {
        printf("json: array element\n");
        fails += 1;
    }
    let d: i64 = lsp_jv_get(nodes, lsp_jv_get(nodes, 1, "c"), "d");
    if (lsp_jv_slen(nodes, d) != 3) {
        printf("json: escape length\n");
        fails += 1;
    } else if (lsp_buf_byte(lsp_jv_str(nodes, d), 1) != 0xC3 || lsp_buf_byte(lsp_jv_str(nodes, d), 2) != 0xA9) {
        printf("json: escape bytes\n");
        fails += 1;
    }
    let e: i64 = lsp_jv_get(nodes, lsp_jv_get(nodes, 1, "c"), "e");
    if (lsp_jv_slen(nodes, e) != 4) {
        printf("json: surrogate length\n");
        fails += 1;
    } else if (lsp_buf_byte(lsp_jv_str(nodes, e), 0) != 0xF0 || lsp_buf_byte(lsp_jv_str(nodes, e), 3) != 0x80) {
        printf("json: surrogate bytes\n");
        fails += 1;
    }
    lsp_json_free(&mut jp);
    var bad: LspJp = lsp_json_parse("{\"a\":]" as ptr<u8>, 6);
    if (bad.ok != 0) {
        printf("json: broken input accepted\n");
        fails += 1;
    }
    lsp_json_free(&mut bad);
    return fails;
}

fn t_frame() -> i32 {
    var hdr: [u8; 40] = [0];
    var hp: ptr<u8> = null;
    unsafe { hp = &mut hdr[0] as ptr<u8>; }
    let hn: i64 = lsp_frame_header(hp, 2);
    if (lsp_eqn(hp, hn, "Content-Length: 2\r\n\r\n", 21) == 0) {
        printf("frame: header bytes\n");
        return 1;
    }
    let inb: ptr<u8> = "Content-Length: 2\r\n\r\n{}Content-Length: 2\r\n\r\n[]";
    var r: LspReader = lsp_reader_from_mem(inb, strlen(inb) as i64);
    let f1: LspFrame = lsp_read_frame(&mut r);
    if (f1.ok != 1 || f1.len != 2 || lsp_eqn(f1.p, 2, "{}", 2) == 0) {
        printf("frame: first body\n");
        return 1;
    }
    free(f1.p);
    let f2: LspFrame = lsp_read_frame(&mut r);
    if (f2.ok != 1 || f2.len != 2 || lsp_eqn(f2.p, 2, "[]", 2) == 0) {
        printf("frame: second body\n");
        return 1;
    }
    free(f2.p);
    let f3: LspFrame = lsp_read_frame(&mut r);
    if (f3.ok != 0) {
        printf("frame: eof\n");
        return 1;
    }
    lsp_reader_free(&mut r);
    return 0;
}

fn t_scan_case(text: ptr<u8>, want_msg: ptr<u8>, want_line: i64, want_col: i64) -> i32 {
    var sc: LspScanOut = zero(LspScanOut);
    let n: i32 = lsp_scan(text, strlen(text) as i64, &mut sc);
    if (n == 0) {
        printf("scan: no diagnostics for %s\n", text);
        return 1;
    }
    var k: i64 = 0;
    while (k < n as i64) {
        if (lsp_eqn(sc.d[k].msg, strlen(sc.d[k].msg) as i64, want_msg, strlen(want_msg) as i64) == 1) {
            if (sc.d[k].sl == want_line && sc.d[k].sc == want_col) {
                return 0;
            }
            printf("scan: position for %s\n", want_msg);
            return 1;
        }
        k += 1;
    }
    printf("scan: message for %s\n", text);
    return 1;
}

fn t_scan() -> i32 {
    var fails: i32 = 0;
    fails += t_scan_case("fn f() {\n    let s = \"abc;\n}\n" as ptr<u8>, "unterminated string literal" as ptr<u8>, 1, 12);
    fails += t_scan_case("fn f(] {)\n" as ptr<u8>, "mismatched ']'" as ptr<u8>, 0, 5);
    fails += t_scan_case("fn f() {\n" as ptr<u8>, "unclosed '{'" as ptr<u8>, 0, 7);
    fails += t_scan_case(")\n" as ptr<u8>, "unmatched ')'" as ptr<u8>, 0, 0);
    fails += t_scan_case("/* open\n" as ptr<u8>, "unterminated block comment" as ptr<u8>, 0, 0);
    var sc: LspScanOut = zero(LspScanOut);
    let clean: ptr<u8> = "fn f(a: i32) -> i32 {\n    // ) not a bracket\n    let s = \"( {\";\n    return a;\n}\n";
    if (lsp_scan(clean, strlen(clean) as i64, &mut sc) != 0) {
        printf("scan: clean input reported %d\n", sc.n);
        fails += 1;
    }
    return fails;
}

fn t_check_frame(r: &mut LspReader, want: ptr<u8>) -> i32 {
    let f: LspFrame = lsp_read_frame(r);
    if (f.ok != 1) {
        printf("session: missing frame\n");
        return 1;
    }
    let n: i64 = strlen(want) as i64;
    if (f.len != n || lsp_eqn(f.p, f.len, want, n) == 0) {
        printf("session: frame body mismatch\n");
        printf("  got:  %s\n", f.p);
        printf("  want: %s\n", want);
        free(f.p);
        return 1;
    }
    free(f.p);
    return 0;
}

fn t_session() -> i32 {
    var out: LspBuf = lsp_buf_new(1024);
    let code: i32 = lsp_session_run(&mut out);
    if (code != 0) {
        printf("session: server exit %d\n", code);
        lsp_buf_free(&mut out);
        return 1;
    }
    var r: LspReader = lsp_reader_from_mem(out.p, out.len);
    var fails: i32 = 0;
    fails += t_check_frame(&mut r, "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"capabilities\":{\"textDocumentSync\":{\"openClose\":true,\"change\":1},\"hoverProvider\":true,\"positionEncoding\":\"utf-16\"},\"serverInfo\":{\"name\":\"rsharp\",\"version\":\"1.2\"}}}" as ptr<u8>);
    fails += t_check_frame(&mut r, "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/publishDiagnostics\",\"params\":{\"uri\":\"file:///t.rsx\",\"version\":1,\"diagnostics\":[{\"range\":{\"start\":{\"line\":2,\"character\":0},\"end\":{\"line\":2,\"character\":1}},\"severity\":1,\"source\":\"rsharp\",\"message\":\"mismatched '}'\"},{\"range\":{\"start\":{\"line\":0,\"character\":10},\"end\":{\"line\":0,\"character\":11}},\"severity\":1,\"source\":\"rsharp\",\"message\":\"unclosed '{'\"}]}}" as ptr<u8>);
    fails += t_check_frame(&mut r, "{\"jsonrpc\":\"2.0\",\"id\":3,\"result\":{\"contents\":{\"kind\":\"plaintext\",\"value\":\"fn declares a function; extern fn binds a system symbol at link time\"},\"range\":{\"start\":{\"line\":0,\"character\":0},\"end\":{\"line\":0,\"character\":2}}}}" as ptr<u8>);
    fails += t_check_frame(&mut r, "{\"jsonrpc\":\"2.0\",\"id\":4,\"error\":{\"code\":-32601,\"message\":\"method not found: foo/bar\"}}" as ptr<u8>);
    fails += t_check_frame(&mut r, "{\"jsonrpc\":\"2.0\",\"id\":5,\"result\":null}" as ptr<u8>);
    let extra: LspFrame = lsp_read_frame(&mut r);
    if (extra.ok == 1) {
        printf("session: extra frame\n");
        free(extra.p);
        fails += 1;
    }
    lsp_reader_free(&mut r);
    lsp_buf_free(&mut out);
    return fails;
}

fn t_exit_codes() -> i32 {
    var fails: i32 = 0;
    var s1: LspSrv = lsp_srv_new();
    var r1: LspReader = lsp_reader_from_mem("x" as ptr<u8>, 0);
    if (lsp_serve(&mut s1, &mut r1) != 0) {
        printf("exit: eof should be 0\n");
        fails += 1;
    }
    lsp_reader_free(&mut r1);
    lsp_srv_free(&mut s1);

    var body: LspBuf = lsp_buf_new(64);
    lsp_buf_puts(&mut body, "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}");
    var inb: LspBuf = lsp_buf_new(128);
    lsp_frame_into(&mut inb, &body);
    var s2: LspSrv = lsp_srv_new();
    var r2: LspReader = lsp_reader_from_mem(inb.p, inb.len);
    if (lsp_serve(&mut s2, &mut r2) != 1) {
        printf("exit: exit before shutdown should be 1\n");
        fails += 1;
    }
    lsp_reader_free(&mut r2);
    lsp_srv_free(&mut s2);
    lsp_buf_free(&mut inb);
    lsp_buf_free(&mut body);
    return fails;
}

fn main() -> i32 {
    var fails: i32 = 0;
    fails += t_json();
    fails += t_frame();
    fails += t_scan();
    fails += t_session();
    fails += t_exit_codes();
    if (fails == 0) {
        printf("lsp suite: ok\n");
        return 0;
    }
    return 1;
}
