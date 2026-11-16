include "../../modules/gui/gui_win.rsx";

include "paint_scene.rsx";

extern fn printf(fmt: ptr<u8>, ...) -> i32;

fn main() -> i32 {
    var app: GApp = zero(GApp);
    if (gui_app_init(&mut app, 720, 520) != 0) {
        printf("paint: cannot start the window\n");
        return 1;
    }
    if (paint_build(&mut app) != 0) {
        gui_app_free(&mut app);
        printf("paint: bad scene\n");
        return 1;
    }
    gui_render(&mut app);
    let rc: i32 = gui_win_run(&mut app, "paint");
    gui_app_free(&mut app);
    return rc;
}
