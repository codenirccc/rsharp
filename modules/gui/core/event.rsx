const GEV_CLICK: i64 = 1;
const GEV_TOGGLE: i64 = 2;
const GEV_CHANGE: i64 = 3;
const GEV_SUBMIT: i64 = 4;
const GEV_FOCUS: i64 = 5;
const GEV_BLUR: i64 = 6;
const GEV_TIMER: i64 = 7;
const GEV_CLOSE: i64 = 8;

struct GEvent {
    id: i64,
    code: i64,
    value: i64
}
