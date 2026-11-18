fn lsp_session_build(out: &mut LspBuf) {
    var b: LspBuf = lsp_buf_new(256);
    lsp_buf_puts(&mut b, "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}");
    lsp_frame_into(out, &b);
    lsp_buf_clear(&mut b);
    lsp_buf_puts(&mut b, "{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":{}}");
    lsp_frame_into(out, &b);
    lsp_buf_clear(&mut b);
    lsp_buf_puts(&mut b, "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file:///t.rsx\",\"languageId\":\"rsharp\",\"version\":1,\"text\":\"fn main() {\\n    let x = (1;\\n}\\n\"}}}");
    lsp_frame_into(out, &b);
    lsp_buf_clear(&mut b);
    lsp_buf_puts(&mut b, "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"textDocument/hover\",\"params\":{\"textDocument\":{\"uri\":\"file:///t.rsx\"},\"position\":{\"line\":0,\"character\":1}}}");
    lsp_frame_into(out, &b);
    lsp_buf_clear(&mut b);
    lsp_buf_puts(&mut b, "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"foo/bar\",\"params\":{}}");
    lsp_frame_into(out, &b);
    lsp_buf_clear(&mut b);
    lsp_buf_puts(&mut b, "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"shutdown\"}");
    lsp_frame_into(out, &b);
    lsp_buf_clear(&mut b);
    lsp_buf_puts(&mut b, "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}");
    lsp_frame_into(out, &b);
    lsp_buf_free(&mut b);
}

fn lsp_session_run(out: &mut LspBuf) -> i32 {
    var srv: LspSrv = lsp_srv_new();
    srv.capture = 1;
    var inb: LspBuf = lsp_buf_new(1024);
    lsp_session_build(&mut inb);
    var r: LspReader = lsp_reader_from_mem(inb.p, inb.len);
    let code: i32 = lsp_serve(&mut srv, &mut r);
    lsp_buf_put(out, srv.out.p, srv.out.len);
    lsp_reader_free(&mut r);
    lsp_buf_free(&mut inb);
    lsp_srv_free(&mut srv);
    return code;
}
