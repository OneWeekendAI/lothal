#!/usr/bin/env bash
# ===========================================================================
#  Lothal v0.2.0 — release announcement poster
#
#  Run it in a dark terminal and screenshot it. The poster is a FIXED size and
#  centres itself, so the shot looks the same on every machine — it does not
#  stretch to fill the window (stretching is what made the first version look
#  like a debug dump rather than a poster).
#
#  Usage:  bash announce-lothal.sh
#
#  Env:
#    LOTHAL_WIDTH=100    poster width in columns (minimum 86)
#    LOTHAL_COLOR=256    force a colour depth: truecolor | 256 | none
#
#  Colour note, because this is what broke the first attempt: 24-bit escapes
#  (\e[38;2;r;g;bm) are IGNORED by Terminal.app and several others, which is
#  why the original rendered as flat grey with no cyan and no green bar. So the
#  default here is 256-colour, which every terminal in use understands; exact
#  RGB is used only when COLORTERM advertises it.
# ===========================================================================

exec python3 - "$@" <<'PY'
import os, shutil, unicodedata

# ---- brand palette (LothalTheme, straight off icon.svg) --------------------
BG     = (0x17, 0x1A, 0x1F)   # panel
INK    = (0xE3, 0xE8, 0xF0)   # frame white
STEEL  = (0x4E, 0x55, 0x5F)   # motor rings
CYAN   = (0x66, 0xD1, 0xF5)   # accent / front-right arm
GREEN  = (0x7E, 0xE7, 0x87)   # live
MUTED  = (0x6B, 0x74, 0x84)   # secondary text
RULE   = (0x2E, 0x33, 0x3B)   # hairlines

# ---- colour depth ----------------------------------------------------------
def _depth():
    forced = os.environ.get("LOTHAL_COLOR", "").lower()
    if forced in ("truecolor", "24bit", "rgb"): return "truecolor"
    if forced in ("256", "8bit"): return "256"
    if forced in ("none", "no", "off", "mono"): return "none"
    if os.environ.get("COLORTERM", "").lower() in ("truecolor", "24bit"): return "truecolor"
    return "256"

DEPTH = _depth()

# The xterm-256 palette, built once: the 6x6x6 colour cube (whose levels are
# NOT evenly spaced) followed by the 24-step grey ramp.
_STEPS = (0, 95, 135, 175, 215, 255)
_PALETTE = [(16 + 36 * r + 6 * g + b, (_STEPS[r], _STEPS[g], _STEPS[b]))
            for r in range(6) for g in range(6) for b in range(6)]
_PALETTE += [(232 + i, (8 + i * 10,) * 3) for i in range(24)]

def _to256(rgb):
    """Nearest palette entry by distance across all three channels at once.

    Quantising each channel independently into the cube is what tinted this
    palette: #E3E8F0 has r and g landing on 215 while b rounds up to 255, and
    the near-white frame comes out lavender; #2E333B does the same in reverse
    and the hairlines come out teal. Both are within a couple of steps of the
    GREY ramp, which a whole-colour search finds and a per-channel one cannot,
    because it has already committed to the cube before it can compare.
    """
    r, g, b = rgb
    return min(_PALETTE, key=lambda e: (e[1][0] - r) ** 2
                                     + (e[1][1] - g) ** 2
                                     + (e[1][2] - b) ** 2)[0]

def fg(rgb):
    if DEPTH == "none": return ""
    if DEPTH == "truecolor": return "\x1b[38;2;%d;%d;%dm" % rgb
    return "\x1b[38;5;%dm" % _to256(rgb)

def bg(rgb):
    if DEPTH == "none": return ""
    if DEPTH == "truecolor": return "\x1b[48;2;%d;%d;%dm" % rgb
    return "\x1b[48;5;%dm" % _to256(rgb)

RESET, BOLD, DIM = "\x1b[0m", "\x1b[1m", "\x1b[2m"

# ---- display width ---------------------------------------------------------
# Not len(): a glyph like ✔ or ● is East-Asian *ambiguous* and many terminals
# render it two cells wide. The first version padded by codepoint count, which
# is exactly why the table's verticals did not line up with its own borders.
# The rule here is simple — measure honestly, and use no ambiguous glyphs.
import re as _re
_ANSI = _re.compile(r"\x1b\[[0-9;]*m")

def vlen(s):
    s = _ANSI.sub("", s)
    n = 0
    for ch in s:
        if unicodedata.combining(ch): continue
        n += 2 if unicodedata.east_asian_width(ch) in ("W", "F") else 1
    return n

def pad(s, w, align="l"):
    d = w - vlen(s)
    if d <= 0: return s
    if align == "c": return " " * (d // 2) + s + " " * (d - d // 2)
    if align == "r": return " " * d + s
    return s + " " * d

# ---------------------------------------------------------------------------
#  The mark
#
#  Drawn from icon.svg's own geometry rather than re-invented, in the SVG's
#  coordinate space. The first version filled the propeller circles solid,
#  which is why it read as a bowtie: in the real mark they are 5-unit STROKES,
#  the thin discs a spinning prop sweeps. Everything below is the icon's
#  numbers, unchanged.
# ---------------------------------------------------------------------------
#  Strokes are THINNER than the icon's, deliberately. The icon is drawn at
#  1024px where a 15-unit arm and a 13-unit body outline read as clean lines;
#  at forty-odd character cells those same widths are four or five pixels and
#  the arms, hubs and body merge into one white mass with a hole in it. The
#  proportions that matter at poster size — arm length, prop radius, the 5"
#  ratio that makes the discs clear each other — are untouched.
STROKE = 0.60
PROP_R, PROP_W = 36.0, 5.0 * STROKE + 1.2
ARM_W, HUB_R = 15.0 * STROKE, 11.0 * STROKE
BODY = (99.0, 97.0, 42.0, 46.0, 10.0)   # x, y, w, h, rx
BODY_W = 13.0 * STROKE
MOTORS = [(76, 76), (164, 76), (76, 164), (164, 164)]
ARMS = [((100, 100), (76, 76)), ((140, 140), (164, 164)),
        ((100, 140), (76, 164)), ((140, 100), (164, 76))]
# Front-right is identified by its COORDINATES, not by an index into two lists
# that happen to be ordered differently — indexing both by 3 put the cyan arm
# at the top right and the cyan hub at the bottom left of it, on opposite
# corners of the aircraft.
FRONT_RIGHT = (164, 76)
VIEW = (28.0, 212.0)                     # square window around the whole mark

def _seg_d(px, py, a, b):
    (ax, ay), (bx, by) = a, b
    vx, vy = bx - ax, by - ay
    wx, wy = px - ax, py - ay
    t = max(0.0, min(1.0, (wx * vx + wy * vy) / (vx * vx + vy * vy)))
    return ((wx - t * vx) ** 2 + (wy - t * vy) ** 2) ** 0.5

def _rrect_d(px, py):
    """Signed distance to a rounded rect's outline — negative inside."""
    x, y, w, h, r = BODY
    cx, cy = x + w / 2.0, y + h / 2.0
    dx, dy = abs(px - cx) - (w / 2.0 - r), abs(py - cy) - (h / 2.0 - r)
    outside = (max(dx, 0.0) ** 2 + max(dy, 0.0) ** 2) ** 0.5
    return outside + min(max(dx, dy), 0.0) - r

def ink_at(u, v):
    """Colour of the mark at (u, v) in 0..1, or None for background."""
    x = VIEW[0] + u * (VIEW[1] - VIEW[0])
    y = VIEW[0] + v * (VIEW[1] - VIEW[0])

    # Painted in the icon's own z-order: hubs, body, arms, prop discs.
    for m in MOTORS:
        if ((x - m[0]) ** 2 + (y - m[1]) ** 2) ** 0.5 <= HUB_R:
            return CYAN if m == FRONT_RIGHT else INK
    if abs(_rrect_d(x, y)) <= BODY_W / 2.0:
        return INK
    for a, b in ARMS:
        if _seg_d(x, y, a, b) <= ARM_W / 2.0:
            return CYAN if b == FRONT_RIGHT else INK
    for mx, my in MOTORS:
        if abs(((x - mx) ** 2 + (y - my) ** 2) ** 0.5 - PROP_R) <= PROP_W / 2.0:
            return STEEL
    return None

SS = 4   # supersampling grid per half-block pixel

def sample(ix, iy, px, py):
    """The dominant colour over one pixel's area, or None if mostly empty.

    A single sample at the pixel centre is not enough here: the propeller ring
    is a 5-unit stroke across a ~184-unit view, so at this size it is THINNER
    THAN ONE PIXEL and point-sampling catches it only where it happens to line
    up with a sample point — which is what turned four circles into four
    squircles. Area coverage is what makes a sub-pixel stroke read as a curve.
    """
    tally = {}
    for sy in range(SS):
        for sx in range(SS):
            u = (ix + (sx + 0.5) / SS) / px
            v = (iy + (sy + 0.5) / SS) / py
            c = ink_at(u, v)
            if c is not None:
                tally[c] = tally.get(c, 0) + 1
    if not tally: return None
    best = max(tally, key=tally.get)
    # Below a third of the area the pixel is more background than mark; drawing
    # it anyway is what thickens a thin stroke into a blob.
    return best if tally[best] >= (SS * SS) / 3.0 else None

def render_mark(cols):
    """Half-block art, `cols` wide. Two vertical samples per row keeps the
    pixels square, so the propeller circles come out round instead of as the
    wide ovals the stretch-to-fit version produced."""
    rows = int(round(cols / 2.0))
    px, py = cols, rows * 2
    out = []
    for r in range(rows):
        line, run, cur = "", "", object()
        for c in range(cols):
            top = sample(c, 2 * r, px, py)
            bot = sample(c, 2 * r + 1, px, py)
            if top == bot:      cell = (top, " " if top is None else "█")
            elif top is None:   cell = (bot, "▄")
            elif bot is None:   cell = (top, "▀")
            else:               cell = ((top, bot), None)
            if cell[1] is None:                       # two different colours
                if run: line += (fg(cur) if cur else "") + run; run = ""
                t, b = cell[0]
                # RESET and nothing else. Re-arming a background here painted
                # the rest of the row in panel colour — the dark bar that
                # appeared beside the front-right arm.
                line += fg(t) + bg(b) + "▀" + RESET
                cur = object()
                continue
            if cell[0] == cur: run += cell[1]
            else:
                if run: line += (fg(cur) if cur else "") + run
                cur, run = cell[0], cell[1]
        if run: line += (fg(cur) if cur else "") + run
        out.append(line + RESET)
    return out

# ---------------------------------------------------------------------------
#  Poster
# ---------------------------------------------------------------------------
# Clamped, not free: below this the longest prose line runs past the right
# column and wraps into the mark, which is worse than a poster that is simply
# wider than a small window and scrolls.
W = max(86, int(os.environ.get("LOTHAL_WIDTH", 100)))
MARK_W = 42
GAP = 5
RIGHT_W = W - MARK_W - GAP

def wordmark():
    return BOLD + fg(INK) + "L O T H A L" + RESET

def rule(w, c=RULE):
    return fg(c) + "─" * w + RESET

def right_column():
    c = []
    c.append(fg(MUTED) + "RELEASE" + RESET + fg(RULE) + "  ·  " + RESET
             + fg(MUTED) + "12 AUGUST 2026" + RESET)
    c.append("")
    c.append(wordmark() + "   " + fg(CYAN) + BOLD + "v0.2.0" + RESET)
    c.append(rule(RIGHT_W))
    c.append("")
    c.append(fg(INK) + "Now live on all three platforms." + RESET)
    c.append("")
    c.append(fg(MUTED) + "The flight model moved into a native Rust" + RESET)
    c.append(fg(MUTED) + "core, and Windows and Linux builds now ship" + RESET)
    c.append(fg(MUTED) + "alongside macOS." + RESET)
    c.append("")

    rows = [("macOS", "11+ Universal", "latest/macos"),
            ("Windows", "10 / 11 x64", "latest/windows"),
            ("Linux", "x86-64", "latest/linux")]
    for name, build, path in rows:
        c.append("  " + fg(INK) + pad(name, 9) + RESET
                 + fg(MUTED) + pad(build, 15) + RESET
                 + fg(GREEN) + pad("live", 6) + RESET
                 + fg(RULE) + "/" + path + RESET)
    c.append("")
    c.append(rule(RIGHT_W))
    c.append("  " + fg(MUTED) + "download" + RESET + "   "
             + BOLD + fg(CYAN) + "dl.meetdev.in" + RESET)
    return c

def build_poster():
    mark = render_mark(MARK_W)
    right = right_column()

    # The mark sits optically centred against the text block rather than top-
    # aligned; a poster reads as composed only when the two columns balance.
    height = max(len(mark), len(right))
    m_top = max(0, (height - len(mark)) // 2)
    r_top = max(0, (height - len(right)) // 2)

    out = []
    out.append("")
    out.append(rule(W, RULE))
    out.append("")
    for i in range(height):
        left = mark[i - m_top] if 0 <= i - m_top < len(mark) else ""
        text = right[i - r_top] if 0 <= i - r_top < len(right) else ""
        out.append(pad(left, MARK_W) + " " * GAP + text)
    out.append("")

    strip = "  Build an FPV drone from real parts.  Fly it.  Feel the difference.  "
    out.append(bg(GREEN) + fg(BG) + BOLD + pad(strip, W) + RESET)
    out.append("")
    return out

# ---- run -------------------------------------------------------------------
term = shutil.get_terminal_size((W, 40)).columns
indent = " " * max(0, (term - W) // 2)
for line in build_poster():
    print(indent + line if line else "")
PY
