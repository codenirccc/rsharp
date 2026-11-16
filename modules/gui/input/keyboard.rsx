fn gui_key(app: &mut GApp, vk: i64, ch: i64) -> i32 {
    let f: i64 = app.focus;
    if (f < 0) {
        return 0;
    }
    let k: i64 = app.widgets[f].kind;
    if (k == GK_FIELD) {
        if (vk == VK_BACK) {
            gui_field_delete(app, f, 1);
            return 1;
        }
        if (vk == VK_DELETE) {
            gui_field_delete(app, f, 0);
            return 1;
        }
        if (vk == VK_LEFT) {
            app.widgets[f].caret = gui_clampi(app.widgets[f].caret - 1, 0, app.widgets[f].blen);
            app.dirty = 1;
            return 1;
        }
        if (vk == VK_RIGHT) {
            app.widgets[f].caret = gui_clampi(app.widgets[f].caret + 1, 0, app.widgets[f].blen);
            app.dirty = 1;
            return 1;
        }
        if (vk == VK_HOME) {
            app.widgets[f].caret = 0;
            app.dirty = 1;
            return 1;
        }
        if (vk == VK_END) {
            app.widgets[f].caret = app.widgets[f].blen;
            app.dirty = 1;
            return 1;
        }
        if (vk == VK_RETURN) {
            gui_push(app, f, GEV_SUBMIT, app.widgets[f].blen);
            return 1;
        }
        if (ch >= 32 && ch <= 126) {
            gui_field_insert(app, f, ch);
            return 1;
        }
        return 0;
    }
    if (vk == VK_SPACE || vk == VK_RETURN) {
        if (k == GK_BUTTON) {
            gui_push(app, f, GEV_CLICK, 0);
            return 1;
        }
        if (k == GK_CHECK) {
            if (app.widgets[f].value == 0) {
                app.widgets[f].value = 1;
            } else {
                app.widgets[f].value = 0;
            }
            gui_push(app, f, GEV_TOGGLE, app.widgets[f].value);
            app.dirty = 1;
            return 1;
        }
    }
    if (vk == VK_LEFT || vk == VK_DOWN) {
        return gui_wheel(app, -1);
    }
    if (vk == VK_RIGHT || vk == VK_UP) {
        return gui_wheel(app, 1);
    }
    return 0;
}
