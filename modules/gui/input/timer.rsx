fn gui_timer(app: &mut GApp) -> i32 {
    app.frames += 1;
    app.dirty = 1;
    gui_push(app, -1, GEV_TIMER, app.frames);
    return 1;
}
