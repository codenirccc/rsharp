fn gui_push(app: &mut GApp, id: i64, code: i64, value: i64) {
    if (app.nev >= GUI_MAX_EVENTS) {
        return;
    }
    let at: i64 = (app.evh + app.nev) % GUI_MAX_EVENTS;
    app.events[at].id = id;
    app.events[at].code = code;
    app.events[at].value = value;
    app.nev += 1;
}

fn gui_next_event(app: &mut GApp, ev: &mut GEvent) -> i32 {
    if (app.nev <= 0) {
        return 0;
    }
    let at: i64 = app.evh;
    ev.id = app.events[at].id;
    ev.code = app.events[at].code;
    ev.value = app.events[at].value;
    app.evh = (app.evh + 1) % GUI_MAX_EVENTS;
    app.nev -= 1;
    return 1;
}
