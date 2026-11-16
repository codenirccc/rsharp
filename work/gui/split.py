import os
import sys

SRC = sys.argv[1]
ROOT = sys.argv[2]

ORDER = [
    "core/sys.rsx",
    "core/limits.rsx",
    "core/math.rsx",
    "core/color.rsx",
    "core/surface.rsx",
    "core/theme.rsx",
    "core/widget.rsx",
    "core/event.rsx",
    "core/app.rsx",
    "text/font.rsx",
    "text/measure.rsx",
    "text/format.rsx",
    "text/glyph.rsx",
    "text/draw.rsx",
    "buffer/copy.rsx",
    "layout/natural.rsx",
    "layout/constraints.rsx",
    "layout/arrange.rsx",
    "api/widget.rsx",
    "api/event.rsx",
    "input/keys.rsx",
    "input/hit.rsx",
    "input/focus.rsx",
    "input/pointer.rsx",
    "input/wheel.rsx",
    "input/field_edit.rsx",
    "input/keyboard.rsx",
    "input/timer.rsx",
    "paint/text.rsx",
    "paint/render.rsx",
    "widgets/panel.rsx",
    "widgets/label.rsx",
    "widgets/button.rsx",
    "widgets/check.rsx",
    "widgets/field.rsx",
    "widgets/slider.rsx",
    "widgets/progress.rsx",
]

MAP = {}
def put(path, names):
    for n in names:
        if n in MAP:
            sys.exit("name %s mapped twice" % n)
        MAP[n] = path

put("core/sys.rsx", ["malloc", "free", "memset", "strlen"])
put("core/limits.rsx", ["GUI_MAX_WIDGETS", "GUI_MAX_EVENTS", "GUI_TEXT_MAX"])
put("core/math.rsx", ["gui_clampi"])
put("core/color.rsx", ["GColor", "gui_col", "gui_word"])
put("core/surface.rsx", ["GSurface", "gs_clear", "gs_fill", "gs_rect", "gs_hline", "gs_vline"])
put("core/theme.rsx", ["GTheme", "gui_theme_dark", "gui_theme_light"])
put("core/widget.rsx", [
    "GK_PANEL", "GK_LABEL", "GK_BUTTON", "GK_CHECK", "GK_FIELD", "GK_SLIDER", "GK_PROGRESS",
    "GL_COL", "GL_ROW", "GA_LEFT", "GA_CENTER", "GA_RIGHT", "GWidget",
])
put("core/event.rsx", [
    "GEV_CLICK", "GEV_TOGGLE", "GEV_CHANGE", "GEV_SUBMIT", "GEV_FOCUS", "GEV_BLUR",
    "GEV_TIMER", "GEV_CLOSE", "GEvent",
])
put("core/app.rsx", ["GApp", "gui_app_init", "gui_app_free"])
put("text/measure.rsx", ["gui_len", "gui_text_w", "gui_text_h"])
put("text/format.rsx", ["gui_itoa"])
put("text/glyph.rsx", ["gs_char"])
put("text/draw.rsx", ["gs_text"])
put("buffer/copy.rsx", ["gui_copy"])
put("layout/natural.rsx", ["gui_natural_w", "gui_natural_h"])
put("layout/constraints.rsx", ["gui_min_size"])
put("layout/arrange.rsx", ["gui_layout_children", "gui_layout"])
put("api/widget.rsx", [
    "gui_add",
    "gui_set_size", "gui_set_grow", "gui_set_fill", "gui_set_pad", "gui_set_layout",
    "gui_set_align", "gui_set_text", "gui_set_visible", "gui_set_enabled", "gui_set_range",
    "gui_set_value", "gui_value", "gui_widget_x", "gui_widget_y", "gui_widget_w",
    "gui_widget_h", "gui_focus", "gui_set_number", "gui_set_buf", "gui_field_text",
])
put("api/event.rsx", ["gui_push", "gui_next_event"])
put("input/keys.rsx", [
    "VK_BACK", "VK_TAB", "VK_RETURN", "VK_ESCAPE", "VK_SPACE", "VK_END", "VK_HOME",
    "VK_LEFT", "VK_UP", "VK_RIGHT", "VK_DOWN", "VK_DELETE",
])
put("input/hit.rsx", ["gui_hit"])
put("input/focus.rsx", ["gui_set_focus", "gui_field_caret_at"])
put("input/pointer.rsx", ["gui_slider_at", "gui_mouse_move", "gui_mouse_down", "gui_mouse_up"])
put("input/wheel.rsx", ["gui_wheel"])
put("input/field_edit.rsx", ["gui_field_insert", "gui_field_delete"])
put("input/keyboard.rsx", ["gui_key"])
put("input/timer.rsx", ["gui_timer"])
put("paint/text.rsx", ["gui_draw_text_c"])
put("paint/render.rsx", ["gui_render", "gui_hash"])
put("widgets/panel.rsx", ["gui_draw_panel"])
put("widgets/label.rsx", ["gui_draw_label"])
put("widgets/button.rsx", ["gui_draw_button"])
put("widgets/check.rsx", ["gui_draw_check"])
put("widgets/field.rsx", ["gui_draw_field"])
put("widgets/slider.rsx", ["gui_draw_slider"])
put("widgets/progress.rsx", ["gui_draw_progress"])

lines = open(SRC, "r").read().split("\n")
items = []
i = 0
n = len(lines)
while i < n:
    raw = lines[i]
    s = raw.strip()
    if s == "":
        i += 1
        continue
    if not (s.startswith("fn ") or s.startswith("struct ") or s.startswith("const ")
            or s.startswith("extern fn ") or s.startswith("include ")):
        sys.exit("bare top-level line %d: %r" % (i + 1, raw))
    start = i
    if s.startswith("include ") or s.startswith("extern fn ") or s.startswith("const "):
        while not lines[i].rstrip().endswith(";"):
            i += 1
        i += 1
    else:
        depth = 0
        while True:
            depth += lines[i].count("{") - lines[i].count("}")
            i += 1
            if depth == 0:
                break
    if s.startswith("fn "):
        name = s[3:].split("(")[0].strip()
    elif s.startswith("struct "):
        name = s[7:].split()[0].strip()
    elif s.startswith("const "):
        name = s[6:].split(":")[0].strip()
    elif s.startswith("extern fn "):
        name = s[10:].split("(")[0].strip()
    else:
        name = None
    body = "\n".join(lines[start:i])
    items.append((name, body))

out = {}
for name, body in items:
    if name is None:
        continue
    f = MAP.get(name)
    if f is None:
        sys.exit("unmapped item: %r" % name)
    out.setdefault(f, []).append(body)

PREBUILT = {"text/font.rsx"}
missing = [f for f in ORDER if f not in out and f not in PREBUILT]
if missing:
    sys.exit("empty targets: %r" % missing)
extra = [f for f in out if f not in ORDER]
if extra:
    sys.exit("targets not in order: %r" % extra)

def join(bodies):
    parts = []
    prev_const = False
    for b in bodies:
        is_const = b.startswith("const ")
        if parts:
            parts.append("\n" if (is_const and prev_const) else "\n\n")
        parts.append(b)
        prev_const = is_const
    return "".join(parts)


for f in ORDER:
    if f in PREBUILT:
        continue
    path = os.path.join(ROOT, f)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", newline="\n") as fh:
        fh.write(join(out[f]) + "\n")

structs = {}
for f in ORDER:
    for body in out.get(f, []):
        if body.startswith("struct "):
            structs[body.split()[1]] = ORDER.index(f)
bad = []
for f in ORDER:
    text = "\n".join(out.get(f, []))
    for sname, sidx in structs.items():
        if sname in text and ORDER.index(f) < sidx:
            bad.append((f, sname))
if bad:
    sys.exit("struct used before declaration: %r" % bad)

with open(os.path.join(ROOT, "gui.rsx"), "w", newline="\n") as fh:
    for f in ORDER:
        fh.write('include "%s";\n' % f)

print("items=%d files=%d" % (len(items), len(out)))
