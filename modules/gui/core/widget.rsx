const GK_PANEL: i64 = 0;
const GK_LABEL: i64 = 1;
const GK_BUTTON: i64 = 2;
const GK_CHECK: i64 = 3;
const GK_FIELD: i64 = 4;
const GK_SLIDER: i64 = 5;
const GK_PROGRESS: i64 = 6;
const GK_CANVAS: i64 = 7;
const GL_COL: i64 = 0;
const GL_ROW: i64 = 1;
const GA_LEFT: i64 = 0;
const GA_CENTER: i64 = 1;
const GA_RIGHT: i64 = 2;

struct GWidget {
    kind: i64,
    id: i64,
    parent: i64,
    layout: i64,
    pad: i64,
    gap: i64,
    x: i64,
    y: i64,
    w: i64,
    h: i64,
    fw: i64,
    fh: i64,
    grow: i64,
    fill: i64,
    align: i64,
    visible: i64,
    enabled: i64,
    hot: i64,
    active: i64,
    focus: i64,
    value: i64,
    vmin: i64,
    vmax: i64,
    caret: i64,
    blen: i64,
    text: ptr<u8>,
    bword: u32,
    bsize: i64,
    ink: ptr<u8>,
    iw: i64,
    ih: i64,
    buf: [u8; GUI_TEXT_MAX]
}
