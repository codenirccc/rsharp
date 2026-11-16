fn gui_field_insert(app: &mut GApp, id: i64, ch: i64) {
    if (ch < 32 || ch > 126) {
        return;
    }
    if (app.widgets[id].blen >= GUI_TEXT_MAX - 1) {
        return;
    }
    var i: i64 = app.widgets[id].blen;
    unsafe {
        while (i > app.widgets[id].caret) {
            app.widgets[id].buf[i] = app.widgets[id].buf[i - 1];
            i -= 1;
        }
        app.widgets[id].buf[app.widgets[id].caret] = ch as u8;
        app.widgets[id].blen += 1;
        app.widgets[id].buf[app.widgets[id].blen] = 0;
    }
    app.widgets[id].caret += 1;
    app.dirty = 1;
    gui_push(app, id, GEV_CHANGE, app.widgets[id].blen);
}

fn gui_field_delete(app: &mut GApp, id: i64, back: i64) {
    if (app.widgets[id].blen <= 0) {
        return;
    }
    var at: i64 = app.widgets[id].caret;
    if (back == 1) {
        if (at <= 0) {
            return;
        }
        at -= 1;
    } else if (at >= app.widgets[id].blen) {
        return;
    }
    unsafe {
        var i: i64 = at;
        while (i < app.widgets[id].blen - 1) {
            app.widgets[id].buf[i] = app.widgets[id].buf[i + 1];
            i += 1;
        }
        app.widgets[id].blen -= 1;
        app.widgets[id].buf[app.widgets[id].blen] = 0;
    }
    app.widgets[id].caret = at;
    app.dirty = 1;
    gui_push(app, id, GEV_CHANGE, app.widgets[id].blen);
}
