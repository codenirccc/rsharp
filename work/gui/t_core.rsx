include "../../modules/gui/gui.rsx";

extern fn printf(fmt: ptr<u8>, ...) -> i32;

fn t_fail(code: i32) -> i32 {
    printf("gui core: fail %d\n", code);
    return code;
}

fn t_clear(app: &mut GApp) {
    var ev: GEvent = zero(GEvent);
    while (gui_next_event(app, &mut ev) != 0) {
    }
}

fn t_count(app: &mut GApp, id: i64, code: i64) -> i64 {
    var n: i64 = 0;
    var ev: GEvent = zero(GEvent);
    while (gui_next_event(app, &mut ev) != 0) {
        if (ev.id == id && ev.code == code) {
            n += 1;
        }
    }
    return n;
}

fn t_last(app: &mut GApp, id: i64, code: i64) -> i64 {
    var v: i64 = -999999;
    var ev: GEvent = zero(GEvent);
    while (gui_next_event(app, &mut ev) != 0) {
        if (ev.id == id && ev.code == code) {
            v = ev.value;
        }
    }
    return v;
}

fn t_str_eq(p: ptr<u8>, q: ptr<u8>) -> i32 {
    let n: i64 = strlen(p) as i64;
    if (n != strlen(q) as i64) {
        return 0;
    }
    var i: i64 = 0;
    while (i < n) {
        var a: u8 = 0;
        var b: u8 = 0;
        unsafe {
            a = p[i];
            b = q[i];
        }
        if (a != b) {
            return 0;
        }
        i += 1;
    }
    return 1;
}

fn main() -> i32 {
    var app: GApp = zero(GApp);
    if (gui_app_init(&mut app, 320, 200) != 0) {
        return t_fail(10);
    }
    gui_set_pad(&mut app, 0, 16, 10);
    let wl: i64 = gui_add(&mut app, GK_LABEL, 0, "label");
    let wb: i64 = gui_add(&mut app, GK_BUTTON, 0, "press");
    let wf: i64 = gui_add(&mut app, GK_FIELD, 0, "abc");
    let wc: i64 = gui_add(&mut app, GK_CHECK, 0, "check");
    let ws: i64 = gui_add(&mut app, GK_SLIDER, 0, "slider");
    let wp: i64 = gui_add(&mut app, GK_PROGRESS, 0, "prog");
    if (wl != 1 || wb != 2 || wf != 3 || wc != 4 || ws != 5 || wp != 6) {
        gui_app_free(&mut app);
        return t_fail(11);
    }
    gui_set_size(&mut app, wb, 120, 28);
    gui_set_size(&mut app, wf, 160, 24);
    gui_set_size(&mut app, wc, 18, 18);
    gui_set_size(&mut app, ws, 160, 24);
    gui_set_size(&mut app, wp, 140, 12);
    gui_set_range(&mut app, ws, 0, 100);
    gui_set_value(&mut app, ws, 50);
    gui_set_value(&mut app, wp, 25);
    gui_render(&mut app);
    if (gui_widget_w(&mut app, wb) != 120) {
        gui_app_free(&mut app);
        return t_fail(12);
    }
    if (gui_widget_h(&mut app, wb) != 28) {
        gui_app_free(&mut app);
        return t_fail(13);
    }
    let yl: i64 = gui_widget_y(&mut app, wl);
    let yb: i64 = gui_widget_y(&mut app, wb);
    let yf: i64 = gui_widget_y(&mut app, wf);
    if (yl >= yb) {
        gui_app_free(&mut app);
        return t_fail(14);
    }
    if (yb >= yf) {
        gui_app_free(&mut app);
        return t_fail(15);
    }
    t_clear(&mut app);
    let bx: i64 = gui_widget_x(&mut app, wb) + 6;
    let by: i64 = gui_widget_y(&mut app, wb) + 6;
    gui_mouse_move(&mut app, bx, by);
    gui_mouse_down(&mut app, bx, by);
    gui_mouse_up(&mut app, bx, by);
    if (t_count(&mut app, wb, GEV_CLICK) != 1) {
        gui_app_free(&mut app);
        return t_fail(16);
    }
    if (gui_focus(&mut app) != wb) {
        gui_app_free(&mut app);
        return t_fail(17);
    }
    t_clear(&mut app);
    let cx: i64 = gui_widget_x(&mut app, wc) + 9;
    let cy: i64 = gui_widget_y(&mut app, wc) + 9;
    gui_mouse_move(&mut app, cx, cy);
    gui_mouse_down(&mut app, cx, cy);
    gui_mouse_up(&mut app, cx, cy);
    if (gui_value(&mut app, wc) != 1) {
        gui_app_free(&mut app);
        return t_fail(18);
    }
    var cfe: i64 = 0;
    var cte: i64 = 0;
    var ctv: i64 = 0;
    var cev: GEvent = zero(GEvent);
    while (gui_next_event(&mut app, &mut cev) != 0) {
        if (cev.id == wc && cev.code == GEV_FOCUS) {
            cfe += 1;
        }
        if (cev.id == wc && cev.code == GEV_TOGGLE) {
            cte += 1;
            ctv = cev.value;
        }
    }
    if (cte != 1 || ctv != 1) {
        gui_app_free(&mut app);
        return t_fail(19);
    }
    if (cfe != 1) {
        gui_app_free(&mut app);
        return t_fail(22);
    }
    gui_mouse_down(&mut app, cx, cy);
    gui_mouse_up(&mut app, cx, cy);
    if (gui_value(&mut app, wc) != 0) {
        gui_app_free(&mut app);
        return t_fail(20);
    }
    if (t_last(&mut app, wc, GEV_TOGGLE) != 0) {
        gui_app_free(&mut app);
        return t_fail(21);
    }
    t_clear(&mut app);
    let sx: i64 = gui_widget_x(&mut app, ws);
    let sy: i64 = gui_widget_y(&mut app, ws);
    let sw: i64 = gui_widget_w(&mut app, ws);
    gui_mouse_down(&mut app, sx + sw - 1, sy + 4);
    if (gui_value(&mut app, ws) != 100) {
        gui_app_free(&mut app);
        return t_fail(23);
    }
    gui_mouse_move(&mut app, sx + 1, sy + 4);
    if (gui_value(&mut app, ws) != 0) {
        gui_app_free(&mut app);
        return t_fail(24);
    }
    gui_mouse_up(&mut app, sx + 1, sy + 4);
    if (t_count(&mut app, ws, GEV_CHANGE) != 2) {
        gui_app_free(&mut app);
        return t_fail(25);
    }
    let wu: i32 = gui_wheel(&mut app, 1);
    if (wu != 1) {
        gui_app_free(&mut app);
        return t_fail(26);
    }
    if (gui_value(&mut app, ws) != 5) {
        gui_app_free(&mut app);
        return t_fail(27);
    }
    let wd: i32 = gui_wheel(&mut app, -1);
    if (wd != 1) {
        gui_app_free(&mut app);
        return t_fail(28);
    }
    if (gui_value(&mut app, ws) != 0) {
        gui_app_free(&mut app);
        return t_fail(29);
    }
    t_clear(&mut app);
    gui_set_text(&mut app, wf, "abc");
    let fx: i64 = gui_widget_x(&mut app, wf);
    let fy: i64 = gui_widget_y(&mut app, wf);
    gui_mouse_move(&mut app, fx + 2, fy + 6);
    gui_mouse_down(&mut app, fx + 2, fy + 6);
    gui_mouse_up(&mut app, fx + 2, fy + 6);
    if (gui_focus(&mut app) != wf) {
        gui_app_free(&mut app);
        return t_fail(30);
    }
    if (t_count(&mut app, wf, GEV_FOCUS) != 1) {
        gui_app_free(&mut app);
        return t_fail(31);
    }
    gui_key(&mut app, 0, 90);
    let ft1: ptr<u8> = gui_field_text(&mut app, wf);
    if (t_str_eq(ft1, "Zabc") != 1) {
        gui_app_free(&mut app);
        return t_fail(32);
    }
    gui_key(&mut app, VK_END, 0);
    gui_key(&mut app, VK_BACK, 0);
    let ft2: ptr<u8> = gui_field_text(&mut app, wf);
    if (t_str_eq(ft2, "Zab") != 1) {
        gui_app_free(&mut app);
        return t_fail(33);
    }
    gui_key(&mut app, VK_HOME, 0);
    gui_key(&mut app, VK_DELETE, 0);
    let ft3: ptr<u8> = gui_field_text(&mut app, wf);
    if (t_str_eq(ft3, "ab") != 1) {
        gui_app_free(&mut app);
        return t_fail(34);
    }
    gui_key(&mut app, VK_RETURN, 0);
    if (t_count(&mut app, wf, GEV_SUBMIT) != 1) {
        gui_app_free(&mut app);
        return t_fail(35);
    }
    t_clear(&mut app);
    gui_render(&mut app);
    let h1: u64 = gui_hash(&mut app);
    gui_render(&mut app);
    let h2: u64 = gui_hash(&mut app);
    if (h1 != h2) {
        gui_app_free(&mut app);
        return t_fail(36);
    }
    gui_set_value(&mut app, ws, 73);
    gui_render(&mut app);
    let h3: u64 = gui_hash(&mut app);
    if (h3 == h2) {
        gui_app_free(&mut app);
        return t_fail(37);
    }
    var i: i64 = 0;
    var last: i64 = 0;
    while (i < 41) {
        last = gui_add(&mut app, GK_LABEL, 0, "x");
        i += 1;
    }
    if (last != 47) {
        gui_app_free(&mut app);
        return t_fail(38);
    }
    let over: i64 = gui_add(&mut app, GK_LABEL, 0, "x");
    if (over != -1) {
        gui_app_free(&mut app);
        return t_fail(39);
    }
    t_clear(&mut app);
    var ev: GEvent = zero(GEvent);
    if (gui_next_event(&mut app, &mut ev) != 0) {
        gui_app_free(&mut app);
        return t_fail(40);
    }
    printf("hash=%lld\n", h3 as i64);
    gui_app_free(&mut app);
    printf("gui core: ok\n");
    return 0;
}
