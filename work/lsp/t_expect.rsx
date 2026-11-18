include "../../modules/lsp/lsp_win.rsx";
include "session.rsx";

fn main() -> i32 {
    var b: LspBuf = lsp_buf_new(1024);
    let code: i32 = lsp_session_run(&mut b);
    let ok: i32 = lsp_write(b.p, b.len);
    lsp_buf_free(&mut b);
    if (code != 0 || ok == 0) {
        return 1;
    }
    return 0;
}
