# tintcoat

[![tests](https://github.com/solvyxtech/tintcoat/actions/workflows/tests.yml/badge.svg)](https://github.com/solvyxtech/tintcoat/actions/workflows/tests.yml)

Terminal color themes that apply to the session you are already in.

No profile to edit, no new window, nothing to restart. And every terminal keeps
its own theme, so the window you use for production does not have to look like
the one you use for scratch work.

```
tintcoat                     pick a theme, previewing as you move
tintcoat set nord            just this terminal
tintcoat set nord --all      every terminal you have open
tintcoat sessions            what each terminal is showing
```

## Why this exists

I work in one terminal window with a long-running program sitting in it. Every
theme switcher I tried wanted me to edit a profile and open a new window, which
meant killing the thing I was in the middle of just to change the background.
That is a silly trade to have to make.

Once that worked, the obvious next thing was that my terminals should not all
look the same. A window sitting on a production host should be visibly, boringly
different from the one where I am trying things out — not because it is pretty,
but because it is the cheapest possible guard against running the right command
in the wrong window.

One thing worth being clear about: this themes the **terminal emulator**, not
your shell and not any particular program. The colors belong to the window, so
whatever is running in it — a shell, an editor, a REPL, a full-screen TUI — is
retinted along with everything else. That is the whole trick.

## Why it works

Most theme switchers rewrite a config file and tell you to open a new window.
tintcoat writes OSC escape sequences straight to the terminal device instead:

| Sequence | What it sets |
| --- | --- |
| `OSC 10` / `11` / `12` | foreground, background, cursor |
| `OSC 17` / `19` | selection background and foreground |
| `OSC 4;N` | palette entry N |
| `OSC 104`, `110`–`119` | reset the above |

Every mainstream terminal has supported these for years. Because a terminal
device is just a file you can write to, tintcoat can also paint a window it is
not running in — which is what makes `--all` and `--tty` possible at all.

## A theme per terminal

Each terminal remembers its own theme, keyed by its tty. A terminal with no
preference of its own uses the default, so new windows stay predictable while
any individual one can be pinned to something else.

```
tintcoat set nord                 pin this terminal
tintcoat set nord --default       ...and make it the default for new terminals
tintcoat set nord --all           paint every open terminal
tintcoat set nord --tty ttys004   paint one specific terminal
tintcoat clear                    unpin, go back to the default
tintcoat clear --all              unpin everything
```

`tintcoat sessions` shows every terminal you have open and lets you change any
of them without leaving the list:

```
  tintcoat  4 open · ⏎ to change one

▸ ttys004   nord                 zsh         pinned  ·you    Nord
  ttys006   gruvbox-dark         vim         default         Arctic north-bluish
  ttys009   ember                ssh         pinned          ████████████████
  ttys012   gruvbox-dark         node        default         ████████████████

  ↑↓ move · ⏎ change theme · c unpin · r refresh · q back
```

Pick a terminal, press enter, and the theme picker opens aimed at it — moving
the cursor repaints **that** window while this one keeps drawing the list. Set
it, and you are back at the terminal list with the new theme showing. `c` unpins
the highlighted terminal and puts it back on the default.

Because the target window is not this one, the preview here is drawn from the
theme's own color values rather than from your palette — otherwise it would be
showing you your colors while claiming to show theirs.

Piped or redirected, `tintcoat sessions` prints a plain listing instead, so it
stays usable in scripts. `tintcoat which` answers the narrower question of what
this terminal is on and why. Records for terminals that no longer exist are
cleaned up automatically, since tty names get recycled when windows close.

## Rules: themes that apply themselves

`~/.config/tintcoat/rules` maps directories and ssh hosts to themes. First match
wins, so put the specific ones first.

```
dir  ~/work/prod   = high-contrast-dark
dir  ~/work        = one-dark
host prod-*        = ember
host *.internal    = midnight-ink
```

With the shell integration loaded, `cd ~/work/prod` retints the window, and
`ssh prod-db1` makes the session visibly different for as long as it lasts —
then puts the window back. Directory rules match a path prefix; host rules are
globs against the ssh destination, with any `user@` stripped first.

A terminal you have pinned by hand is left alone. Explicit beats automatic.

### What the host rules do and do not match

Host rules match **what you typed**, not what ssh resolves it to. If your
`~/.ssh/config` maps `Host prod` onto some address, `host prod-*` matches the
alias `prod` — a machine you reach as `web1` will not match however it is
configured. Write rules against the names you actually type.

Two other honest limits:

- **The far end can paint over you.** If the remote shell sets its own colors,
  they win for as long as you are there. The window is put back when the
  session ends, but "prod is red" is a convention, not an enforcement.
- **Resuming a suspended command does not restore its theme.** Suspending one
  with ctrl-Z is handled — the window goes back to this terminal's own colors
  the moment you are looking at your own prompt again. Bringing it back with
  `fg` does not re-apply it, because the two shells suspend different things
  (zsh stops the whole wrapper, bash stops only the child and runs the rest of
  the wrapper immediately), and neither offers a hook the wrapper can catch on
  the way back in. Re-run `tintcoat set <theme>` if it matters.

## Themes

100 of them: 75 dark, 25 light. **[See them all →](https://solvyxtech.github.io/tintcoat/)**
— every theme previewed in its own colors, generated from the theme files by
`tools/gallery.py` so it cannot drift from what ships.

**Dark**

```
abyssal               arctic-dim            aurora-north
ayu-dark              ayu-mirage            basalt-glow
blackcurrant          blueprint             cacao
campfire              carbon-weave          catppuccin-frappe
catppuccin-mocha      cobalt                concrete
copper-patina         dark-cream            deep-jade
desert-night          dracula               ember
espresso              everforest-dark       film-noir
forest-floor          github-dark           glacier-deep
gruvbox-dark          gunmetal              high-contrast-dark
iceberg               iron-oxide            kanagawa
koi-pond              lacquer               leather-bound
mesa                  midnight-ink          midnight-orchid
mono-amber            mono-green            mono-slate
monokai               monsoon               moss-stone
nebula                neon-alley            night-owl
nord                  obsidian              oceanic-next
oil-slick             one-dark              palenight
peat-bog              petrichor             plum-dusk
redwood               rose-pine             sea-glass
selenized-dark        slate-harbor          solarized-dark
spruce                srcery                stained-glass
sumi-ink              synthwave             tidepool
tokyo-night           tokyo-night-storm     ultraviolet
warm-charcoal         wine-cellar           zenburn
```

**Light**

```
ayu-light             catppuccin-latte      cherry-blossom
clay                  everforest-light      github-light
gray-card             gruvbox-light         high-contrast-light
highlighter           lavender-fog          ledger
linen                 matcha                mint-paper
newsprint             paper-cream           papercolor
porcelain             rose-pine-dawn        sandstone
sea-fog               sepia-print           sky-wash
solarized-light
```

Adding one is a file: copy any theme in `themes/`, change the values, run
`python3 tools/gallery.py` so the gallery picks it up.

Every one is checked automatically, because a theme can parse perfectly and
still be unusable. `tests/themes.py` verifies body text meets WCAG AA against
the background, that dim text and each palette color separate from it, that a
selection is readable and the cursor findable, and that no two themes are
near-copies. Adding a theme that fails any of those breaks the build.

## Install

Requires **zsh**, or **bash 4 or newer**. macOS still ships bash 3.2, which
cannot run this — but it also ships zsh, so on a Mac there is nothing to do.

```
git clone https://github.com/solvyxtech/tintcoat.git ~/.local/share/tintcoat
~/.local/share/tintcoat/install.sh
```

The installer symlinks `bin/tintcoat` into `~/.local/bin` and creates
`~/.config/tintcoat`. Nothing else is touched.

## Shell integration

Optional, and where the automatic parts live. Source it from `~/.zshrc` or
`~/.bashrc`:

```sh
. ~/.local/share/tintcoat/shell/init.sh

tintcoat_enable_auto              # this terminal's theme, reapplied on cd
tintcoat_wrap_ssh                 # ssh themed by host rules
tintcoat_wrap psql solarized-dark # theme one command while it runs
```

`tintcoat_wrap` applies a theme on entry and hands the terminal back on exit,
including when you interrupt it. Piped output and nested calls pass through
untouched, so scripts are unaffected. `TINTCOAT_DISABLE=1` turns all of it off.

The hooks do their lookups in pure shell and fork nothing. Launching tintcoat
costs about 20ms, which is fine once but not on every prompt, so the program is
only started when the answer actually changes — `cd` inside one project is free.

## The picker

```
  tintcoat  100 themes · here: night-owl

      mono-slate           │   Nord
      monokai              │   Arctic north-bluish, official palette
      monsoon              │
      moss-stone           █   bg #2E3440  fg #D8DEE9
      nebula               █   contrast 9.2:1
      neon-alley           │
      newsprint            │   ~/src/tintcoat main ±
  ●   night-owl            │   $ git commit -m 'retune the palette'
    ▸ nord                 │    + accent = "#8EC07C"
      obsidian             │   bold primary  dim secondary
      oceanic-next         │   ✓ 24 passed  ! 2 warn  ✗ 1 failed

  ↑↓ move · ⏎ set here · d default · A all · / find · e edit · q
```

| Key | Does |
| --- | --- |
| `↑` `↓`, `PgUp` `PgDn`, `Home` `End` | move, previewing live |
| `/` | narrow the list as you type |
| `⏎` | set for this terminal |
| `d` | also make it the default for new terminals |
| `A` | apply to every open terminal |
| `e` | open the editor on the highlighted theme |
| `q` | back out, restoring what you had |

The layout follows the window: the preview moves below the list on narrow
terminals and drops detail rather than overflowing on small ones. The list is a
viewport, so the cursor is always on screen no matter how many themes you have.

## The editor

`tintcoat edit <name>` walks the twenty-one color slots.

| Key | Effect |
| --- | --- |
| `↑` `↓` | move between slots |
| `←` `→` | lightness |
| `,` `.` | hue |
| `-` `=` | saturation |
| `x` | type a hex value |
| `w` | save |
| `a` | save under a new name |
| `r` | discard changes and reload |

It shows the foreground/background contrast ratio and flags anything below
WCAG AA. Nudges are kept in floating-point HSL rather than re-derived from the
rounded hex each time, so holding a key down does not drift the hue.

Editing a bundled theme writes your copy to `~/.config/tintcoat/themes/`, which
shadows the bundled one. The checkout is never modified, so `git pull` stays
clean.

## Theme format

Plain `KEY=value` text. Every color is optional — leave the palette out and the
terminal keeps the one it was configured with.

```
# nord
LABEL=Nord
DESC=Arctic north-bluish, official palette

BG=#2E3440
FG=#D8DEE9
CURSOR=#D8DEE9
SEL_BG=#434C5E
SEL_FG=#D8DEE9

ANSI0=#3B4252
ANSI1=#BF616A
...
ANSI15=#ECEFF4
```

`tintcoat new <name>` copies the current theme as a starting point.

## Files

| Path | What |
| --- | --- |
| `~/.config/tintcoat/default` | theme for new terminals |
| `~/.config/tintcoat/sessions/` | one file per pinned terminal |
| `~/.config/tintcoat/rules` | directory and host rules |
| `~/.config/tintcoat/themes/` | your themes; shadow bundled ones by name |
| `~/.config/tintcoat/config` | `scrolloff`, and anything else general |

## Layout

```
bin/tintcoat        launcher: picks zsh or bash 4+, then runs lib/main.sh
lib/core.sh      themes, color math, escape sequences, sessions, rules
lib/ui.sh        picker, viewport, preview
lib/edit.sh      color editor
shell/init.sh    PATH, hooks, wrappers -- fork-free lookups
themes/          bundled themes
```

The implementation is one dialect that both shells understand. zsh gets
`ksh_arrays` so array indexing matches bash, associative subscripts are always
quoted because zsh reads unquoted ones as globs, glob matching goes through one
helper because zsh will not expand a pattern held in a variable without being
asked, and anything needing floating point goes to POSIX awk.

A keystroke in the picker costs about 4ms: it does no work per frame that it can
cache, builds escape sequences from real control bytes rather than `printf '%b'`,
and pads columns by string slicing instead of a subshell per row.

## Tests

```
tests/run.sh
```

Every push and pull request runs the whole suite on **Ubuntu and macOS**, plus
shellcheck and the theme checks. That matters more than usual here: the claim
is that one codebase runs on two shells, and proving it on one laptop proves
very little.

Around 6,000 checks. The unit tests run under both shells; the rest drive the
real binary through a pty or a subprocess.

```
tests/unit.sh         pure functions: viewport, color math, parsing, rules
tests/themes.py       every bundled theme is legible and distinct
tests/robust.py       bad input, bad paths, bad permissions, races
tests/render.py       every frame fits its window and never overflows
tests/interactive.py  keys do what they claim, via a real pty
tests/wrap.py         hooks, wrappers, and per-terminal resolution
```

`robust.py` is the one that has found the most. It runs everything from a config
directory whose path contains spaces, quotes and parentheses; from a checkout
reached through a symlink; against themes that are empty, binary, CRLF-encoded,
full of invalid colors, or actually directories; with an unwritable config; with
eight processes writing state at once; and with 358 themes installed. Nothing is
allowed to hang, crash, print a shell error, or leave state half-written.

State files are written to a temporary name and renamed into place, so a reader
arriving mid-write sees the old value or the new one, never an empty file.

## Previously called tinct

Up to v1.1.0 this was `tinct`, which turned out to be a name that half the
internet was already using. v2.0.0 renames the command, the environment
variables (`TINCT_*` is now `TINTCOAT_*`) and the config directory. If you have
a `~/.config/tinct` from the old version, it is moved to `~/.config/tintcoat`
the first time you run the new one, so pins, rules and your own themes survive.
Update the path in your shell rc and re-run `install.sh` to replace the old
symlink.

## License

MIT.
