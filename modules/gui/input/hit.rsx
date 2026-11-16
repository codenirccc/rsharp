fn gui_hit(app: &mut GApp, x: i64, y: i64) -> i64 {
    var i: i64 = app.nw - 1;
    while (i > 0) {
        if (app.widgets[i].visible == 1 && app.widgets[i].enabled == 1
            && app.widgets[i].kind != GK_PANEL) {
            let w: i64 = app.widgets[i].w;
            let h: i64 = app.widgets[i].h;
            if (x >= app.widgets[i].x && y >= app.widgets[i].y
                && x < app.widgets[i].x + w && y < app.widgets[i].y + h) {
                return i;
            }
        }
        i -= 1;
    }
    return -1;
}
