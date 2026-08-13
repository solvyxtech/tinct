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

# CI machines are slower than a laptop; scale the pty waits rather than let
# these turn into flakes.
SLOW = float(os.environ.get("TINCT_TEST_SLOW", "1"))

def _bash():
    """bash 4+ to test against. run.sh exports TINCT_BASH; fall back to PATH so
    the suites also work when run directly, including on Linux where Homebrew
    paths do not exist."""
    import shutil as _sh
    return os.environ.get("TINCT_BASH") or _sh.which("bash") or "bash"


fails = []
checks = 0


def check(cond, label):
    global checks
    checks += 1
    if not cond:
        fails.append(label)


def run(shell, args, keys, home, rows=28, cols=116, extra_env=None):
    """Run tinct under a pty, send keys, return (output, exit code)."""
    # Every TINCT_ variable goes, not a named few: the suite is often run from
    # a shell that has the integration loaded and exports state of its own.
    env = {k: v for k, v in os.environ.items() if not k.startswith("TINCT_")}
    env.update({
        "TINCT_SHELL": shell, "TINCT_HOME": home,
        "TERM": "xterm-256color", "LINES": str(rows), "COLUMNS": str(cols),
    })
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

    pump(0.5 * SLOW)
    for k in keys:
        os.write(fd, KEYS.get(k, k.encode()))
        pump(0.22 * SLOW)
    pump(0.5 * SLOW)
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


def sandbox(default=None):
    default = default or FIRST
    home = tempfile.mkdtemp(prefix="tinct-test-")
    os.makedirs(os.path.join(home, "themes"), exist_ok=True)
    os.makedirs(os.path.join(home, "sessions"), exist_ok=True)
    with open(os.path.join(home, "default"), "w") as f:
        f.write(default + "\n")
    return home


def pinned_of(home):
    """The theme pinned to the pty this run used.

    The tty name is allocated by the kernel, so rather than guess it, read
    back whichever session file the run created -- there is only ever one.
    """
    d = os.path.join(home, "sessions")
    names = [n for n in os.listdir(d)] if os.path.isdir(d) else []
    if len(names) != 1:
        return None
    return open(os.path.join(d, names[0])).read().strip()


def pinned_count(home):
    d = os.path.join(home, "sessions")
    return len(os.listdir(d)) if os.path.isdir(d) else 0


def default_of(home):
    p = os.path.join(home, "default")
    return open(p).read().strip() if os.path.exists(p) else None


ANSI_RE = re.compile(r"\033\[[0-9;?]*[A-Za-z]")


def theme_names():
    """The theme list in the order the picker shows it.

    Derived rather than hardcoded: positions shift every time a theme is
    added, and a test that says "the third one" should not care which.
    """
    env = {k: v for k, v in os.environ.items() if not k.startswith("TINCT_")}
    env["TINCT_HOME"] = tempfile.mkdtemp(prefix="tinct-ls-")
    r = subprocess.run([TINCT, "ls"], capture_output=True, text=True, env=env,
                       stdin=subprocess.DEVNULL)
    out = []
    for line in r.stdout.splitlines():
        line = ANSI_RE.sub("", line).strip()
        if line.startswith("* "):
            line = line[2:]
        if line:
            out.append(line.split()[0])
    shutil.rmtree(env["TINCT_HOME"], ignore_errors=True)
    return out


NAMES = theme_names()
FIRST, SECOND, THIRD, LAST = NAMES[0], NAMES[1], NAMES[2], NAMES[-1]

SHELLS = ["zsh", _bash()]

for shell in SHELLS:
    tag = "zsh" if shell == "zsh" else "bash"

    # --- cancelling changes nothing -----------------------------------------
    home = sandbox()
    out, code = run(shell, [], ["q"], home)
    check(code == 0, f"{tag}: quitting exits cleanly (got {code})")
    check("cancelled" in out, f"{tag}: quitting says it cancelled")
    check(pinned_of(home) is None, f"{tag}: quitting pins nothing")
    check(default_of(home) == FIRST, f"{tag}: quitting leaves the default alone")
    check("\033[?1049h" in out, f"{tag}: enters the alternate screen")
    check("\033[?1049l" in out, f"{tag}: leaves the alternate screen")
    check("\033[?25h" in out, f"{tag}: puts the cursor back")
    shutil.rmtree(home)

    # --- moving and choosing -------------------------------------------------
    home = sandbox()
    out, code = run(shell, [], ["down", "down", "enter"], home)
    check(pinned_of(home) == THIRD,
          f"{tag}: two downs and enter pins the third theme (got {pinned_of(home)})")
    check(f"{THIRD} set for this terminal" in out, f"{tag}: confirms what it set")
    check(default_of(home) == FIRST, f"{tag}: pinning does not touch the default")
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
    check(pinned_of(home) == LAST,
          f"{tag}: end jumps to the last theme (got {pinned_of(home)})")
    shutil.rmtree(home)

    # --- filtering -----------------------------------------------------------
    home = sandbox()
    out, _ = run(shell, [], ["/", "n", "o", "r", "d", "enter", "enter"], home)
    check(pinned_of(home) == "nord", f"{tag}: filter then enter picks nord (got {pinned_of(home)})")
    shutil.rmtree(home)

    # --- d sets the default too, A paints every terminal --------------------
    home = sandbox()
    out, _ = run(shell, [], ["down", "d"], home)
    check(default_of(home) == SECOND,
          f"{tag}: 'd' makes it the default for new terminals (got {default_of(home)})")
    check(pinned_of(home) == SECOND, f"{tag}: 'd' also pins it here")
    shutil.rmtree(home)

    home = sandbox()
    out, _ = run(shell, [], ["down", "A"], home)
    check("applied to" in out, f"{tag}: 'A' reports how many terminals it painted")
    check(pinned_count(home) >= 1, f"{tag}: 'A' records a theme per terminal")
    check(default_of(home) == FIRST, f"{tag}: 'A' leaves the default alone")
    shutil.rmtree(home)

    home = sandbox()
    out, _ = run(shell, [], ["/", "z", "z", "z", "q"], home)
    check("nothing matches" in ANSI.sub("", out), f"{tag}: a filter matching nothing says so")
    check(pinned_of(home) is None, f"{tag}: a dead filter changes nothing")
    shutil.rmtree(home)

    home = sandbox()
    out, _ = run(shell, [], ["/", "n", "o", "r", "d", "^U", "enter", "enter"], home)
    check(pinned_of(home) == FIRST,
          f"{tag}: ctrl-u wipes the filter back to the whole list (got {pinned_of(home)})")
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
    saved = os.path.join(home, "themes", f"{SECOND}.theme")
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
        check(pinned_of(home) == "nord", f"{tag}: saving pins it to this terminal")
        check(default_of(home) == FIRST, f"{tag}: saving leaves the default alone")
    shutil.rmtree(home)

    # --- editing a bundled theme must not touch the repo --------------------
    bundled = os.path.join(ROOT, "themes", "nord.theme")
    before = open(bundled).read()
    home = sandbox()
    run(shell, ["edit", "nord"], ["down", "right", "w", "q"], home)
    check(open(bundled).read() == before, f"{tag}: editing never writes to the bundled themes")
    shutil.rmtree(home)

# --- the terminal picker ------------------------------------------------------
# TINCT_TTY may hold several device paths, so the picker can be pointed at
# ordinary files standing in for terminals. Nothing here touches a real window.
def terminal_picker_case(shell, tag):
    home = sandbox()
    box = tempfile.mkdtemp(prefix="tinct-ttys-")
    fakes = [os.path.join(box, "termA"), os.path.join(box, "termB")]
    for f in fakes:
        open(f, "w").close()

    out, code = run(shell, ["sessions"], ["down", "enter", "down", "enter", "q"],
                    home, extra_env={"TINCT_TTY": "\n".join(fakes)})

    check(code == 0, f"{tag}: terminal picker exits cleanly (got {code})")
    plain = ANSI_RE.sub("", out)
    check("open" in plain and "change one" in plain,
          f"{tag}: terminal picker draws its header")

    a = open(fakes[0]).read()
    b = open(fakes[1]).read()
    check("\033]11;" in b, f"{tag}: the chosen terminal is painted")
    check(a == "", f"{tag}: the other terminal is left completely alone")

    names = os.listdir(os.path.join(home, "sessions"))
    check(len(names) == 1, f"{tag}: exactly one terminal is pinned (got {names})")
    if names:
        check("termB" in names[0],
              f"{tag}: the pin lands on the terminal that was selected (got {names[0]})")
        pinned = open(os.path.join(home, "sessions", names[0])).read().strip()
        check(pinned == SECOND,
              f"{tag}: the pin records the theme that was chosen (got {pinned})")

    check(default_of(home) == FIRST, f"{tag}: changing another terminal leaves the default alone")
    shutil.rmtree(home, ignore_errors=True)
    shutil.rmtree(box, ignore_errors=True)


def terminal_picker_unpin(shell, tag):
    home = sandbox()
    box = tempfile.mkdtemp(prefix="tinct-ttys-")
    fake = os.path.join(box, "termA")
    open(fake, "w").close()
    key = fake.replace("/", "-")
    os.makedirs(os.path.join(home, "sessions"), exist_ok=True)
    open(os.path.join(home, "sessions", key), "w").write(LAST + "\n")

    out, _ = run(shell, ["sessions"], ["c", "q"], home,
                 extra_env={"TINCT_TTY": fake})
    check(not os.path.exists(os.path.join(home, "sessions", key)),
          f"{tag}: 'c' unpins the selected terminal")
    check("\033]11;" in open(fake).read(),
          f"{tag}: unpinning repaints that terminal with the default")
    shutil.rmtree(home, ignore_errors=True)
    shutil.rmtree(box, ignore_errors=True)


for shell in SHELLS:
    tag = "zsh" if shell == "zsh" else "bash"
    terminal_picker_case(shell, tag)
    terminal_picker_unpin(shell, tag)

print(f"interactive: {checks - len(fails)}/{checks} checks passed")
for f in fails:
    print("  FAIL", f)
sys.exit(1 if fails else 0)
