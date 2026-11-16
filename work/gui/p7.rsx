include "../../modules/gui/gui.rsx";

extern fn printf(fmt: ptr<u8>, ...) -> i32;

fn main() -> i32 {
    var app: GApp = zero(GApp);
    let rc: i32 = gui_app_init(&mut app, 320, 200);
    if (rc != 0) {
        return 1;
    }
    let a: i64 = gui_add(&mut app, GK_LABEL, 0, "hello gui");
    let b: i64 = gui_add(&mut app, GK_BUTTON, 0, "press me");
    let c: i64 = gui_add(&mut app, GK_FIELD, 0, "abc");
    let d: i64 = gui_add(&mut app, GK_CHECK, 0, "check");
    let e: i64 = gui_add(&mut app, GK_SLIDER, 0, "slider");
    let f: i64 = gui_add(&mut app, GK_PROGRESS, 0, "progress");
    gui_set_value(&mut app, e, 40);
    gui_set_value(&mut app, f, 75);
    gui_set_grow(&mut app, f, 1);
    gui_render(&mut app);
    printf("ids=%lld %lld %lld %lld %lld %lld hash=%lld\n", a, b, c, d, e, f, gui_hash(&mut app));
    var i: i64 = 0;
    while (i < 7) {
        printf("row %lld = %d\n", i, gui_font_row(65, i) as i32);
        i += 1;
    }
    gui_app_free(&mut app);
    return 0;
}
