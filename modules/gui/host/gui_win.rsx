extern "user32" fn RegisterClassExA(cls: ptr<u8>) -> u16;
extern "user32" fn CreateWindowExA(ex: u32, cls: ptr<u8>, title: ptr<u8>, style: u32,
                                   x: i32, y: i32, w: i32, h: i32, parent: ptr<u8>,
                                   menu: ptr<u8>, inst: ptr<u8>, param: ptr<u8>) -> ptr<u8>;
extern "user32" fn DestroyWindow(h: ptr<u8>) -> i32;
extern "user32" fn ShowWindow(h: ptr<u8>, cmd: i32) -> i32;
extern "user32" fn UpdateWindow(h: ptr<u8>) -> i32;
extern "user32" fn GetMessageA(msg: ptr<u8>, h: ptr<u8>, lo: u32, hi: u32) -> i32;
extern "user32" fn TranslateMessage(msg: ptr<u8>) -> i32;
extern "user32" fn DispatchMessageA(msg: ptr<u8>) -> ptr<u8>;
extern "user32" fn DefWindowProcA(h: ptr<u8>, m: u32, wp: u64, lp: i64) -> i64;
extern "user32" fn PostQuitMessage(code: i32);
extern "user32" fn SetTimer(h: ptr<u8>, id: u64, ms: u32, proc: ptr<u8>) -> u64;
extern "user32" fn KillTimer(h: ptr<u8>, id: u64) -> i32;
extern "user32" fn BeginPaint(h: ptr<u8>, ps: ptr<u8>) -> ptr<u8>;
extern "user32" fn EndPaint(h: ptr<u8>, ps: ptr<u8>) -> i32;
extern "user32" fn GetClientRect(h: ptr<u8>, r: ptr<u8>) -> i32;
extern "user32" fn InvalidateRect(h: ptr<u8>, r: ptr<u8>, erase: i32) -> i32;
extern "user32" fn AdjustWindowRectEx(r: ptr<u8>, style: u32, menu: i32, ex: u32) -> i32;
extern "user32" fn SetWindowLongPtrA(h: ptr<u8>, idx: i32, v: i64) -> i64;
extern "user32" fn GetWindowLongPtrA(h: ptr<u8>, idx: i32) -> i64;
extern "user32" fn LoadCursorA(inst: ptr<u8>, name: ptr<u8>) -> ptr<u8>;
extern "user32" fn SetCursor(c: ptr<u8>) -> ptr<u8>;
extern "gdi32" fn StretchDIBits(dc: ptr<u8>, xd: i32, yd: i32, wd: i32, hd: i32,
                                xs: i32, ys: i32, ws: i32, hs: i32, bits: ptr<u8>,
                                bmi: ptr<u8>, usage: u32, rop: u32) -> i32;
extern "kernel32" fn GetModuleHandleA(name: ptr<u8>) -> ptr<u8>;

const GW_WM_DESTROY: u32 = 2;
const GW_WM_CLOSE: u32 = 16;
const GW_WM_PAINT: u32 = 15;
const GW_WM_ERASEBKGND: u32 = 20;
const GW_WM_SETCURSOR: u32 = 32;
const GW_WM_KEYDOWN: u32 = 256;
const GW_WM_CHAR: u32 = 258;
const GW_WM_TIMER: u32 = 275;
const GW_WM_MOUSEMOVE: u32 = 512;
const GW_WM_LBUTTONDOWN: u32 = 513;
const GW_WM_LBUTTONUP: u32 = 514;
const GW_WM_MOUSEWHEEL: u32 = 522;

const GW_WS_CAPTION: u32 = 0x00C00000;
const GW_WS_SYSMENU: u32 = 0x00080000;
const GW_WS_MINIMIZEBOX: u32 = 0x00020000;
const GW_SW_SHOW: i32 = 5;
const GW_USERDATA: i32 = -21;
const GW_ROP: u32 = 0x00CC0020;

struct GWndClass {
    cbSize: u32,
    style: u32,
    proc: ptr<u8>,
    clsExtra: i32,
    wndExtra: i32,
    inst: ptr<u8>,
    icon: ptr<u8>,
    cursor: ptr<u8>,
    brush: ptr<u8>,
    menuName: ptr<u8>,
    className: ptr<u8>,
    iconSm: ptr<u8>
}

struct GMsg {
    hwnd: ptr<u8>,
    message: u32,
    wParam: u64,
    lParam: i64,
    stamp: u32,
    x: i32,
    y: i32,
    priv: u32
}

struct GPaint {
    dc: ptr<u8>,
    erase: i32,
    left: i32,
    top: i32,
    right: i32,
    bottom: i32,
    restore: i32,
    incUpdate: i32,
    reserved: [u8; 32]
}

struct GBi {
    size: u32,
    width: i32,
    height: i32,
    planes: u16,
    bits: u16,
    comp: u32,
    sizeImage: u32,
    xppm: i32,
    yppm: i32,
    clrUsed: u32,
    clrImportant: u32
}

struct GWinRect {
    left: i32,
    top: i32,
    right: i32,
    bottom: i32
}

struct GWin {
    app: ptr<GApp>,
    hwnd: ptr<u8>,
    hook: fn(i64, i64) -> void,
    tick_ms: i64,
    quit_ms: i64,
    frame: i64,
    live: i64
}

fn gw_x(lp: i64) -> i64 {
    return lp & 65535;
}

fn gw_y(lp: i64) -> i64 {
    return (lp >> 16) & 65535;
}

fn gw_blit(gw: ptr<GWin>, dc: ptr<u8>) {
    var ap: ptr<GApp> = null;
    var bi: GBi = zero(GBi);
    var r: GWinRect = zero(GWinRect);
    unsafe { ap = gw.app; }
    unsafe { gui_render(&mut *ap); }
    var w: i32 = 0;
    var h: i32 = 0;
    unsafe {
        GetClientRect(gw.hwnd, &mut r as ptr<u8>);
        w = r.right - r.left;
        h = r.bottom - r.top;
    }
    if (w <= 0 || h <= 0) {
        return;
    }
    bi.size = 40;
    bi.width = w;
    bi.height = 0 - h;
    bi.planes = 1;
    bi.bits = 32;
    bi.comp = 0;
    var bmp: ptr<u8> = null;
    var bip: ptr<u8> = null;
    unsafe {
        bmp = ap.px;
        bip = &mut bi as ptr<u8>;
    }
    StretchDIBits(dc, 0, 0, w, h, 0, 0, w, h, bmp, bip, 0, GW_ROP);
}

fn gw_tick(gw: ptr<GWin>) {
    var ap: ptr<GApp> = null;
    var hk: fn(i64, i64) -> void = gui_win_noop;
    var n: i64 = 0;
    unsafe {
        ap = gw.app;
        hk = gw.hook;
        gw.frame += 1;
        n = gw.frame;
    }
    unsafe { gui_timer(&mut *ap); }
    if ((hk as i64) != 0) {
        hk(ap as i64, n);
    }
    var q: i64 = 0;
    unsafe { q = gw.quit_ms; }
    if (q > 0) {
        var elapsed: i64 = 0;
        unsafe { elapsed = gw.frame * gw.tick_ms; }
        if (elapsed >= q) {
            unsafe { DestroyWindow(gw.hwnd); }
        }
    }
}

extern "C" fn gui_win_proc(h: ptr<u8>, m: u32, wp: u64, lp: i64) -> i64 {
    let raw: i64 = GetWindowLongPtrA(h, GW_USERDATA);
    if (m == GW_WM_PAINT) {
        var ps: GPaint = zero(GPaint);
        var psp: ptr<u8> = null;
        unsafe { psp = &mut ps as ptr<u8>; }
        let dc: ptr<u8> = BeginPaint(h, psp);
        if (raw != 0) {
            let gw: ptr<GWin> = raw as ptr<GWin>;
            gw_blit(gw, dc);
        }
        EndPaint(h, psp);
        return 0;
    }
    if (m == GW_WM_DESTROY) {
        PostQuitMessage(0);
        return 0;
    }
    if (m == GW_WM_CLOSE) {
        DestroyWindow(h);
        return 0;
    }
    if (raw == 0) {
        return DefWindowProcA(h, m, wp, lp);
    }
    let gw: ptr<GWin> = raw as ptr<GWin>;
    var ap: ptr<GApp> = null;
    unsafe { ap = gw.app; }
    if (m == GW_WM_TIMER) {
        gw_tick(gw);
        InvalidateRect(h, null, 0);
        return 0;
    }
    if (m == GW_WM_ERASEBKGND) {
        return 1;
    }
    if (m == GW_WM_SETCURSOR) {
        SetCursor(LoadCursorA(null, 32512 as ptr<u8>));
        return 1;
    }
    if (m == GW_WM_MOUSEMOVE) {
        unsafe { gui_mouse_move(&mut *ap, gw_x(lp), gw_y(lp)); }
        InvalidateRect(h, null, 0);
        return 0;
    }
    if (m == GW_WM_LBUTTONDOWN) {
        unsafe { gui_mouse_down(&mut *ap, gw_x(lp), gw_y(lp)); }
        InvalidateRect(h, null, 0);
        return 0;
    }
    if (m == GW_WM_LBUTTONUP) {
        unsafe { gui_mouse_up(&mut *ap, gw_x(lp), gw_y(lp)); }
        InvalidateRect(h, null, 0);
        return 0;
    }
    if (m == GW_WM_MOUSEWHEEL) {
        var d: i64 = ((wp >> 16) & 65535) as i64;
        if (d >= 32768) {
            d = d - 65536;
        }
        if (d > 0) {
            unsafe { gui_wheel(&mut *ap, 1); }
        } else if (d < 0) {
            unsafe { gui_wheel(&mut *ap, -1); }
        }
        InvalidateRect(h, null, 0);
        return 0;
    }
    if (m == GW_WM_KEYDOWN) {
        let vk: i64 = (wp & 255) as i64;
        if (vk == VK_BACK || vk == VK_TAB || vk == VK_RETURN || vk == VK_ESCAPE
            || vk == VK_LEFT || vk == VK_RIGHT || vk == VK_UP || vk == VK_DOWN
            || vk == VK_HOME || vk == VK_END || vk == VK_DELETE || vk == VK_SPACE) {
            unsafe { gui_key(&mut *ap, vk, 0); }
            InvalidateRect(h, null, 0);
            return 0;
        }
        return DefWindowProcA(h, m, wp, lp);
    }
    if (m == GW_WM_CHAR) {
        let ch: i64 = (wp & 65535) as i64;
        if (ch >= 32 && ch <= 126) {
            unsafe { gui_key(&mut *ap, 0, ch); }
            InvalidateRect(h, null, 0);
        }
        return 0;
    }
    return DefWindowProcA(h, m, wp, lp);
}

fn gui_win_open(app: &mut GApp, title: ptr<u8>) -> i64 {
    let inst: ptr<u8> = GetModuleHandleA(null);
    var wc: GWndClass = zero(GWndClass);
    wc.cbSize = sizeof(GWndClass) as u32;
    wc.style = 3;
    wc.proc = gui_win_proc as ptr<u8>;
    wc.inst = inst;
    wc.cursor = LoadCursorA(null, 32512 as ptr<u8>);
    wc.className = "RSharpGuiWindow";
    var wcp: ptr<u8> = null;
    unsafe { wcp = &mut wc as ptr<u8>; }
    RegisterClassExA(wcp);
    let style: u32 = GW_WS_CAPTION | GW_WS_SYSMENU | GW_WS_MINIMIZEBOX;
    var r: GWinRect = zero(GWinRect);
    r.right = app.w as i32;
    r.bottom = app.h as i32;
    var rp: ptr<u8> = null;
    unsafe { rp = &mut r as ptr<u8>; }
    AdjustWindowRectEx(rp, style, 0, 0);
    let h: ptr<u8> = CreateWindowExA(0, "RSharpGuiWindow", title, style,
                                     90, 60, r.right - r.left, r.bottom - r.top,
                                     null, null, inst, null);
    if (h == null) {
        return 0;
    }
    ShowWindow(h, GW_SW_SHOW);
    UpdateWindow(h);
    return h as i64;
}

fn gui_win_run_hook(app: &mut GApp, title: ptr<u8>, tick_ms: i64, quit_ms: i64,
                    hook: fn(i64, i64) -> void) -> i32 {
    let h: i64 = gui_win_open(app, title);
    if (h == 0) {
        return -1;
    }
    let hwnd: ptr<u8> = h as ptr<u8>;
    var ap: ptr<GApp> = null;
    unsafe { ap = app as ptr<GApp>; }
    var gw: GWin = zero(GWin);
    gw.app = ap;
    gw.hwnd = hwnd;
    gw.hook = hook;
    gw.tick_ms = tick_ms;
    gw.quit_ms = quit_ms;
    gw.frame = 0;
    gw.live = 1;
    var gwp: ptr<GWin> = null;
    unsafe { gwp = &mut gw as ptr<GWin>; }
    SetWindowLongPtrA(hwnd, GW_USERDATA, gwp as i64);
    if (tick_ms > 0) {
        SetTimer(hwnd, 1, tick_ms as u32, null);
    }
    InvalidateRect(hwnd, null, 0);
    var msg: GMsg = zero(GMsg);
    var mp: ptr<u8> = null;
    unsafe { mp = &mut msg as ptr<u8>; }
    while (true) {
        let got: i32 = GetMessageA(mp, null, 0, 0);
        if (got <= 0) {
            break;
        }
        TranslateMessage(mp);
        DispatchMessageA(mp);
    }
    if (tick_ms > 0) {
        KillTimer(hwnd, 1);
    }
    return 0;
}

fn gui_win_noop(a: i64, b: i64) {
}

fn gui_win_run(app: &mut GApp, title: ptr<u8>) -> i32 {
    return gui_win_run_hook(app, title, 0, 0, gui_win_noop);
}
