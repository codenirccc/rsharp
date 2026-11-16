include "../../modules/gui/gui_win.rsx";

extern fn printf(fmt: ptr<u8>, ...) -> i32;

const TW_TITLE: i64 = 1;
const TW_BTN: i64 = 2;
const TW_HIT: i64 = 3;
const TW_NOTE: i64 = 4;

fn tw_fail(code: i32) -> i32 {
    printf("gui win: fail %d\n", code);
    return code;
}

fn tw_hook(ap: i64, n: i64) {
    let p: ptr<GApp> = ap as ptr<GApp>;
    var ev: GEvent = zero(GEvent);
    unsafe {
        while (gui_next_event(&mut *p, &mut ev) != 0) {
            if (ev.code == GEV_CLICK) {
                let v: i64 = gui_value(&mut *p, TW_HIT) + 1;
                gui_set_value(&mut *p, TW_HIT, v);
                if (v == 1) {
                    gui_set_text(&mut *p, TW_NOTE, "clicked once");
                }
            }
        }
    }
    if (n == 3) {
        var bx: i64 = 0;
        var by: i64 = 0;
        unsafe {
            bx = gui_widget_x(&mut *p, TW_BTN) + 6;
            by = gui_widget_y(&mut *p, TW_BTN) + 6;
            gui_mouse_move(&mut *p, bx, by);
            gui_mouse_down(&mut *p, bx, by);
            gui_mouse_up(&mut *p, bx, by);
        }
    }
}

fn main() -> i32 {
    var app: GApp = zero(GApp);
    if (gui_app_init(&mut app, 420, 260) != 0) {
        return tw_fail(10);
    }
    gui_set_pad(&mut app, 0, 16, 10);
    let t: i64 = gui_add(&mut app, GK_LABEL, 0, "gui win test");
    let b: i64 = gui_add(&mut app, GK_BUTTON, 0, "click me");
    let h: i64 = gui_add(&mut app, GK_PROGRESS, 0, "hits");
    let n: i64 = gui_add(&mut app, GK_LABEL, 0, "waiting");
    if (t != TW_TITLE || b != TW_BTN || h != TW_HIT || n != TW_NOTE) {
        gui_app_free(&mut app);
        return tw_fail(11);
    }
    gui_set_size(&mut app, b, 120, 28);
    gui_set_size(&mut app, h, 140, 12);
    gui_set_range(&mut app, h, 0, 4);
    gui_set_value(&mut app, h, 0);
    gui_render(&mut app);
    let h0: u64 = gui_hash(&mut app);
    let rc: i32 = gui_win_run_hook(&mut app, "R# gui - win test", 40, 800, tw_hook);
    if (rc != 0) {
        gui_app_free(&mut app);
        return tw_fail(12);
    }
    let hits: i64 = gui_value(&mut app, h);
    if (hits != 1) {
        gui_app_free(&mut app);
        return tw_fail(13);
    }
    if (app.frames < 10) {
        gui_app_free(&mut app);
        return tw_fail(14);
    }
    let h1: u64 = gui_hash(&mut app);
    if (h1 == h0) {
        gui_app_free(&mut app);
        return tw_fail(15);
    }
    printf("frames=%lld hits=%lld\n", app.frames, hits);
    gui_app_free(&mut app);
    printf("gui win: ok\n");
    return 0;
}
