include "../../modules/gui/gui_win.rsx";

include "paint_scene.rsx";

extern fn printf(fmt: ptr<u8>, ...) -> i32;

fn tp_hook(ap: i64, n: i64) {
    let p: ptr<GApp> = ap as ptr<GApp>;
    unsafe {
        paint_drain(&mut *p);
    }
    if (n == 2) {
        unsafe {
            let cx: i64 = gui_widget_x(&mut *p, PA_CANVAS);
            let cy: i64 = gui_widget_y(&mut *p, PA_CANVAS);
            let sx: i64 = cx + 96;
            let sy: i64 = cy + 120;
            let ex: i64 = cx + 560;
            let ey: i64 = cy + 224;
            gui_mouse_move(&mut *p, sx, sy);
            gui_mouse_down(&mut *p, sx, sy);
            var step: i64 = 1;
            while (step <= 8) {
                gui_mouse_move(&mut *p, sx + (ex - sx) * step / 8, sy + (ey - sy) * step / 8);
                step += 1;
            }
            gui_mouse_up(&mut *p, ex, ey);
        }
    } else if (n == 4) {
        unsafe {
            let bx: i64 = gui_widget_x(&mut *p, PA_SAVE) + 12;
            let by: i64 = gui_widget_y(&mut *p, PA_SAVE) + 8;
            gui_mouse_move(&mut *p, bx, by);
            gui_mouse_down(&mut *p, bx, by);
            gui_mouse_up(&mut *p, bx, by);
        }
    } else if (n == 6) {
        unsafe {
            let app: &mut GApp = &mut *p;
            app.quit = 1;
        }
    }
}

fn main() -> i32 {
    var app: GApp = zero(GApp);
    if (gui_app_init(&mut app, 720, 520) != 0) {
        printf("paint selftest: init failed\n");
        return 1;
    }
    if (paint_build(&mut app) != 0) {
        gui_app_free(&mut app);
        printf("paint selftest: bad scene\n");
        return 1;
    }
    gui_render(&mut app);
    let rc: i32 = gui_win_run_hook(&mut app, "paint selftest", 40, 900, tp_hook);
    if (rc != 0) {
        gui_app_free(&mut app);
        printf("paint selftest: run failed\n");
        return 1;
    }
    gui_app_free(&mut app);

    let read: i64 = 2147483648;
    let h: i64 = CreateFileA("paint.bmp" as ptr<u8>, read as u32, 1, null, 3, 0x80, 0);
    if (h == -1) {
        printf("paint selftest: paint.bmp missing\n");
        return 1;
    }
    var size: u64 = 0;
    var sp: ptr<u64> = null;
    unsafe {
        sp = &mut size as ptr<u64>;
    }
    let ok: i32 = GetFileSizeEx(h, sp);
    var head: [u8; 4] = [0];
    var got: u32 = 0;
    var hp: ptr<u8> = null;
    var gp: ptr<u32> = null;
    unsafe {
        hp = &mut head[0] as ptr<u8>;
        gp = &mut got as ptr<u32>;
        ReadFile(h, hp, 4, gp, null);
    }
    CloseHandle(h);
    if (ok == 0) {
        printf("paint selftest: size query failed\n");
        return 1;
    }
    let want: u64 = (54 + 656 * 336 * 3) as u64;
    if (size != want) {
        printf("paint selftest: size %llu, want %llu\n", size, want);
        return 1;
    }
    if (head[0] != 66 || head[1] != 77) {
        printf("paint selftest: not a bitmap\n");
        return 1;
    }
    printf("paint selftest: ok (%llu bytes)\n", size, want);
    return 0;
}
