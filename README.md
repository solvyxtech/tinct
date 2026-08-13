# tinct

Terminal color themes that apply to the session you are already in.

No profile to edit, no new window, nothing to restart. Pick a theme and the
terminal in front of you changes color, including the program running in it.

```
tinct                  pick a theme, previewing as you move
tinct set nord         apply it and remember it
tinct edit nord        adjust the colors by hand
tinct reset            hand the terminal back its own colors
```

## Why this exists

I work in one terminal window with a long-running program sitting in it. Every
theme switcher I tried wanted me to edit a profile and open a new window, which
meant killing the thing I was in the middle of just to change the background.
That is a silly trade to have to make.

So this changes the window in place. It also grew a `watch` setting, because the
window I actually wanted to retint was usually a *different tab* from the one I
was typing in — and a program that is already running cannot be asked to
re-read a config file.

One thing worth being clear about: this themes the **terminal emulator**, not
your shell and not any particular program. The colors belong to the window, so
whatever is running in it — a shell, an editor, a REPL, a full-screen TUI — is
retinted along with everything else. That is the whole trick.

## Why it works

Most theme switchers rewrite a config file and tell you to open a new window.
tinct writes OSC escape sequences straight to the terminal device instead:

| Sequence | What it sets |
| --- | --- |
| `OSC 10` / `11` / `12` | foreground, background, cursor |
| `OSC 17` / `19` | selection background and foreground |
| `OSC 4;N` | palette entry N |
| `OSC 104`, `110`–`119` | reset the above |

Every mainstream terminal has supported these for years. Because the colors
are a property of the terminal rather than of any program, a long-running
process in that window is retinted along with everything else.

It can also repaint a window it is not being run from. Give it a program name
to watch and it resolves that process's tty and writes there directly:

```
# ~/.config/tinct/config
watch = psql, vim
```

That is what makes it useful with something already running in another tab.

## Install

Requires **zsh**, or **bash 4 or newer**. macOS still ships bash 3.2, which
cannot run this — but it also ships zsh, so on a Mac there is nothing to do.

```
git clone https://github.com/solvyxtech/tinct.git ~/.local/share/tinct
~/.local/share/tinct/install.sh
```

The installer symlinks `bin/tinct` into `~/.local/bin` and creates
`~/.config/tinct`. Nothing else is touched. To do it by hand, put `bin/tinct`
on your `PATH`.

## Shell integration

Optional, and the reason the project exists. Source it from `~/.zshrc` or
`~/.bashrc`:

```sh
. ~/.local/share/tinct/shell/init.sh

tinct_wrap psql                   # theme while it runs, restore when it exits
tinct_wrap ssh solarized-dark     # a specific theme for a specific tool
```

A wrapped command applies a theme on entry and hands the terminal back on
exit — including when you interrupt it. Piped output and nested calls pass
through untouched, so scripts are unaffected.

## The picker

```
  tinct  36 themes · saved: gruvbox-dark

  ● gruvbox-dark        │   Nord
    high-contrast-dark  │   Arctic north-bluish, official palette
    lavender-fog        █
  ▸ nord                █   ████████████████
    obsidian            █   ████████████████
    one-dark            █
    rose-pine           │   bg #2E3440  fg #D8DEE9
    tokyo-night         │   contrast 9.7:1

  ↑↓ move · ⏎ set · / find · e edit · q cancel
```

`/` narrows the list as you type, `e` opens the editor on the highlighted
theme, `q` leaves everything as it was. The layout follows the window: the
preview moves below the list on narrow terminals and drops detail rather than
overflowing on small ones.

## The editor

`tinct edit <name>` walks the twenty-one color slots.

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

Editing a bundled theme writes your copy to `~/.config/tinct/themes/`, which
shadows the bundled one. The checkout is never modified, so `git pull` stays
clean.

## Theme format

Plain `KEY=value` text. Every color is optional — leave the palette out and
the terminal keeps the one it was configured with.

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

`tinct new <name>` copies the current theme as a starting point.

## Configuration

`~/.config/tinct/config`, same `KEY=value` format:

| Key | Default | Meaning |
| --- | --- | --- |
| `watch` | *(none)* | comma-separated program names whose terminals also get repainted |
| `scrolloff` | `2` | rows of context kept above and below the picker cursor |

## Layout

```
bin/tinct        launcher: picks zsh or bash 4+, then runs lib/main.sh
lib/core.sh      theme files, color math, escape sequences, tty targeting
lib/ui.sh        picker, viewport, preview
lib/edit.sh      color editor
shell/init.sh    PATH plus tinct_wrap
themes/          bundled themes
tests/           see below
```

The implementation is one dialect that both shells understand. zsh gets
`ksh_arrays` so array indexing matches bash, associative subscripts are always
quoted because zsh reads unquoted ones as globs, and anything needing floating
point goes to POSIX awk rather than to a shell built-in.

## Tests

```
tests/run.sh
```

Runs the unit tests under both shells, then three suites that drive the real
binary: layout assertions across nine terminal sizes, an interactive suite that
drives the picker and editor through a pty, and one that exercises the shell
integration. Roughly 700 checks.

```
tests/unit.sh         pure functions: viewport, color math, parsing
tests/render.py       every frame fits its window and never overflows
tests/interactive.py  keys do what they claim, via a real pty
tests/wrap.py         tinct_wrap applies, restores, and stays out of the way
```

## License

MIT.
