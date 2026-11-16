extern "objc" fn objc_getClass(name: ptr<u8>) -> ptr<u8>;
extern "objc" fn objc_allocateClassPair(sup: ptr<u8>, name: ptr<u8>, extra: u64) -> ptr<u8>;
extern "objc" fn objc_registerClassPair(cls: ptr<u8>);
extern "objc" fn class_addMethod(cls: ptr<u8>, sel: ptr<u8>, imp: ptr<u8>, types: ptr<u8>) -> i32;
extern "objc" fn sel_registerName(name: ptr<u8>) -> ptr<u8>;
extern "objc" fn objc_msgSend(p0: ptr<u8>, p1: ptr<u8>, ...) -> ptr<u8>;
extern "coregraphics" fn CGColorSpaceCreateDeviceRGB() -> ptr<u8>;
extern "coregraphics" fn CGColorSpaceRelease(cs: ptr<u8>);
extern "coregraphics" fn CGBitmapContextCreate(data: ptr<u8>, w: u64, h: u64, bpc: u64,
                                               bpr: u64, cs: ptr<u8>, info: u32) -> ptr<u8>;
extern "coregraphics" fn CGBitmapContextCreateImage(ctx: ptr<u8>) -> ptr<u8>;
extern "coregraphics" fn CGImageRelease(img: ptr<u8>);
extern "coregraphics" fn CGContextRelease(ctx: ptr<u8>);
extern "system" fn dlopen(path: ptr<u8>, mode: i32) -> ptr<u8>;

const GM_ACTIVATION_REGULAR: i64 = 0;
const GM_RTLD_NOW: i32 = 2;
const GM_STYLE: i64 = 7;
const GM_LAYER: i64 = 2;
const GM_BITMAP_INFO: u32 = 8198;

struct GMacRect {
    x: f64,
    y: f64,
    w: f64,
    h: f64
}

struct GMacPoint {
    x: f64,
    y: f64
}

struct GMac {
    app: ptr<GApp>,
    win: ptr<u8>,
    view: ptr<u8>,
    layer: ptr<u8>,
    ctx: ptr<u8>,
    hook: fn(i64, i64) -> void,
    tick_ms: i64,
    quit_ms: i64,
    frame: i64,
    live: i64
}

fn gui_mac_noop(a: i64, b: i64) {
}

fn gm_cls(name: ptr<u8>) -> ptr<u8> {
    return objc_getClass(name);
}

fn gm_sel(name: ptr<u8>) -> ptr<u8> {
    return sel_registerName(name);
}

fn gm_s(o: ptr<u8>, name: ptr<u8>) -> ptr<u8> {
    return objc_msgSend(o, sel_registerName(name));
}

fn gm_s1(o: ptr<u8>, name: ptr<u8>, a: i64) -> ptr<u8> {
    return objc_msgSend(o, sel_registerName(name), a);
}

fn gm_s2(o: ptr<u8>, name: ptr<u8>, a: i64, b: i64) -> ptr<u8> {
    return objc_msgSend(o, sel_registerName(name), a, b);
}

fn gm_s3(o: ptr<u8>, name: ptr<u8>, a: i64, b: i64, c: i64) -> ptr<u8> {
    return objc_msgSend(o, sel_registerName(name), a, b, c);
}

fn gm_str(s: ptr<u8>) -> ptr<u8> {
    return gm_s1(gm_cls("NSString"), "stringWithUTF8String:", s as i64);
}

fn gm_invoke(obj: ptr<u8>, name: ptr<u8>, out: ptr<u8>) -> i32 {
    let m: ptr<u8> = sel_registerName(name);
    let sig: ptr<u8> = gm_s1(obj, "methodSignatureForSelector:", m as i64);
    if ((sig as i64) == 0) {
        return -1;
    }
    let inv: ptr<u8> = gm_s1(gm_cls("NSInvocation"), "invocationWithMethodSignature:", sig as i64);
    if ((inv as i64) == 0) {
        return -1;
    }
    gm_s1(inv, "setTarget:", obj as i64);
    gm_s1(inv, "setSelector:", m as i64);
    gm_s(inv, "invoke");
    gm_s1(inv, "getReturnValue:", out as i64);
    return 0;
}

fn gm_state(view: ptr<u8>) -> ptr<GMac> {
    let t: i64 = gm_s(view, "tag") as i64;
    return t as ptr<GMac>;
}

fn gm_app_of(gm: ptr<GMac>) -> ptr<GApp> {
    var ap: ptr<GApp> = null;
    unsafe { ap = gm.app; }
    return ap;
}

fn gm_point(ev: ptr<u8>, out: ptr<u8>) -> i32 {
    return gm_invoke(ev, "locationInWindow", out);
}

fn gm_double(ev: ptr<u8>, name: ptr<u8>, out: ptr<u8>) -> i32 {
    return gm_invoke(ev, name, out);
}

fn gm_make_ctx(app: &mut GApp) -> ptr<u8> {
    var px: ptr<u8> = null;
    var w: i64 = 0;
    var h: i64 = 0;
    unsafe {
        px = app.px;
        w = app.w;
        h = app.h;
    }
    if ((px as i64) == 0 || w <= 0 || h <= 0) {
        return null;
    }
    let cs: ptr<u8> = CGColorSpaceCreateDeviceRGB();
    if ((cs as i64) == 0) {
        return null;
    }
    let ctx: ptr<u8> = CGBitmapContextCreate(px, w as u64, h as u64, 8, (w * 4) as u64,
                                             cs, GM_BITMAP_INFO);
    CGColorSpaceRelease(cs);
    return ctx;
}

fn gm_blit(gm: ptr<GMac>) {
    let ap: ptr<GApp> = gm_app_of(gm);
    var layer: ptr<u8> = null;
    var ctx: ptr<u8> = null;
    unsafe {
        layer = gm.layer;
        ctx = gm.ctx;
    }
    if ((ap as i64) == 0 || (layer as i64) == 0 || (ctx as i64) == 0) {
        return;
    }
    unsafe { gui_render(&mut *ap); }
    let img: ptr<u8> = CGBitmapContextCreateImage(ctx);
    if ((img as i64) == 0) {
        return;
    }
    gm_s1(layer, "setContents:", img as i64);
    gm_s(layer, "setNeedsDisplay");
    CGImageRelease(img);
}

fn gm_stop(gm: ptr<GMac>) {
    var win: ptr<u8> = null;
    unsafe { win = gm.win; }
    if ((win as i64) != 0) {
        gm_s1(win, "orderOut:", 0);
        gm_s(win, "close");
    }
    let nsapp: ptr<u8> = gm_s(gm_cls("NSApplication"), "sharedApplication");
    if ((nsapp as i64) != 0) {
        gm_s1(nsapp, "stop:", 0);
    }
}

fn gm_tick(gm: ptr<GMac>) {
    let ap: ptr<GApp> = gm_app_of(gm);
    if ((ap as i64) == 0) {
        return;
    }
    var tk: i64 = 0;
    var qm: i64 = 0;
    var win: ptr<u8> = null;
    unsafe {
        tk = gm.tick_ms;
        qm = gm.quit_ms;
        win = gm.win;
    }
    if (tk > 0) {
        var hk: fn(i64, i64) -> void = gui_mac_noop;
        var n: i64 = 0;
        unsafe {
            hk = gm.hook;
            gm.frame += 1;
            n = gm.frame;
        }
        unsafe { gui_timer(&mut *ap); }
        if ((hk as i64) != 0) {
            hk(ap as i64, n);
        }
    }
    gm_blit(gm);
    var q: i64 = 0;
    unsafe { q = ap.quit; }
    if (q != 0) {
        gm_stop(gm);
        return;
    }
    var n2: i64 = 0;
    unsafe { n2 = gm.frame; }
    if (qm > 0 && tk > 0 && n2 * tk >= qm) {
        gm_stop(gm);
        return;
    }
    if ((win as i64) != 0) {
        let vis: i64 = (gm_s(win, "isVisible") as i64) & 255;
        if (vis == 0) {
            gm_stop(gm);
        }
    }
}

fn gm_vk(code: i64) -> i64 {
    if (code == 51) {
        return VK_BACK;
    }
    if (code == 48) {
        return VK_TAB;
    }
    if (code == 36 || code == 76) {
        return VK_RETURN;
    }
    if (code == 53) {
        return VK_ESCAPE;
    }
    if (code == 49) {
        return VK_SPACE;
    }
    if (code == 115) {
        return VK_HOME;
    }
    if (code == 119) {
        return VK_END;
    }
    if (code == 123) {
        return VK_LEFT;
    }
    if (code == 124) {
        return VK_RIGHT;
    }
    if (code == 125) {
        return VK_DOWN;
    }
    if (code == 126) {
        return VK_UP;
    }
    if (code == 117) {
        return VK_DELETE;
    }
    return 0;
}

fn gm_mouse_xy(gm: ptr<GMac>, ev: ptr<u8>, px: ptr<i64>, py: ptr<i64>, down: i32) -> i32 {
    var pt: GMacPoint = zero(GMacPoint);
    var pp: ptr<u8> = null;
    unsafe { pp = &mut pt as ptr<u8>; }
    if (gm_point(ev, pp) != 0) {
        return -1;
    }
    let ap: ptr<GApp> = gm_app_of(gm);
    if ((ap as i64) == 0) {
        return -1;
    }
    var h: i64 = 0;
    var w: i64 = 0;
    unsafe {
        h = ap.h;
        w = ap.w;
    }
    var x: i64 = pt.x as i64;
    var y: i64 = h - (pt.y as i64);
    if (x < 0) {
        x = 0;
    }
    if (y < 0) {
        y = 0;
    }
    if (x > w) {
        x = w;
    }
    if (y > h) {
        y = h;
    }
    unsafe {
        px[0] = x;
        py[0] = y;
    }
    if (down != 0) {
        unsafe { gui_mouse_down(&mut *ap, x, y); }
    } else {
        unsafe { gui_mouse_move(&mut *ap, x, y); }
    }
    return 0;
}

fn gm_imp_mouse_down(sv: ptr<u8>, cm: ptr<u8>, ev: ptr<u8>) {
    let gm: ptr<GMac> = gm_state(sv);
    if ((gm as i64) == 0) {
        return;
    }
    var x: i64 = 0;
    var y: i64 = 0;
    var xp: ptr<i64> = null;
    var yp: ptr<i64> = null;
    unsafe {
        xp = &mut x as ptr<i64>;
        yp = &mut y as ptr<i64>;
    }
    if (gm_mouse_xy(gm, ev, xp, yp, 1) == 0) {
        gm_blit(gm);
    }
}

fn gm_imp_mouse_up(sv: ptr<u8>, cm: ptr<u8>, ev: ptr<u8>) {
    let gm: ptr<GMac> = gm_state(sv);
    if ((gm as i64) == 0) {
        return;
    }
    let ap: ptr<GApp> = gm_app_of(gm);
    var pt: GMacPoint = zero(GMacPoint);
    var pp: ptr<u8> = null;
    unsafe { pp = &mut pt as ptr<u8>; }
    if (gm_point(ev, pp) != 0 || (ap as i64) == 0) {
        return;
    }
    var h: i64 = 0;
    unsafe { h = ap.h; }
    let x: i64 = pt.x as i64;
    let y: i64 = h - (pt.y as i64);
    unsafe { gui_mouse_up(&mut *ap, x, y); }
    gm_blit(gm);
}

fn gm_imp_mouse_move(sv: ptr<u8>, cm: ptr<u8>, ev: ptr<u8>) {
    let gm: ptr<GMac> = gm_state(sv);
    if ((gm as i64) == 0) {
        return;
    }
    var x: i64 = 0;
    var y: i64 = 0;
    var xp: ptr<i64> = null;
    var yp: ptr<i64> = null;
    unsafe {
        xp = &mut x as ptr<i64>;
        yp = &mut y as ptr<i64>;
    }
    if (gm_mouse_xy(gm, ev, xp, yp, 0) == 0) {
        gm_blit(gm);
    }
}

fn gm_imp_scroll(sv: ptr<u8>, cm: ptr<u8>, ev: ptr<u8>) {
    let gm: ptr<GMac> = gm_state(sv);
    if ((gm as i64) == 0) {
        return;
    }
    let ap: ptr<GApp> = gm_app_of(gm);
    if ((ap as i64) == 0) {
        return;
    }
    var d: f64 = 0.0;
    var dp: ptr<u8> = null;
    unsafe { dp = &mut d as ptr<u8>; }
    if (gm_double(ev, "scrollingDeltaY", dp) != 0) {
        return;
    }
    if (d > 0.0) {
        unsafe { gui_wheel(&mut *ap, -1); }
    } else if (d < 0.0) {
        unsafe { gui_wheel(&mut *ap, 1); }
    }
    gm_blit(gm);
}

fn gm_imp_key_down(sv: ptr<u8>, cm: ptr<u8>, ev: ptr<u8>) {
    let gm: ptr<GMac> = gm_state(sv);
    if ((gm as i64) == 0) {
        return;
    }
    let ap: ptr<GApp> = gm_app_of(gm);
    if ((ap as i64) == 0) {
        return;
    }
    let code: i64 = (gm_s(ev, "keyCode") as i64) & 65535;
    let vk: i64 = gm_vk(code);
    var handled: i64 = 0;
    if (vk != 0) {
        unsafe { gui_key(&mut *ap, vk, 0); }
        handled = 1;
    } else {
        let str: ptr<u8> = gm_s(ev, "characters");
        if ((str as i64) != 0) {
            let u: ptr<u8> = gm_s(str, "UTF8String");
            if ((u as i64) != 0) {
                var ch: i64 = 0;
                unsafe { ch = u[0] as i64; }
                if (ch >= 32 && ch <= 126) {
                    unsafe { gui_key(&mut *ap, 0, ch); }
                    handled = 1;
                }
            }
        }
    }
    if (handled != 0) {
        gm_blit(gm);
    }
}

fn gm_imp_tick(sv: ptr<u8>, cm: ptr<u8>, timer: ptr<u8>) {
    let gm: ptr<GMac> = gm_state(sv);
    if ((gm as i64) == 0) {
        return;
    }
    gm_tick(gm);
}

fn gm_make_view() -> ptr<u8> {
    let base: ptr<u8> = gm_cls("NSView");
    if ((base as i64) == 0) {
        return null;
    }
    var sub: ptr<u8> = objc_allocateClassPair(base, "RGuiView", 0);
    if ((sub as i64) == 0) {
        return gm_cls("RGuiView");
    }
    class_addMethod(sub, sel_registerName("mouseDown:"), gm_imp_mouse_down as ptr<u8>, "v@:@");
    class_addMethod(sub, sel_registerName("mouseUp:"), gm_imp_mouse_up as ptr<u8>, "v@:@");
    class_addMethod(sub, sel_registerName("mouseMoved:"), gm_imp_mouse_move as ptr<u8>, "v@:@");
    class_addMethod(sub, sel_registerName("mouseDragged:"), gm_imp_mouse_move as ptr<u8>, "v@:@");
    class_addMethod(sub, sel_registerName("scrollWheel:"), gm_imp_scroll as ptr<u8>, "v@:@");
    class_addMethod(sub, sel_registerName("keyDown:"), gm_imp_key_down as ptr<u8>, "v@:@");
    class_addMethod(sub, sel_registerName("onTick:"), gm_imp_tick as ptr<u8>, "v@:@");
    objc_registerClassPair(sub);
    return sub;
}

fn gm_make_window(w: i64, h: i64) -> ptr<u8> {
    let cls: ptr<u8> = gm_cls("NSWindow");
    if ((cls as i64) == 0) {
        return null;
    }
    let win: ptr<u8> = gm_s(cls, "alloc");
    if ((win as i64) == 0) {
        return null;
    }
    let m: ptr<u8> = sel_registerName("initWithContentRect:styleMask:backing:defer:");
    let sig: ptr<u8> = gm_s1(win, "methodSignatureForSelector:", m as i64);
    if ((sig as i64) == 0) {
        return null;
    }
    let inv: ptr<u8> = gm_s1(gm_cls("NSInvocation"), "invocationWithMethodSignature:", sig as i64);
    if ((inv as i64) == 0) {
        return null;
    }
    var r: GMacRect = zero(GMacRect);
    r.x = 0.0;
    r.y = 0.0;
    r.w = w as f64;
    r.h = h as f64;
    var mask: i64 = GM_STYLE;
    var backing: i64 = GM_LAYER;
    var defer_: i64 = 0;
    var rp: ptr<u8> = null;
    var mp: ptr<u8> = null;
    var bp: ptr<u8> = null;
    var dp: ptr<u8> = null;
    unsafe {
        rp = &mut r as ptr<u8>;
        mp = &mut mask as ptr<u8>;
        bp = &mut backing as ptr<u8>;
        dp = &mut defer_ as ptr<u8>;
    }
    gm_s1(inv, "setTarget:", win as i64);
    gm_s1(inv, "setSelector:", m as i64);
    gm_s2(inv, "setArgument:atIndex:", rp as i64, 2);
    gm_s2(inv, "setArgument:atIndex:", mp as i64, 3);
    gm_s2(inv, "setArgument:atIndex:", bp as i64, 4);
    gm_s2(inv, "setArgument:atIndex:", dp as i64, 5);
    gm_s(inv, "invoke");
    var out: ptr<u8> = null;
    var op: ptr<u8> = null;
    unsafe { op = &mut out as ptr<u8>; }
    gm_s1(inv, "getReturnValue:", op as i64);
    if ((out as i64) == 0) {
        gm_s(win, "release");
        return null;
    }
    gm_s1(out, "setReleasedWhenClosed:", 0);
    return out;
}

fn gui_mac_open(app: &mut GApp, title: ptr<u8>) -> i64 {
    dlopen("/System/Library/Frameworks/AppKit.framework/AppKit", GM_RTLD_NOW);
    let nsapp: ptr<u8> = gm_s(gm_cls("NSApplication"), "sharedApplication");
    if ((nsapp as i64) == 0) {
        return 0;
    }
    gm_s1(nsapp, "setActivationPolicy:", GM_ACTIVATION_REGULAR);
    gm_s(nsapp, "finishLaunching");
    var w: i64 = 0;
    var h: i64 = 0;
    unsafe {
        w = app.w;
        h = app.h;
    }
    let win: ptr<u8> = gm_make_window(w, h);
    if ((win as i64) == 0) {
        return 0;
    }
    let view: ptr<u8> = gm_make_view();
    if ((view as i64) == 0) {
        gm_s(win, "release");
        return 0;
    }
    gm_s1(view, "setWantsLayer:", 1);
    gm_s1(win, "setContentView:", view as i64);
    gm_s1(win, "makeFirstResponder:", view as i64);
    gm_s1(win, "setAcceptsMouseMovedEvents:", 1);
    gm_s0_title(win, title);
    gm_s(win, "center");
    gm_s1(win, "makeKeyAndOrderFront:", 0);
    gm_s1(nsapp, "activateIgnoringOtherApps:", 1);
    let layer: ptr<u8> = gm_s(view, "layer");
    if ((layer as i64) != 0) {
        gm_s1(layer, "setContentsGravity:", gm_str("resize") as i64);
        gm_s1(layer, "setMasksToBounds:", 1);
    }
    return win as i64;
}

fn gm_s0_title(win: ptr<u8>, title: ptr<u8>) {
    if ((title as i64) == 0) {
        return;
    }
    let str: ptr<u8> = gm_str(title);
    if ((str as i64) != 0) {
        gm_s1(win, "setTitle:", str as i64);
    }
}

fn gui_mac_run_hook(app: &mut GApp, title: ptr<u8>, tick_ms: i64, quit_ms: i64,
                    hook: fn(i64, i64) -> void) -> i32 {
    let h: i64 = gui_mac_open(app, title);
    if (h == 0) {
        return -1;
    }
    let win: ptr<u8> = h as ptr<u8>;
    let view: ptr<u8> = gm_s(win, "contentView");
    let layer: ptr<u8> = gm_s(view, "layer");
    let ctx: ptr<u8> = gm_make_ctx(app);
    if ((view as i64) == 0 || (ctx as i64) == 0) {
        gm_s(win, "release");
        return -1;
    }
    var ap: ptr<GApp> = null;
    unsafe { ap = app as ptr<GApp>; }
    var gm: GMac = zero(GMac);
    gm.app = ap;
    gm.win = win;
    gm.view = view;
    gm.layer = layer;
    gm.ctx = ctx;
    gm.hook = hook;
    gm.tick_ms = tick_ms;
    gm.quit_ms = quit_ms;
    gm.frame = 0;
    gm.live = 1;
    var gp: ptr<GMac> = null;
    unsafe { gp = &mut gm as ptr<GMac>; }
    gm_s1(view, "setTag:", gp as i64);
    var iv: f64 = 0.1;
    if (tick_ms > 0) {
        iv = (tick_ms as f64) / 1000.0;
    }
    gm_timer(iv, view, gm_sel("onTick:"));
    gm_blit(gp);
    let nsapp: ptr<u8> = gm_s(gm_cls("NSApplication"), "sharedApplication");
    if ((nsapp as i64) != 0) {
        gm_s(nsapp, "run");
    }
    gm_s1(view, "setTag:", 0);
    gm_s1(win, "orderOut:", 0);
    gm_s(win, "close");
    CGContextRelease(ctx);
    return 0;
}

fn gm_timer(iv: f64, target: ptr<u8>, sel: ptr<u8>) -> ptr<u8> {
    let cls: ptr<u8> = gm_cls("NSTimer");
    if ((cls as i64) == 0) {
        return null;
    }
    let m: ptr<u8> = sel_registerName("scheduledTimerWithTimeInterval:target:selector:userInfo:repeats:");
    var zero_: i64 = 0;
    var one_: i64 = 1;
    return objc_msgSend(cls, m, iv, target as i64, sel as i64, zero_, one_);
}

fn gui_mac_run(app: &mut GApp, title: ptr<u8>) -> i32 {
    return gui_mac_run_hook(app, title, 0, 0, gui_mac_noop);
}
