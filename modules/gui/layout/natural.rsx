fn gui_natural_w(app: &mut GApp, id: i64) -> i64 {
    let s: i64 = app.theme.scale;
    let u: i64 = app.theme.unit * s;
    let k: i64 = app.widgets[id].kind;
    if (k == GK_LABEL) {
        return gui_text_w(app.widgets[id].text, s);
    }
    if (k == GK_BUTTON) {
        return gui_text_w(app.widgets[id].text, s) + u * 6;
    }
    if (k == GK_CHECK) {
        return gui_text_w(app.widgets[id].text, s) + u * 6;
    }
    if (k == GK_FIELD) {
        return u * 30;
    }
    if (k == GK_SLIDER) {
        return u * 30;
    }
    if (k == GK_PROGRESS) {
        return u * 30;
    }
    if (app.widgets[id].fw > 0) {
        return app.widgets[id].fw;
    }
    return 0;
}

fn gui_natural_h(app: &mut GApp, id: i64) -> i64 {
    let s: i64 = app.theme.scale;
    let k: i64 = app.widgets[id].kind;
    if (k == GK_PANEL) {
        return app.widgets[id].fh;
    }
    if (k == GK_LABEL) {
        return gui_text_h(s) + 2;
    }
    if (k == GK_BUTTON) {
        return app.theme.row;
    }
    if (k == GK_CHECK) {
        return app.theme.row;
    }
    if (k == GK_FIELD) {
        return app.theme.row;
    }
    if (k == GK_SLIDER) {
        return app.theme.row;
    }
    if (k == GK_PROGRESS) {
        return app.theme.row;
    }
    return app.theme.row;
}
