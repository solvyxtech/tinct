#!/usr/bin/env python3
"""Tests for the shell integration: tinct_wrap / tinct_run.

Runs each case in a pty so the wrapper sees a real terminal on stdout, with
TINCT_TTY pointed at a file so the escapes it emits can be read back.
"""
import os, pty, select, struct, sys, tempfile, termios, fcntl, time, shutil

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INIT = os.path.join(ROOT, "shell", "init.sh")

fails = []
checks = 0


def check(cond, label):
    global checks
    checks += 1
    if not cond:
        fails.append(label)


def run_script(shell_argv, script, home, cap, interrupt_after=None, wait=3.0):
    env = dict(os.environ)
    env.update({"TINCT_HOME": home, "TINCT_TTY": cap, "TERM": "xterm-256color"})
    env.pop("TINCT_ROWS", None)
    env.pop("TINCT_COLS", None)

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


def sandbox(active="nord"):
    home = tempfile.mkdtemp(prefix="tinct-wrap-")
    os.makedirs(os.path.join(home, "themes"), exist_ok=True)
    open(os.path.join(home, "active"), "w").write(active + "\n")
    return home


SHELLS = [["zsh", "-f"], [os.environ.get("TINCT_BASH", "/opt/homebrew/bin/bash"), "--norc"]]

for argv in SHELLS:
    tag = "zsh" if argv[0] == "zsh" else "bash"
    home = sandbox()
    cap = os.path.join(home, "cap")

    # --- a wrapped command themes on entry and resets on exit ---------------
    run_script(argv, f". {INIT}; tinct_wrap sleep; sleep 0.2", home, cap)
    painted = open(cap).read() if os.path.exists(cap) else ""
    check("\033]11;#2E3440" in painted, f"{tag}: wrapped command applies the active theme")
    check("\033]111" in painted, f"{tag}: wrapped command resets the terminal on exit")
    check(painted.index("\033]11;#2E3440") < painted.index("\033]111"),
          f"{tag}: theme is applied before it is reset")
    open(cap, "w").close()

    # --- a specific theme per command ---------------------------------------
    run_script(argv, f". {INIT}; tinct_wrap sleep solarized-light; sleep 0.2", home, cap)
    painted = open(cap).read() if os.path.exists(cap) else ""
    check("\033]11;#FDF6E3" in painted, f"{tag}: a named theme overrides the active one")
    open(cap, "w").close()

    # --- interrupting must still hand the terminal back ---------------------
    run_script(argv, f". {INIT}; tinct_wrap sleep; sleep 5", home, cap,
               interrupt_after=0.8, wait=3.0)
    painted = open(cap).read() if os.path.exists(cap) else ""
    check("\033]111" in painted, f"{tag}: interrupting a wrapped command still resets")
    open(cap, "w").close()

    # --- piped output is left alone -----------------------------------------
    run_script(argv, f". {INIT}; tinct_wrap echo; echo hi | cat > /dev/null", home, cap)
    painted = open(cap).read() if os.path.exists(cap) else ""
    check(painted == "", f"{tag}: a wrapped command writing to a pipe emits nothing")
    open(cap, "w").close()

    # --- nesting does not re-theme ------------------------------------------
    run_script(argv, f". {INIT}; tinct_wrap sleep; TINCT_WRAPPED=1 sleep 0.2", home, cap)
    painted = open(cap).read() if os.path.exists(cap) else ""
    check(painted == "", f"{tag}: an already-wrapped command is passed straight through")
    open(cap, "w").close()

    # --- PATH and refusals ---------------------------------------------------
    out = run_script(argv, f". {INIT}; command -v tinct", home, cap)
    check("bin/tinct" in out, f"{tag}: sourcing init puts tinct on PATH")

    out = run_script(argv, f". {INIT}; tinct_wrap 'rm -rf /' 2>&1", home, cap)
    check("not a usable command name" in out, f"{tag}: refuses a bogus command name")

    shutil.rmtree(home)

print(f"wrap: {checks - len(fails)}/{checks} checks passed")
for f in fails:
    print("  FAIL", f)
sys.exit(1 if fails else 0)
