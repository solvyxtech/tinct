#!/usr/bin/env python3
"""Layout assertions for the picker, across terminal sizes and selections.

Renders frames with `tinct __frame` and checks the things that were wrong
before there was a viewport: the cursor has to be on screen, the frame has to
fit the window, and no row may overflow the width.
"""
import os, re, subprocess, sys, unicodedata

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TINCT = os.path.join(ROOT, "bin", "tinct")
ANSI = re.compile(r"\033\[[0-9;?]*[A-Za-z]|\033\][^\a]*\a")

fails = []
checks = 0


def width(s):
    """Display columns, ignoring escapes."""
    s = ANSI.sub("", s)
    w = 0
    for ch in s:
        if unicodedata.combining(ch):
            continue
        w += 2 if unicodedata.east_asian_width(ch) in ("W", "F") else 1
    return w


def check(cond, label):
    global checks
    checks += 1
    if not cond:
        fails.append(label)


def frame(shell, idx, rows, cols, filt="", home=None):
    env = dict(os.environ)
    env["TINCT_SHELL"] = shell
    if home:
        env["TINCT_HOME"] = home
    r = subprocess.run(
        [TINCT, "__frame", str(idx), str(rows), str(cols), filt],
        capture_output=True, text=True, env=env, stdin=subprocess.DEVNULL,
    )
    if r.returncode != 0:
        fails.append(f"{shell}: __frame exited {r.returncode}: {r.stderr.strip()[:200]}")
        return []
    body = r.stdout.replace("\033[H\033[2J", "")
    return body.split("\n")


def themes(shell, home):
    env = dict(os.environ)
    env["TINCT_SHELL"] = shell
    if home:
        env["TINCT_HOME"] = home
    r = subprocess.run([TINCT, "ls"], capture_output=True, text=True, env=env,
                       stdin=subprocess.DEVNULL)
    names = []
    for line in r.stdout.splitlines():
        line = ANSI.sub("", line).strip()
        if line.startswith("* "):
            line = line[2:]
        if line:
            names.append(line.split()[0])
    return names


SIZES = [
    (28, 116),   # the reported window
    (24, 80),    # the classic default
    (50, 200),   # tall and wide
    (20, 100),
    (16, 90),
    (12, 46),    # cramped
    (10, 40),
    (8, 34),     # absurd, must still not corrupt the screen
    (30, 79),    # one column, just under the two-pane threshold
]

for shell in ("zsh", os.environ.get("TINCT_BASH", "/opt/homebrew/bin/bash")):
    label = "zsh" if shell == "zsh" else "bash"
    names = themes(shell, None)
    if not names:
        fails.append(f"{label}: no themes listed")
        continue
    n = len(names)

    for rows, cols in SIZES:
        for idx in (0, 1, n // 2, n - 2, n - 1):
            lines = frame(shell, idx, rows, cols)
            tag = f"{label} {rows}x{cols} idx={idx}"

            check(len(lines) <= rows, f"{tag}: frame is {len(lines)} lines, window is {rows}")

            over = [(i, width(l)) for i, l in enumerate(lines) if width(l) > cols]
            check(not over, f"{tag}: rows overflow width: {over[:3]}")

            plain = [ANSI.sub("", l) for l in lines]
            cursor = [l for l in plain if "▸" in l]
            check(len(cursor) == 1, f"{tag}: expected exactly one cursor row, got {len(cursor)}")
            if cursor:
                check(names[idx] in cursor[0],
                      f"{tag}: cursor row is {cursor[0].strip()!r}, wanted {names[idx]!r}")

            check(any("tinct" in l for l in plain), f"{tag}: header missing")
            check(lines[-1].strip() != "" or rows < 10, f"{tag}: last row is blank")

# The last row must not end with a newline, or a full-height frame scrolls the
# alt screen and drags the header off the top.
env = dict(os.environ); env["TINCT_SHELL"] = "zsh"
raw = subprocess.run([TINCT, "__frame", "10", "28", "116"], capture_output=True,
                     text=True, env=env, stdin=subprocess.DEVNULL).stdout
check(not raw.endswith("\n"), "frame must not end with a newline")

# Filtering narrows the list and keeps the cursor consistent.
for shell in ("zsh", os.environ.get("TINCT_BASH", "/opt/homebrew/bin/bash")):
    label = "zsh" if shell == "zsh" else "bash"
    lines = [ANSI.sub("", l) for l in frame(shell, 0, 28, 116, "mono")]
    body = "\n".join(lines)
    check("mono-amber" in body, f"{label}: filter 'mono' should match mono-amber")
    check("gruvbox-dark" not in body, f"{label}: filter 'mono' should exclude gruvbox-dark")
    check(any("/mono" in l for l in lines), f"{label}: filter should be shown in the header")

    lines = [ANSI.sub("", l) for l in frame(shell, 0, 28, 116, "zzzznope")]
    body = "\n".join(lines)
    check("nothing matches" in body, f"{label}: a filter matching nothing should say so")
    check("▸" not in body, f"{label}: no cursor row when nothing matches")

# Two-pane above the threshold, one pane below it.
wide = [ANSI.sub("", l) for l in frame("zsh", 0, 28, 116)]
narrow = [ANSI.sub("", l) for l in frame("zsh", 0, 28, 60)]
check(any("│" in l and len(l.strip()) > 30 for l in wide), "wide: preview should sit beside the list")
check(not any("contrast" in l and "│" in l for l in narrow), "narrow: preview should not sit beside the list")

print(f"render: {checks - len(fails)}/{checks} checks passed")
for f in fails:
    print("  FAIL", f)
sys.exit(1 if fails else 0)
