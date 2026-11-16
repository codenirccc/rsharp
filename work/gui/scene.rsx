const SC_TITLE: i64 = 1;
const SC_SUB: i64 = 2;
const SC_BAR: i64 = 3;
const SC_INC: i64 = 4;
const SC_RESET: i64 = 5;
const SC_QUIT: i64 = 6;
const SC_COUNT: i64 = 7;
const SC_SROW: i64 = 8;
const SC_SLAB: i64 = 9;
const SC_SLIDER: i64 = 10;
const SC_SVAL: i64 = 11;
const SC_PROG: i64 = 12;
const SC_FROW: i64 = 13;
const SC_FIELD: i64 = 14;
const SC_ECHO: i64 = 15;
const SC_STATUS: i64 = 16;

fn scene_num(app: &mut GApp, id: i64, v: i64, prefix: ptr<u8>) {
    let bp: ptr<u8> = gui_field_text(app, id);
    let n: i64 = gui_len(prefix);
    var i: i64 = 0;
    unsafe {
        while (i < n) {
            bp[i] = prefix[i];
            i += 1;
        }
        gui_itoa(bp + n, v);
    }
    gui_set_text(app, id, bp);
}

fn scene_build(app: &mut GApp) -> i32 {
    gui_set_pad(app, 0, 20, 12);
    var id: i64 = 0;
    id = gui_add(app, GK_LABEL, 0, "R# / gui");
    if (id != SC_TITLE) {
        return -1;
    }
    id = gui_add(app, GK_LABEL, 0, "a widget kit that lives in modules/gui");
    if (id != SC_SUB) {
        return -1;
    }
    id = gui_add(app, GK_PANEL, 0, null);
    if (id != SC_BAR) {
        return -1;
    }
    gui_set_layout(app, SC_BAR, GL_ROW);
    gui_set_pad(app, SC_BAR, 0, 8);
    gui_set_size(app, SC_BAR, 0, 34);
    gui_set_fill(app, SC_BAR, 1);
    id = gui_add(app, GK_BUTTON, SC_BAR, "count +1");
    if (id != SC_INC) {
        return -1;
    }
    gui_set_grow(app, SC_INC, 1);
    gui_set_fill(app, SC_INC, 1);
    id = gui_add(app, GK_BUTTON, SC_BAR, "reset");
    if (id != SC_RESET) {
        return -1;
    }
    gui_set_grow(app, SC_RESET, 1);
    gui_set_fill(app, SC_RESET, 1);
    id = gui_add(app, GK_BUTTON, SC_BAR, "quit");
    if (id != SC_QUIT) {
        return -1;
    }
    gui_set_grow(app, SC_QUIT, 1);
    gui_set_fill(app, SC_QUIT, 1);
    id = gui_add(app, GK_LABEL, 0, null);
    if (id != SC_COUNT) {
        return -1;
    }
    gui_set_fill(app, SC_COUNT, 1);
    scene_num(app, SC_COUNT, 0, "count ");
    id = gui_add(app, GK_PANEL, 0, null);
    if (id != SC_SROW) {
        return -1;
    }
    gui_set_layout(app, SC_SROW, GL_ROW);
    gui_set_pad(app, SC_SROW, 0, 8);
    gui_set_size(app, SC_SROW, 0, 34);
    gui_set_fill(app, SC_SROW, 1);
    id = gui_add(app, GK_LABEL, SC_SROW, "slider");
    if (id != SC_SLAB) {
        return -1;
    }
    gui_set_size(app, SC_SLAB, 84, 0);
    gui_set_fill(app, SC_SLAB, 1);
    id = gui_add(app, GK_SLIDER, SC_SROW, null);
    if (id != SC_SLIDER) {
        return -1;
    }
    gui_set_grow(app, SC_SLIDER, 1);
    gui_set_fill(app, SC_SLIDER, 1);
    gui_set_range(app, SC_SLIDER, 0, 100);
    gui_set_value(app, SC_SLIDER, 35);
    id = gui_add(app, GK_LABEL, SC_SROW, null);
    if (id != SC_SVAL) {
        return -1;
    }
    gui_set_size(app, SC_SVAL, 60, 0);
    gui_set_fill(app, SC_SVAL, 1);
    gui_set_align(app, SC_SVAL, GA_RIGHT);
    scene_num(app, SC_SVAL, 35, "");
    id = gui_add(app, GK_PROGRESS, 0, null);
    if (id != SC_PROG) {
        return -1;
    }
    gui_set_grow(app, SC_PROG, 1);
    gui_set_fill(app, SC_PROG, 1);
    gui_set_range(app, SC_PROG, 0, 100);
    gui_set_value(app, SC_PROG, 20);
    id = gui_add(app, GK_PANEL, 0, null);
    if (id != SC_FROW) {
        return -1;
    }
    gui_set_layout(app, SC_FROW, GL_ROW);
    gui_set_pad(app, SC_FROW, 0, 8);
    gui_set_size(app, SC_FROW, 0, 34);
    gui_set_fill(app, SC_FROW, 1);
    id = gui_add(app, GK_FIELD, SC_FROW, "type here");
    if (id != SC_FIELD) {
        return -1;
    }
    gui_set_grow(app, SC_FIELD, 1);
    gui_set_fill(app, SC_FIELD, 1);
    id = gui_add(app, GK_BUTTON, SC_FROW, "echo");
    if (id != SC_ECHO) {
        return -1;
    }
    gui_set_size(app, SC_ECHO, 110, 0);
    gui_set_fill(app, SC_ECHO, 1);
    id = gui_add(app, GK_LABEL, 0, "ready");
    if (id != SC_STATUS) {
        return -1;
    }
    gui_set_fill(app, SC_STATUS, 1);
    return 0;
}

fn scene_echo(app: &mut GApp) {
    let fp: ptr<u8> = gui_field_text(app, SC_FIELD);
    if (fp == null) {
        return;
    }
    gui_set_buf(app, SC_STATUS, fp);
}

fn scene_drain(app: &mut GApp) -> i64 {
    var ev: GEvent = zero(GEvent);
    var n: i64 = 0;
    while (gui_next_event(app, &mut ev) == 1) {
        n += 1;
        if (ev.code == GEV_CLICK) {
            if (ev.id == SC_INC) {
                let cur: i64 = gui_value(app, SC_COUNT) + 1;
                gui_set_value(app, SC_COUNT, cur);
                scene_num(app, SC_COUNT, cur, "count ");
            } else if (ev.id == SC_RESET) {
                gui_set_value(app, SC_COUNT, 0);
                scene_num(app, SC_COUNT, 0, "count ");
                gui_set_value(app, SC_SLIDER, 35);
                scene_num(app, SC_SVAL, 35, "");
                gui_set_buf(app, SC_STATUS, "reset");
            } else if (ev.id == SC_QUIT) {
                app.quit = 1;
            } else if (ev.id == SC_ECHO) {
                scene_echo(app);
            }
        } else if (ev.code == GEV_CHANGE && ev.id == SC_SLIDER) {
            scene_num(app, SC_SVAL, ev.value, "");
        } else if (ev.code == GEV_SUBMIT && ev.id == SC_FIELD) {
            scene_echo(app);
        }
    }
    return n;
}

fn scene_tick(appp: i64, frame: i64) {
    let ap: ptr<GApp> = appp as ptr<GApp>;
    unsafe { scene_tick_ref(&mut *ap, frame); }
}

fn scene_tick_ref(app: &mut GApp, frame: i64) {
    scene_drain(app);
    var v: i64 = frame * 4 % 101;
    if (v > 100) {
        v = 100;
    }
    gui_set_value(app, SC_PROG, v);
}
