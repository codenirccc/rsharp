include "../../modules/gui/gui_win.rsx";

extern fn printf(fmt: ptr<u8>, ...) -> i32;
extern "kernel32" fn GetTickCount64() -> u64;

fn main() -> i32 {
    var app: GApp = zero(GApp);
    if (gui_app_init(&mut app, 400, 300) != 0) {
        return 1;
    }
    let a: i64 = gui_add(&mut app, GK_LABEL, 0, "probe");
    gui_set_number(&mut app, a, 12);
    let h: i64 = gui_win_open(&mut app, "probe");
    printf("hwnd=%lld\n", h);
    if (h == 0) {
        return 2;
    }
    let t0: u64 = GetTickCount64();
    var seen: i64 = 0;
    var msg: GMsg = zero(GMsg);
    var mp: ptr<u8> = null;
    unsafe { mp = &mut msg as ptr<u8>; }
    while (true) {
        let got: i32 = GetMessageA(mp, null, 0, 0);
        let now: u64 = GetTickCount64();
        if (got <= 0) {
            printf("got=%d dt=%lld\n", got, (now - t0) as i64);
            break;
        }
        if (seen < 12) {
            printf("msg=%u wp=%lld\n", msg.message, msg.wParam as i64);
            seen += 1;
        }
        TranslateMessage(mp);
        DispatchMessageA(mp);
        if ((now - t0) > 1500) {
            printf("timeout exit\n");
            return 0;
        }
    }
    return 0;
}
