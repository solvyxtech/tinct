#!/usr/bin/env python3
"""Tests for the shell integration.

Everything here runs in a pty, because the integration only does anything when
stdout is a terminal. The escapes it writes go straight to that pty, so the
captured output is what the terminal would actually have received.
"""
import os, pty, select, struct, sys, tempfile, termios, fcntl, time, shutil

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INIT = os.path.join(ROOT, "shell", "init.sh")

NORD_BG = "\033]11;#2E3440\a"
SOLAR_LIGHT_BG = "\033]11;#FDF6E3\a"
GRUV_BG = "\033]11;#282828\a"
EMBER_BG = "\033]11;#151210\a"

fails = []
checks = 0


def check(cond, label):
    global checks
    checks += 1
    if not cond:
        fails.append(label)


def run_script(shell_argv, script, home, interrupt_after=None, wait=3.0):
    env = dict(os.environ)
    env.update({"TINCT_HOME": home, "TERM": "xterm-256color"})
    for k in ("TINCT_TTY", "TINCT_ROWS", "TINCT_COLS", "TINCT_DISABLE"):
        env.pop(k, None)

    pid, fd = pty.fork()
    if pid == 0:
        os.environ.clear()
        os.environ.update(env)
        os.execvp(shell_argv[0], shell_argv + ["-c", script])
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))

    out = bytearray()
    start = time.time()
    sent = False
    while time.time() - start < wait:
        if interrupt_after and not sent and time.time() - start > interrupt_after:
            os.write(fd, b"\003")
            sent = True
        r, _, _ = select.select([fd], [], [], 0.05)
        if r:
            try:
                chunk = os.read(fd, 65536)
            except OSError:
                break
            if not chunk:
                break
            out.extend(chunk)
    try:
        os.close(fd)
    except OSError:
        pass
    try:
        os.waitpid(pid, os.WNOHANG)
    except ChildProcessError:
        pass
    return out.decode("utf-8", "replace")


def sandbox(default="gruvbox-dark", rules=None, sessions=None):
    home = tempfile.mkdtemp(prefix="tinct-wrap-")
    os.makedirs(os.path.join(home, "themes"), exist_ok=True)
    os.makedirs(os.path.join(home, "sessions"), exist_ok=True)
    open(os.path.join(home, "default"), "w").write(default + "\n")
    if rules:
        open(os.path.join(home, "rules"), "w").write(rules)
    for tty, theme in (sessions or {}).items():
        open(os.path.join(home, "sessions", tty), "w").write(theme + "\n")
    return home


SHELLS = [["zsh", "-f"], [os.environ.get("TINCT_BASH", "/opt/homebrew/bin/bash"), "--norc"]]

for argv in SHELLS:
    tag = "zsh" if argv[0] == "zsh" else "bash"

    # --- painting without launching anything --------------------------------
    home = sandbox()
    out = run_script(argv, f". {INIT}; tinct_paint nord", home)
    check(NORD_BG in out, f"{tag}: tinct_paint writes the theme to the terminal")
    check("\033]104\a" in out, f"{tag}: tinct_paint clears the old palette first")
    shutil.rmtree(home)

    # --- a new shell picks up the default -----------------------------------
    home = sandbox(default="gruvbox-dark")
    out = run_script(argv, f". {INIT}; tinct_sync", home)
    check(GRUV_BG in out, f"{tag}: a new terminal gets the default theme")
    shutil.rmtree(home)

    # --- a pinned terminal beats the default --------------------------------
    home = sandbox(default="gruvbox-dark")
    out = run_script(
        argv,
        f'. {INIT}; mkdir -p "$TINCT_HOME/sessions"; '
        f'printf nord > "$TINCT_HOME/sessions/$TINCT_TTY_NAME"; '
        f"TINCT_SHOWING=''; tinct_sync",
        home,
    )
    check(NORD_BG in out, f"{tag}: a pinned terminal keeps its own theme")
    check(GRUV_BG not in out, f"{tag}: a pinned terminal ignores the default")
    shutil.rmtree(home)

    # --- directory rules ------------------------------------------------------
    home = sandbox(default="gruvbox-dark", rules="dir /tmp = solarized-light\n")
    out = run_script(argv, f'. {INIT}; cd /tmp; tinct_sync', home)
    check(SOLAR_LIGHT_BG in out, f"{tag}: a directory rule themes that directory")

    out = run_script(argv, f'. {INIT}; cd /; tinct_sync', home)
    check(GRUV_BG in out, f"{tag}: a directory with no rule falls back to the default")

    # a pin outranks a directory rule
    out = run_script(
        argv,
        f'. {INIT}; printf nord > "$TINCT_HOME/sessions/$TINCT_TTY_NAME"; '
        f'cd /tmp; TINCT_SHOWING=""; tinct_sync',
        home,
    )
    check(NORD_BG in out, f"{tag}: a pin outranks a directory rule")
    check(SOLAR_LIGHT_BG not in out, f"{tag}: the directory rule is skipped when pinned")
    shutil.rmtree(home)

    # --- repainting only when the answer changes ----------------------------
    home = sandbox(default="gruvbox-dark", rules="dir /tmp = solarized-light\n")
    out = run_script(argv, f'. {INIT}; cd /tmp; tinct_sync; tinct_sync; tinct_sync', home)
    check(out.count(SOLAR_LIGHT_BG) == 1,
          f"{tag}: syncing repeatedly repaints once, not every time "
          f"(saw {out.count(SOLAR_LIGHT_BG)})")
    shutil.rmtree(home)

    # --- the cd hook fires without an explicit sync --------------------------
    home = sandbox(default="gruvbox-dark", rules="dir /tmp = solarized-light\n")
    # zsh runs chpwd hooks; bash re-evaluates PROMPT_COMMAND. Under -c there is
    # no prompt, so call it the way the shell would.
    if tag == "zsh":
        script = f'. {INIT}; tinct_enable_auto; cd /tmp'
    else:
        script = f'. {INIT}; tinct_enable_auto; cd /tmp; eval "$PROMPT_COMMAND"'
    out = run_script(argv, script, home)
    check(GRUV_BG in out, f"{tag}: enabling the hook paints the default immediately")
    check(SOLAR_LIGHT_BG in out, f"{tag}: cd into a rule'd directory repaints via the hook")
    check(out.index(GRUV_BG) < out.index(SOLAR_LIGHT_BG),
          f"{tag}: the default lands before the directory rule")
    shutil.rmtree(home)

    # --- wrapping a command --------------------------------------------------
    home = sandbox(default="gruvbox-dark")
    out = run_script(argv, f'. {INIT}; tinct_wrap sleep solarized-light; sleep 0.2', home)
    check(SOLAR_LIGHT_BG in out, f"{tag}: a wrapped command applies its theme")
    check(out.rindex(GRUV_BG) > out.index(SOLAR_LIGHT_BG),
          f"{tag}: a wrapped command restores the terminal afterwards")
    shutil.rmtree(home)

    # --- interrupting still restores -----------------------------------------
    home = sandbox(default="gruvbox-dark")
    out = run_script(argv, f'. {INIT}; tinct_wrap sleep solarized-light; sleep 5', home,
                     interrupt_after=0.8, wait=3.0)
    check(SOLAR_LIGHT_BG in out, f"{tag}: interrupt case applied the theme first")
    check(out.rindex(GRUV_BG) > out.index(SOLAR_LIGHT_BG),
          f"{tag}: interrupting a wrapped command still restores")
    shutil.rmtree(home)

    # --- piped output is left alone -----------------------------------------
    home = sandbox()
    out = run_script(argv, f'. {INIT}; tinct_wrap echo solarized-light; echo hi | cat > /dev/null', home)
    check(SOLAR_LIGHT_BG not in out, f"{tag}: a wrapped command writing to a pipe emits nothing")
    shutil.rmtree(home)

    # --- ssh by host rule ----------------------------------------------------
    home = sandbox(default="gruvbox-dark", rules="host prod-* = ember\n")
    # `ssh` is replaced by a stub on PATH so nothing leaves the machine.
    stub = os.path.join(home, "bin")
    os.makedirs(stub, exist_ok=True)
    with open(os.path.join(stub, "ssh"), "w") as f:
        f.write("#!/bin/sh\necho \"stub ssh $*\"\n")
    os.chmod(os.path.join(stub, "ssh"), 0o755)

    out = run_script(argv, f'PATH="{stub}:$PATH"; . {INIT}; tinct_wrap_ssh; ssh prod-db1', home)
    check(EMBER_BG in out, f"{tag}: ssh to a matching host applies its theme")
    check("stub ssh prod-db1" in out, f"{tag}: ssh still runs the real command")
    check(out.rindex(GRUV_BG) > out.index(EMBER_BG), f"{tag}: ssh restores on exit")

    out = run_script(argv, f'PATH="{stub}:$PATH"; . {INIT}; tinct_wrap_ssh; ssh someone@prod-db1', home)
    check(EMBER_BG in out, f"{tag}: ssh strips user@ before matching the host")

    out = run_script(argv, f'PATH="{stub}:$PATH"; . {INIT}; tinct_wrap_ssh; ssh -p 2222 prod-db1', home)
    check(EMBER_BG in out, f"{tag}: ssh skips option arguments when finding the host")

    out = run_script(argv, f'PATH="{stub}:$PATH"; . {INIT}; tinct_wrap_ssh; ssh example.com', home)
    check(EMBER_BG not in out, f"{tag}: ssh to an unmatched host is left alone")
    check("stub ssh example.com" in out, f"{tag}: unmatched ssh still runs")
    shutil.rmtree(home)

    # --- PATH, refusals, opt-out ---------------------------------------------
    home = sandbox()
    out = run_script(argv, f'. {INIT}; command -v tinct', home)
    check("bin/tinct" in out, f"{tag}: sourcing init puts tinct on PATH")

    out = run_script(argv, f". {INIT}; tinct_wrap 'rm -rf /' 2>&1", home)
    check("not a usable command name" in out, f"{tag}: refuses a bogus command name")

    out = run_script(argv, f'. {INIT}; TINCT_DISABLE=1 tinct_sync', home)
    check(GRUV_BG not in out, f"{tag}: TINCT_DISABLE stops it painting anything")
    shutil.rmtree(home)

print(f"wrap: {checks - len(fails)}/{checks} checks passed")
for f in fails:
    print("  FAIL", f)
sys.exit(1 if fails else 0)
