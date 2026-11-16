include "../../modules/gui/gui_mac.rsx";
include "scene.rsx";

fn main() -> i32 {
    var app: GApp = zero(GApp);
    if (gui_app_init(&mut app, 720, 520) != 0) {
        return 1;
    }
    if (scene_build(&mut app) != 0) {
        gui_app_free(&mut app);
        return 2;
    }
    let rc: i32 = gui_mac_run_hook(&mut app, "R# gui - modules/gui", 80, 0, scene_tick);
    gui_app_free(&mut app);
    return rc;
}
