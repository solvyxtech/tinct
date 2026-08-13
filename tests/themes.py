#!/usr/bin/env python3
"""Quality checks for every bundled theme.

A theme can parse perfectly and still be unusable: dim text the same shade as
the background, a selection you cannot read, a cursor you cannot find. These
are the checks that catch that, applied to every theme in the repo so a new one
cannot quietly ship broken.
"""
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
THEMES = os.path.join(ROOT, "themes")
HEX = re.compile(r"^#[0-9A-Fa-f]{6}$")

# The palette is optional by design: a theme may set only the window colors and
# leave the terminal's own 16 colors alone (warm-charcoal does exactly that).
# What is present still has to be valid.
REQUIRED = ["LABEL", "DESC", "BG", "FG", "CURSOR", "SEL_BG", "SEL_FG"]
PALETTE = [f"ANSI{i}" for i in range(16)]

# Thresholds. Body text gets the WCAG AA bar; the rest get the looser
# "can a person actually see this" bar.
AA_TEXT = 4.5
MIN_DIM = 2.2      # ANSI8, which is what dim text uses
MIN_ANSI = 2.2     # colored text must separate from the background
MIN_SEL = 2.5      # selected text against its highlight
MIN_CURSOR = 1.8   # you have to be able to find the cursor

fails, warns, checks = [], [], 0


def check(cond, label, soft=False):
    global checks
    checks += 1
    if not cond:
        (warns if soft else fails).append(label)


def parse(path):
    d = {}
    for line in open(path):
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        d[k.strip()] = v.strip()
    return d


def rgb(h):
    h = h.lstrip("#")
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


def lum(h):
    def ch(v):
        v /= 255
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = rgb(h)
    return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b)


def contrast(a, b):
    la, lb = lum(a), lum(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def dist(a, b):
    return sum(abs(x - y) for x, y in zip(rgb(a), rgb(b)))


themes = {}
files = sorted(f for f in os.listdir(THEMES) if f.endswith(".theme"))
check(len(files) > 0, "there are themes to check")

for f in files:
    name = f[:-6]
    d = parse(os.path.join(THEMES, f))
    themes[name] = d

    for key in REQUIRED:
        check(key in d, f"{name}: missing {key}")
    if not all(k in d for k in REQUIRED):
        continue

    present = [k for k in PALETTE if k in d]
    check(len(present) in (0, 16),
          f"{name}: has {len(present)} palette entries — set all 16 or none")

    for key in REQUIRED[2:] + present:
        check(bool(HEX.match(d[key])), f"{name}: {key} is not a #RRGGBB color ({d[key]!r})")
    if not all(HEX.match(d[k]) for k in REQUIRED[2:] + present):
        continue
    full = len(present) == 16

    check(len(d["DESC"]) >= 8, f"{name}: description is too short to be useful")
    check(len(d["DESC"]) <= 60, f"{name}: description is too long for the picker ({len(d['DESC'])})")

    bg = d["BG"]
    c = contrast(d["FG"], bg)
    check(c >= AA_TEXT, f"{name}: body text contrast {c:.1f}:1 is below AA ({AA_TEXT})")

    if full:
        c = contrast(d["ANSI8"], bg)
        check(c >= MIN_DIM, f"{name}: dim text (ANSI8) contrast {c:.1f}:1 — it will be unreadable")

        for i in list(range(1, 7)) + list(range(9, 15)):
            c = contrast(d[f"ANSI{i}"], bg)
            check(c >= MIN_ANSI, f"{name}: ANSI{i} contrast {c:.1f}:1 against the background")

    c = contrast(d["SEL_FG"], d["SEL_BG"])
    check(c >= MIN_SEL, f"{name}: selected text contrast {c:.1f}:1")

    c = contrast(d["CURSOR"], bg)
    check(c >= MIN_CURSOR, f"{name}: cursor contrast {c:.1f}:1 — hard to find")

    # A selection that matches the background is invisible as a selection.
    check(dist(d["SEL_BG"], bg) >= 24, f"{name}: selection background is too close to the background")

    if full:
        # ANSI0 doubling as the background makes block-drawn UIs disappear.
        check(dist(d["ANSI0"], bg) >= 8 or d["ANSI0"] == bg,
              f"{name}: ANSI0 is almost-but-not-quite the background")

        # The bright half should actually be bright, or bold text does nothing.
        # Several well-known palettes genuinely do not define a separate bright
        # half, so this is a note rather than a failure.
        same = sum(1 for i in range(8) if d[f"ANSI{i}"] == d[f"ANSI{i+8}"])
        check(same <= 3, f"{name}: {same} of 8 bright colors match their normal pair", soft=True)

# No two themes should be near-copies of each other.
names = sorted(themes)
for i, a in enumerate(names):
    for b in names[i + 1:]:
        da, db = themes[a], themes[b]
        keys = [k for k in REQUIRED[2:] + PALETTE
                if k in da and k in db and HEX.match(da[k]) and HEX.match(db[k])]
        total = sum(dist(da[k], db[k]) for k in keys)
        check(total > 60, f"{a} and {b} are nearly the same theme (distance {total})")

light = [n for n, d in themes.items() if "BG" in d and HEX.match(d["BG"]) and lum(d["BG"]) > 0.5]
print(f"themes: {checks - len(fails)}/{checks} checks passed "
      f"({len(files)} themes, {len(light)} light, {len(files) - len(light)} dark)")
for w in warns:
    print("  note", w)
for f in fails:
    print("  FAIL", f)
sys.exit(1 if fails else 0)
