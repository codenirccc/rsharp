fn gui_layout_children(app: &mut GApp, pi: i64) {
    let pad: i64 = app.widgets[pi].pad;
    let gap: i64 = app.widgets[pi].gap;
    let axis: i64 = app.widgets[pi].layout;
    let cx: i64 = app.widgets[pi].x + pad;
    let cy: i64 = app.widgets[pi].y + pad;
    let cw: i64 = app.widgets[pi].w - pad * 2;
    let ch: i64 = app.widgets[pi].h - pad * 2;
    var total: i64 = cw;
    if (axis != GL_ROW) {
        total = ch;
    }
    var fixed: i64 = 0;
    var weight: i64 = 0;
    var n: i64 = 0;
    var i: i64 = 0;
    while (i < app.nw) {
        if (app.widgets[i].parent == pi && app.widgets[i].visible == 1) {
            n += 1;
            if (app.widgets[i].grow > 0) {
                weight += app.widgets[i].grow;
            } else {
                fixed += gui_min_size(app, i, axis);
            }
        }
        i += 1;
    }
    var free: i64 = total - fixed;
    if (n > 1) {
        free = free - gap * (n - 1);
    }
    if (free < 0) {
        free = 0;
    }
    var pos: i64 = cy;
    if (axis == GL_ROW) {
        pos = cx;
    }
    i = 0;
    while (i < app.nw) {
        if (app.widgets[i].parent == pi && app.widgets[i].visible == 1) {
            var main: i64 = 0;
            if (app.widgets[i].grow > 0 && weight > 0) {
                main = free * app.widgets[i].grow / weight;
            } else {
                main = gui_min_size(app, i, axis);
            }
            if (axis == GL_ROW) {
                app.widgets[i].x = pos;
                app.widgets[i].y = cy;
                app.widgets[i].w = main;
                if (app.widgets[i].fill == 1) {
                    app.widgets[i].h = ch;
                } else if (app.widgets[i].fh > 0) {
                    app.widgets[i].h = app.widgets[i].fh;
                } else {
                    app.widgets[i].h = gui_natural_h(app, i);
                }
            } else {
                app.widgets[i].y = pos;
                app.widgets[i].x = cx;
                app.widgets[i].h = main;
                if (app.widgets[i].fill == 1) {
                    app.widgets[i].w = cw;
                } else if (app.widgets[i].fw > 0) {
                    app.widgets[i].w = app.widgets[i].fw;
                } else {
                    app.widgets[i].w = gui_natural_w(app, i);
                }
                if (app.widgets[i].align == GA_CENTER) {
                    app.widgets[i].x = cx + (cw - app.widgets[i].w) / 2;
                } else if (app.widgets[i].align == GA_RIGHT) {
                    app.widgets[i].x = cx + cw - app.widgets[i].w;
                }
            }
            if (app.widgets[i].align == GA_CENTER && axis == GL_ROW) {
                app.widgets[i].y = cy + (ch - app.widgets[i].h) / 2;
            }
            pos += main + gap;
        }
        i += 1;
    }
}

fn gui_layout(app: &mut GApp) {
    app.widgets[0].x = 0;
    app.widgets[0].y = 0;
    app.widgets[0].w = app.w;
    app.widgets[0].h = app.h;
    var i: i64 = 0;
    while (i < app.nw) {
        if (app.widgets[i].kind == GK_PANEL && app.widgets[i].visible == 1) {
            gui_layout_children(app, i);
        }
        i += 1;
    }
}
