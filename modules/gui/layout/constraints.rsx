fn gui_min_size(app: &mut GApp, id: i64, axis: i64) -> i64 {
    if (axis == GL_ROW) {
        if (app.widgets[id].fw > 0) {
            return app.widgets[id].fw;
        }
        return gui_natural_w(app, id);
    }
    if (app.widgets[id].fh > 0) {
        return app.widgets[id].fh;
    }
    return gui_natural_h(app, id);
}
