#!/bin/sh
# Run everything. Each suite runs under zsh and, when one is available, under
# bash 4 or newer -- the two shells tinct claims to support.
#
#   tests/run.sh
#   TINCT_BASH=/opt/homebrew/bin/bash tests/run.sh

set -e
ROOT=$(cd -- "$(dirname "$0")/.." && pwd -P)
cd "$ROOT"

# Nothing in here should see the caller's configuration.
unset TINCT_HOME TINCT_THEME_DIR TINCT_ACTIVE_FILE TINCT_CONFIG_FILE
unset TINCT_TTY TINCT_ROWS TINCT_COLS TINCT_SHELL TINCT_WATCH

if [ -z "${TINCT_BASH:-}" ]; then
  for cand in /opt/homebrew/bin/bash /usr/local/bin/bash bash; do
    b=$(command -v "$cand" 2>/dev/null) || continue
    major=$("$b" -c 'echo ${BASH_VERSINFO[0]}' 2>/dev/null) || continue
    case $major in ''|*[!0-9]*) continue ;; esac
    [ "$major" -ge 4 ] && { TINCT_BASH=$b; break; }
  done
fi
export TINCT_BASH

fail=0
run() {
  printf '\n=== %s ===\n' "$1"
  shift
  "$@" || fail=1
}

run "unit (zsh)" zsh tests/unit.sh
if [ -n "${TINCT_BASH:-}" ]; then
  run "unit (bash $("$TINCT_BASH" -c 'echo $BASH_VERSION'))" "$TINCT_BASH" tests/unit.sh
else
  printf '\n=== unit (bash) ===\nskipped: no bash 4+ found, set TINCT_BASH to test it\n'
fi

run "themes"      python3 tests/themes.py
run "layout"      python3 tests/render.py
run "interactive" python3 tests/interactive.py
run "shell"       python3 tests/wrap.py

printf '\n'
if [ "$fail" -eq 0 ]; then
  printf 'all suites passed\n'
else
  printf 'FAILURES\n' >&2
fi
exit $fail
