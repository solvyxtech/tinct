#!/usr/bin/env python3
"""Drive the picker and the editor through a real pty, in both shells.

The layout tests check what a frame looks like; these check that keys do what
they claim, that the chosen theme actually reaches the terminal, and that the
terminal is handed back in the state it was lent in.
"""
import os, pty, re, select, shutil, struct, subprocess, sys, tempfile, termios, fcntl, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TINCT = os.path.join(ROOT, "bin", "tinct")
ANSI = re.compile(r"\033\[[0-9;?]*[A-Za-z]|\033\][^\a]*\a")

KEYS = {
    "up": b"\033[A", "down": b"\033[B", "right": b"\033[C", "left": b"\033[D",
    "enter": b"\r", "esc": b"\033", "^C": b"\003", "^U": b"\025", "bs": b"\177",
    "pgdn": b"\033[6~", "pgup": b"\033[5~", "end": b"\033[F", "home": b"\033[H",
}

fails = []
checks = 0


def check(cond, label):
    global checks
    checks += 1
    if not cond:
        fails.append(label)


def run(shell, args, keys, home, rows=28, cols=116, extra_env=None):
    """Run tinct under a pty, send keys, return (output, exit code)."""
    env = dict(os.environ)
    env.update({
        "TINCT_SHELL": shell, "TINCT_HOME": home,
        "TERM": "xterm-256color", "LINES": str(rows), "COLUMNS": str(cols),
    })
    env.pop("TINCT_ROWS", None)
    env.pop("TINCT_COLS", None)
    if extra_env:
        env.update(extra_env)

    pid, fd = pty.fork()
    if pid == 0:
        os.environ.clear()
        os.environ.update(env)
        os.execv(TINCT, [TINCT] + args)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))

    out = bytearray()

    def pump(sec):
        end = time.time() + sec
        while time.time() < end:
            r, _, _ = select.select([fd], [], [], 0.02)
            if r:
                try:
                    chunk = os.read(fd, 65536)
                except OSError:
                    return
                if not chunk:
                    return
                out.extend(chunk)

    pump(0.5)
    for k in keys:
        os.write(fd, KEYS.get(k, k.encode()))
        pump(0.22)
    pump(0.5)
    try:
        os.close(fd)
    except OSError:
        pass
    try:
        _, status = os.waitpid(pid, 0)
        code = os.waitstatus_to_exitcode(status)
    except ChildProcessError:
        code = 0
    return out.decode("utf-8", "replace"), code


def sandbox(active="arctic-dim"):
    home = tempfile.mkdtemp(prefix="tinct-test-")
    os.makedirs(os.path.join(home, "themes"), exist_ok=True)
    with open(os.path.join(home, "active"), "w") as f:
        f.write(active + "\n")
    return home


def active_of(home):
    p = os.path.join(home, "active")
    return open(p).read().strip() if os.path.exists(p) else None


SHELLS = ["zsh", os.environ.get("TINCT_BASH", "/opt/homebrew/bin/bash")]

for shell in SHELLS:
    tag = "zsh" if shell == "zsh" else "bash"

    # --- cancelling changes nothing -----------------------------------------
    home = sandbox()
    out, code = run(shell, [], ["q"], home)
    check(code == 0, f"{tag}: quitting exits cleanly (got {code})")
    check("cancelled" in out, f"{tag}: quitting says it cancelled")
    check(active_of(home) == "arctic-dim", f"{tag}: quitting leaves the saved theme alone")
    check("\033[?1049h" in out, f"{tag}: enters the alternate screen")
    check("\033[?1049l" in out, f"{tag}: leaves the alternate screen")
    check("\033[?25h" in out, f"{tag}: puts the cursor back")
    shutil.rmtree(home)

    # --- moving and choosing -------------------------------------------------
    home = sandbox()
    out, code = run(shell, [], ["down", "down", "enter"], home)
    check(active_of(home) == "copper-patina",
          f"{tag}: two downs and enter picks the third theme (got {active_of(home)})")
    check("theme set to copper-patina" in out, f"{tag}: confirms the theme it set")
    shutil.rmtree(home)

    # --- the cursor stays visible while walking a long way down --------------
    home = sandbox()
    out, _ = run(shell, [], ["pgdn"] * 4 + ["q"], home, rows=28, cols=116)
    frames = out.split("\033[H\033[2J")
    last = ANSI.sub("", frames[-1])
    check("▸" in last, f"{tag}: cursor is on screen after paging down")
    shutil.rmtree(home)

    home = sandbox()
    out, _ = run(shell, [], ["end", "enter"], home)
    check(active_of(home) == "wine-cellar",
          f"{tag}: end jumps to the last theme (got {active_of(home)})")
    shutil.rmtree(home)

    # --- filtering -----------------------------------------------------------
    home = sandbox()
    out, _ = run(shell, [], ["/", "n", "o", "r", "d", "enter", "enter"], home)
    check(active_of(home) == "nord", f"{tag}: filter then enter picks nord (got {active_of(home)})")
    shutil.rmtree(home)

    home = sandbox()
    out, _ = run(shell, [], ["/", "z", "z", "z", "q"], home)
    check("nothing matches" in ANSI.sub("", out), f"{tag}: a filter matching nothing says so")
    check(active_of(home) == "arctic-dim", f"{tag}: a dead filter changes nothing")
    shutil.rmtree(home)

    home = sandbox()
    out, _ = run(shell, [], ["/", "n", "o", "r", "d", "^U", "enter", "enter"], home)
    check(active_of(home) == "arctic-dim",
          f"{tag}: ctrl-u wipes the filter back to the whole list (got {active_of(home)})")
    shutil.rmtree(home)

    # --- the theme actually reaches the terminal ----------------------------
    home = sandbox()
    cap = os.path.join(home, "cap")
    out, _ = run(shell, [], ["/", "n", "o", "r", "d", "enter", "enter"], home,
                 extra_env={"TINCT_TTY": cap})
    painted = open(cap).read() if os.path.exists(cap) else ""
    check("\033]11;#2E3440" in painted, f"{tag}: nord's background was written to the terminal")
    check("\033]104" in painted, f"{tag}: the previous palette was cleared first")
    shutil.rmtree(home)

    # --- interrupt must not strand the terminal ------------------------------
    home = sandbox()
    out, code = run(shell, [], ["down", "^C"], home)
    check("\033[?1049l" in out, f"{tag}: ctrl-c still leaves the alternate screen")
    check("\033[?25h" in out, f"{tag}: ctrl-c still restores the cursor")
    shutil.rmtree(home)

    # --- 'e' hands the picker's highlighted theme to the editor -------------
    home = sandbox()
    out, code = run(shell, [], ["down", "e", "down", "right", "w", "q"], home)
    check(code == 0, f"{tag}: picker hands off to the editor cleanly (got {code})")
    saved = os.path.join(home, "themes", "catppuccin-mocha.theme")
    check(os.path.exists(saved),
          f"{tag}: 'e' edits the highlighted theme, not the saved one")
    shutil.rmtree(home)

    # --- editor --------------------------------------------------------------
    home = sandbox()
    out, code = run(shell, ["edit", "nord"], ["down", "right", "right", "q"], home)
    check(code == 0, f"{tag}: editor exits cleanly (got {code})")
    check("discarded" in out, f"{tag}: editor warns that unsaved edits were dropped")
    shutil.rmtree(home)

    home = sandbox()
    out, code = run(shell, ["edit", "nord"], ["down", "right", "right", "w", "q"], home)
    saved = os.path.join(home, "themes", "nord.theme")
    check(os.path.exists(saved), f"{tag}: 'w' writes the theme into the user's own directory")
    if os.path.exists(saved):
        body = open(saved).read()
        check("FG=" in body and "BG=" in body, f"{tag}: saved theme keeps its colors")
        check(active_of(home) == "nord", f"{tag}: saving makes it the default")
    shutil.rmtree(home)

    # --- editing a bundled theme must not touch the repo --------------------
    bundled = os.path.join(ROOT, "themes", "nord.theme")
    before = open(bundled).read()
    home = sandbox()
    run(shell, ["edit", "nord"], ["down", "right", "w", "q"], home)
    check(open(bundled).read() == before, f"{tag}: editing never writes to the bundled themes")
    shutil.rmtree(home)

print(f"interactive: {checks - len(fails)}/{checks} checks passed")
for f in fails:
    print("  FAIL", f)
sys.exit(1 if fails else 0)
