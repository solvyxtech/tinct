#!/usr/bin/env python3
"""Hostile conditions: bad input, bad paths, bad permissions, races.

The other suites check that tinct does the right thing when everything is
normal. This one checks it fails cleanly when things are not: unreadable
config, corrupt themes, a home directory with spaces in it, two processes
writing at once, no terminal at all. Nothing here should hang, crash, print a
stack trace, or leave state half-written.
"""
import os, shutil, subprocess, sys, tempfile, time
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TINCT = os.path.join(ROOT, "bin", "tinct")
def _bash():
    """bash 4+ to test against. run.sh exports TINCT_BASH; fall back to PATH so
    the suites also work when run directly, including on Linux where Homebrew
    paths do not exist."""
    import shutil as _sh
    return os.environ.get("TINCT_BASH") or _sh.which("bash") or "bash"


SHELLS = ["zsh", _bash()]

fails, checks = [], 0


def check(cond, label):
    global checks
    checks += 1
    if not cond:
        fails.append(label)


def run(args, home=None, shell=None, timeout=25, extra=None, binary=TINCT):
    env = dict(os.environ)
    for k in ("TINCT_TTY", "TINCT_ROWS", "TINCT_COLS", "TINCT_HOME", "TINCT_SHELL"):
        env.pop(k, None)
    if home:
        env["TINCT_HOME"] = home
    if shell:
        env["TINCT_SHELL"] = shell
    if extra:
        env.update(extra)
    try:
        return subprocess.run([binary] + args, capture_output=True, text=True,
                              env=env, stdin=subprocess.DEVNULL, timeout=timeout)
    except subprocess.TimeoutExpired:
        return None


def sandbox(default="nord", suffix=""):
    home = tempfile.mkdtemp(prefix="tinct-qc-", suffix=suffix)
    os.makedirs(os.path.join(home, "themes"), exist_ok=True)
    os.makedirs(os.path.join(home, "sessions"), exist_ok=True)
    if default:
        open(os.path.join(home, "default"), "w").write(default + "\n")
    return home


def clean(r, label, expect_zero=True):
    """A result that did not hang, did not trace back, and used the right code."""
    check(r is not None, f"{label}: hung")
    if r is None:
        return
    check("Traceback" not in r.stderr and "line " not in r.stderr.split("\n")[0].lower()
          or "tinct:" in r.stderr,
          f"{label}: raw interpreter error: {r.stderr.strip()[:160]}")
    for noise in ("command not found", "syntax error", "bad pattern",
                  "parse error", "unbound variable", "bad substitution",
                  "no such file or directory"):
        check(noise not in r.stderr.lower(), f"{label}: shell error {noise!r}: {r.stderr.strip()[:160]}")
    if expect_zero:
        check(r.returncode == 0, f"{label}: exit {r.returncode}, stderr={r.stderr.strip()[:120]}")


for shell in SHELLS:
    tag = "zsh" if shell == "zsh" else "bash"

    # --- awkward paths --------------------------------------------------------
    for suffix, desc in ((" with spaces", "spaces"), ("_'quoted'", "quotes"),
                         (" (parens)", "parens")):
        home = sandbox(suffix=suffix)
        r = run(["ls"], home, shell)
        clean(r, f"{tag}: config path with {desc}")
        if r:
            check("nord" in r.stdout, f"{tag}: lists themes from a path with {desc}")
        r = run(["set", "nord"], home, shell)
        clean(r, f"{tag}: set into a path with {desc}")
        r = run(["which"], home, shell)
        clean(r, f"{tag}: which from a path with {desc}")
        shutil.rmtree(home, ignore_errors=True)

    # --- the checkout itself living somewhere awkward ------------------------
    box = tempfile.mkdtemp(prefix="tinct-qc-")
    spaced = os.path.join(box, "my tools", "tinct copy")
    os.makedirs(os.path.dirname(spaced), exist_ok=True)
    shutil.copytree(ROOT, spaced, ignore=shutil.ignore_patterns(".git"))
    home = sandbox()
    r = run(["ls"], home, shell, binary=os.path.join(spaced, "bin", "tinct"))
    clean(r, f"{tag}: checkout at a path with spaces")
    if r:
        check("nord" in r.stdout, f"{tag}: finds bundled themes from a spaced checkout")

    # --- reached through a symlink on PATH -----------------------------------
    linkdir = os.path.join(box, "bin")
    os.makedirs(linkdir, exist_ok=True)
    link = os.path.join(linkdir, "tinct")
    os.symlink(os.path.join(spaced, "bin", "tinct"), link)
    r = run(["ls"], home, shell, binary=link)
    clean(r, f"{tag}: invoked through a symlink")
    if r:
        check("nord" in r.stdout, f"{tag}: symlinked binary still finds lib/ and themes/")
    shutil.rmtree(box, ignore_errors=True)
    shutil.rmtree(home, ignore_errors=True)

    # --- no themes at all -----------------------------------------------------
    empty = tempfile.mkdtemp(prefix="tinct-qc-")
    os.makedirs(os.path.join(empty, "themes"), exist_ok=True)
    r = run(["ls"], empty, shell, extra={"TINCT_BUNDLED_DIR": os.path.join(empty, "none")})
    check(r is not None, f"{tag}: no themes at all: hung")
    if r:
        check(r.returncode != 0, f"{tag}: listing no themes exits non-zero")
        check("no themes" in (r.stderr + r.stdout).lower(),
              f"{tag}: listing no themes says so plainly")
    shutil.rmtree(empty, ignore_errors=True)

    # --- corrupt and hostile theme files -------------------------------------
    home = sandbox()
    td = os.path.join(home, "themes")
    open(os.path.join(td, "empty.theme"), "w").close()
    open(os.path.join(td, "nokeys.theme"), "w").write("just some prose\nno equals signs\n")
    open(os.path.join(td, "crlf.theme"), "w", newline="").write(
        "LABEL=CRLF\r\nDESC=carriage returns\r\nBG=#101010\r\nFG=#F0F0F0\r\n")
    open(os.path.join(td, "badhex.theme"), "w").write(
        "LABEL=Bad\nDESC=nonsense colors\nBG=zzzzzz\nFG=#12\nANSI0=notacolor\nANSI99=#FFFFFF\n")
    open(os.path.join(td, "novalue.theme"), "w").write("LABEL=\nDESC=\nBG=\nFG=\n")
    with open(os.path.join(td, "binary.theme"), "wb") as f:
        f.write(bytes(range(256)) * 4)
    os.makedirs(os.path.join(td, "adirectory.theme"), exist_ok=True)

    r = run(["ls"], home, shell)
    clean(r, f"{tag}: listing with corrupt themes present")
    for name in ("empty", "nokeys", "crlf", "badhex", "novalue", "binary"):
        r = run(["apply", name], home, shell)
        clean(r, f"{tag}: applying corrupt theme {name!r}")
    r = run(["apply", "crlf"], home, shell)
    if r:
        check("\r" not in r.stdout, f"{tag}: CRLF theme does not emit carriage returns")
        check("#101010" in r.stdout, f"{tag}: CRLF theme still parses its colors")
    r = run(["apply", "badhex"], home, shell)
    if r:
        check("zzzzzz" not in r.stdout, f"{tag}: an invalid hex is not passed to the terminal")
    r = run(["__frame", "0", "24", "100"], home, shell)
    clean(r, f"{tag}: rendering a frame with corrupt themes present")
    shutil.rmtree(home, ignore_errors=True)

    # --- corrupt state files --------------------------------------------------
    home = sandbox()
    open(os.path.join(home, "default"), "w").write("deleted-theme\n")
    r = run(["which"], home, shell)
    clean(r, f"{tag}: default naming a theme that does not exist")
    open(os.path.join(home, "default"), "w").write("")
    r = run(["which"], home, shell)
    clean(r, f"{tag}: empty default file")
    open(os.path.join(home, "default"), "wb").write(b"\x00\x01\x02binary\n")
    r = run(["which"], home, shell)
    clean(r, f"{tag}: binary default file")
    open(os.path.join(home, "default"), "w").write("nord\n")
    open(os.path.join(home, "sessions", "ttys999"), "w").write("also-deleted\n")
    r = run(["sessions"], home, shell)
    clean(r, f"{tag}: session naming a theme that does not exist")
    shutil.rmtree(home, ignore_errors=True)

    # --- unwritable config ----------------------------------------------------
    # Skipped as root: root ignores the permission bits, so the case cannot be
    # set up at all. CI containers run as root; laptops do not.
    home = sandbox()
    if os.geteuid() == 0:
        shutil.rmtree(home, ignore_errors=True)
        home = None
    if home:
      os.chmod(home, 0o500)
      try:
        r = run(["set", "dracula"], home, shell)
        check(r is not None, f"{tag}: unwritable config: hung")
        if r:
            check("Traceback" not in r.stderr, f"{tag}: unwritable config does not trace back")
            check("#" in r.stdout or r.returncode != 0,
                  f"{tag}: unwritable config either paints or fails, not neither")
      finally:
        os.chmod(home, 0o700)
        shutil.rmtree(home, ignore_errors=True)

    # --- bad arguments --------------------------------------------------------
    home = sandbox()
    for args, label in (
        (["nonsense-command"], "unknown command"),
        (["set"], "set with no name"),
        (["set", "no-such-theme"], "set an unknown theme"),
        (["apply", "no-such-theme"], "apply an unknown theme"),
        (["edit", "no-such-theme"], "edit an unknown theme"),
        (["new"], "new with no name"),
        (["set", "nord", "--bogus"], "an unknown option"),
        (["set", "nord", "extra", "args"], "too many arguments"),
        (["set", "nord", "--tty", "definitely-not-a-tty"], "a tty that does not exist"),
    ):
        r = run(args, home, shell)
        check(r is not None, f"{tag}: {label}: hung")
        if r:
            check(r.returncode != 0, f"{tag}: {label} exits non-zero (got {r.returncode})")
            check(r.stderr.strip() != "", f"{tag}: {label} explains itself on stderr")
            check("Traceback" not in r.stderr, f"{tag}: {label} does not trace back")

    # a name made entirely of characters that are not allowed
    r = run(["new", "///"], home, shell)
    check(r is not None and r.returncode != 0, f"{tag}: new with an unusable name is refused")
    # metacharacters must be stripped, not executed
    canary = os.path.join(home, "canary")
    r = run(["new", f"x; touch {canary}; y"], home, shell)
    check(not os.path.exists(canary), f"{tag}: metacharacters in a name are not executed")
    shutil.rmtree(home, ignore_errors=True)

    # --- interactive commands with no terminal --------------------------------
    home = sandbox()
    for args, label in (([], "picker"), (["edit"], "editor")):
        r = run(args, home, shell, timeout=12)
        check(r is not None, f"{tag}: {label} with no terminal: hung")
        if r:
            check(r.returncode != 0, f"{tag}: {label} with no terminal exits non-zero")
            check("terminal" in r.stderr.lower(), f"{tag}: {label} says it needs a terminal")
    shutil.rmtree(home, ignore_errors=True)

    # --- reset works from nothing --------------------------------------------
    bare = tempfile.mkdtemp(prefix="tinct-qc-")
    r = run(["reset"], bare, shell)
    clean(r, f"{tag}: reset with an empty config directory")
    r = run(["where"], bare, shell)
    clean(r, f"{tag}: where with an empty config directory")
    shutil.rmtree(bare, ignore_errors=True)

    # config directory that does not exist at all
    gone = os.path.join(tempfile.mkdtemp(prefix="tinct-qc-"), "nope", "deeper")
    r = run(["set", "nord"], gone, shell)
    clean(r, f"{tag}: set creates its config directory on demand")
    check(os.path.exists(os.path.join(gone, "default")) or
          os.path.exists(os.path.join(gone, "sessions")),
          f"{tag}: set actually wrote something under a fresh config directory")
    shutil.rmtree(os.path.dirname(gone), ignore_errors=True)

# --- writes from several processes at once -----------------------------------
home = sandbox()
picks = ["nord", "dracula", "monokai", "gruvbox-dark", "ember", "iceberg",
         "zenburn", "kanagawa"]
with ThreadPoolExecutor(max_workers=8) as pool:
    list(pool.map(lambda t: run(["set", t, "--default"], home), picks * 3))
final = open(os.path.join(home, "default")).read().strip()
check(final in picks, f"concurrent writes leave one valid theme name (got {final!r})")
check("\n" not in final and len(final) < 40, "concurrent writes do not interleave")
r = run(["which"], home)
clean(r, "reading state after concurrent writes")
shutil.rmtree(home, ignore_errors=True)

# --- a lot of themes ----------------------------------------------------------
home = sandbox()
big = os.path.join(home, "themes")
for i in range(300):
    open(os.path.join(big, f"bulk{i:03d}.theme"), "w").write(
        f"LABEL=Bulk {i}\nDESC=generated theme number {i}\n"
        f"BG=#10{i % 10}0{i % 10}0\nFG=#EEEEEE\nCURSOR=#FFFFFF\n"
        f"SEL_BG=#333333\nSEL_FG=#FFFFFF\n")
t = time.time()
r = run(["__frame", "200", "28", "116"], home)
elapsed = time.time() - t
clean(r, "rendering with 358 themes")
if r:
    lines = r.stdout.replace("\033[H\033[2J", "").split("\n")
    check(len(lines) <= 28, f"358 themes still fit the window ({len(lines)} lines)")
    check("▸" in r.stdout, "the cursor is still on screen with 358 themes")
budget = 6 * float(os.environ.get("TINCT_TEST_SLOW", "1"))
check(elapsed < budget, f"rendering with 358 themes stays responsive ({elapsed:.1f}s)")
shutil.rmtree(home, ignore_errors=True)

# --- a theme with absurd metadata --------------------------------------------
home = sandbox()
open(os.path.join(home, "themes", "shouty.theme"), "w").write(
    "LABEL=" + "L" * 400 + "\nDESC=" + "D" * 400 + "\nBG=#101010\nFG=#F0F0F0\n"
    "CURSOR=#FFFFFF\nSEL_BG=#333333\nSEL_FG=#FFFFFF\n")
r = run(["__frame", "0", "24", "80"], home, extra={"TINCT_HOME": home})
clean(r, "rendering a theme with a 400-character label")
if r:
    for line in r.stdout.replace("\033[H\033[2J", "").split("\n"):
        import re as _re
        plain = _re.sub(r"\033\[[0-9;?]*[A-Za-z]", "", line)
        check(len(plain) <= 80, f"absurd metadata still fits the width ({len(plain)})")
        break
shutil.rmtree(home, ignore_errors=True)

print(f"robust: {checks - len(fails)}/{checks} checks passed")
for f in fails:
    print("  FAIL", f)
sys.exit(1 if fails else 0)
