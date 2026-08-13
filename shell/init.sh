# tinct shell integration -- source this from ~/.zshrc or ~/.bashrc:
#
#     . /path/to/tinct/shell/init.sh
#
# It puts tinct on PATH and gives you tinct_wrap, which is the interesting
# part: a wrapped command runs with a theme applied and hands the terminal
# back when it exits.
#
#     tinct_wrap psql                # theme while it runs, restore after
#     tinct_wrap psql solarized-dark # a specific theme for a specific tool
#
# Deliberately small, because it is sourced by every interactive shell. The
# program itself is only loaded when you actually run it.

# Where am I? The two shells disagree about how a sourced file learns its own
# path, and neither answer parses cleanly in the other, so ask separately.
if [ -n "${ZSH_VERSION:-}" ]; then
  TINCT_SHELL_DIR=${${(%):-%x}:A:h}
else
  TINCT_SHELL_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
fi
TINCT_BIN_DIR=${TINCT_SHELL_DIR%/*}/bin

case ":$PATH:" in
  *":$TINCT_BIN_DIR:"*) ;;
  *) PATH="$TINCT_BIN_DIR:$PATH" ;;
esac
export PATH

# Run a command with a theme applied, restoring the terminal afterwards.
# Nested calls and non-terminal output pass straight through untouched.
tinct_run() {              # tinct_run <theme-or-empty> <command> [args...]
  local theme=$1
  shift
  if [ ! -t 1 ] || [ -n "${TINCT_WRAPPED:-}" ]; then
    command "$@"
    return $?
  fi

  local rc=0 name=${1##*/}

  # The reset is registered before the command starts, so an interrupt or a
  # crash still hands the terminal back instead of stranding it mid-theme.
  trap 'tinct reset >/dev/null 2>&1; trap - INT TERM' INT TERM

  TINCT_WRAPPED=1 tinct apply ${theme:+"$theme"} >/dev/null 2>&1
  printf '\033]0;%s\a' "$name"

  TINCT_WRAPPED=1 command "$@" || rc=$?

  trap - INT TERM
  tinct reset >/dev/null 2>&1
  printf '\033]0;%s\a' "${PWD##*/}"
  return $rc
}

# Replace a command with a themed version of itself.
tinct_wrap() {             # tinct_wrap <command> [theme]
  local cmd=$1 theme=${2:-}
  case $cmd in
    ''|*[!A-Za-z0-9_-]*)
      printf 'tinct_wrap: not a usable command name: %s\n' "$cmd" >&2
      return 1 ;;
  esac
  eval "${cmd}() { tinct_run '${theme}' '${cmd}' \"\$@\"; }"
}
