# tintcoat shell integration -- source this from ~/.zshrc or ~/.bashrc:
#
#     . /path/to/tintcoat/shell/init.sh
#
# What it gives you:
#   * this terminal gets its own theme back when you open it
#   * directories can carry a theme, applied as you cd into them
#   * ssh can carry a theme per host, so prod does not look like your laptop
#   * tintcoat_wrap, to theme a single command while it runs
#
# A note on why there is real code here rather than calls to tintcoat: launching
# the program costs about 20ms, which is fine once but not on every prompt.
# The lookups below are pure shell and fork nothing, so tintcoat is only launched
# when the answer actually changes.

if [ -n "${ZSH_VERSION:-}" ]; then
  TINTCOAT_SHELL_DIR=${${(%):-%x}:A:h}
else
  TINTCOAT_SHELL_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
fi
TINTCOAT_REPO=${TINTCOAT_SHELL_DIR%/*}
TINTCOAT_BIN_DIR=$TINTCOAT_REPO/bin
: "${TINTCOAT_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/tintcoat}"

case ":$PATH:" in
  *":$TINTCOAT_BIN_DIR:"*) ;;
  *) PATH="$TINTCOAT_BIN_DIR:$PATH" ;;
esac
export PATH

# Which terminal is this? Asked once, because `tty` is a fork.
TINTCOAT_TTY_NAME=$(tty 2>/dev/null) || TINTCOAT_TTY_NAME=''
TINTCOAT_TTY_NAME=${TINTCOAT_TTY_NAME#/dev/}
case $TINTCOAT_TTY_NAME in /*|'') TINTCOAT_TTY_NAME='' ;; esac
# Session records are keyed by a flattened name, because Linux terminals are
# called pts/0 and a slash would nest a directory instead of naming a file.
TINTCOAT_TTY_KEY=${TINTCOAT_TTY_NAME//\//-}

if [ -n "${ZSH_VERSION:-}" ]; then
  tintcoat__match() { case $1 in ${~2}) return 0 ;; esac; return 1; }
else
  tintcoat__match() { case $1 in $2) return 0 ;; esac; return 1; }
fi

tintcoat__trim() {            # -> TINTCOAT_T
  local s=$1
  while :; do case $s in ' '*|"	"*) s=${s#?} ;; *) break ;; esac; done
  while :; do case $s in *' '|*"	") s=${s%?} ;; *) break ;; esac; done
  TINTCOAT_T=$s
}

tintcoat__theme_file() {      # <name> -> TINTCOAT_F
  TINTCOAT_F=''
  if [ -f "$TINTCOAT_HOME/themes/$1.theme" ]; then TINTCOAT_F=$TINTCOAT_HOME/themes/$1.theme
  elif [ -f "$TINTCOAT_REPO/themes/$1.theme" ]; then TINTCOAT_F=$TINTCOAT_REPO/themes/$1.theme
  fi
  [ -n "$TINTCOAT_F" ]
}

# Same rule as lib/core.sh: never forward a value we cannot vouch for.
tintcoat__is_hex() {
  case $1 in
    '#'[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]) return 0 ;;
    '#'[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]) return 0 ;;
  esac
  return 1
}

# Write a theme straight to this terminal. Same OSC sequences lib/core.sh
# builds; kept here so the prompt path never launches a process.
tintcoat_paint() {            # <theme name>
  tintcoat__theme_file "$1" || return 1
  local line key val out esc bel
  esc=$(printf '\033'); bel=$(printf '\a')
  out="${esc}]104${bel}"
  while IFS= read -r line || [ -n "$line" ]; do
    case $line in ''|'#'*) continue ;; esac
    case $line in *=*) ;; *) continue ;; esac
    tintcoat__trim "${line%%=*}"; key=$TINTCOAT_T
    tintcoat__trim "${line#*=}"; val=$TINTCOAT_T
    tintcoat__is_hex "$val" || continue
    case $key in
      FG)     out="${out}${esc}]10;${val}${bel}" ;;
      BG)     out="${out}${esc}]11;${val}${bel}" ;;
      CURSOR) out="${out}${esc}]12;${val}${bel}" ;;
      SEL_BG) out="${out}${esc}]17;${val}${bel}" ;;
      SEL_FG) out="${out}${esc}]19;${val}${bel}" ;;
      ANSI*)  case ${key#ANSI} in
                ''|*[!0-9]*) ;;
                *) out="${out}${esc}]4;${key#ANSI};${val}${bel}" ;;
              esac ;;
    esac
  done < "$TINTCOAT_F"
  printf '%s' "$out"
}

# First rule whose pattern matches, or nothing.
tintcoat_rule_lookup() {      # <dir|host> <value> -> TINTCOAT_RULE
  TINTCOAT_RULE=''
  [ -r "$TINTCOAT_HOME/rules" ] || return 1
  local line kind pat theme rest
  while IFS= read -r line || [ -n "$line" ]; do
    tintcoat__trim "$line"; line=$TINTCOAT_T
    case $line in ''|'#'*) continue ;; esac
    case $line in *=*) ;; *) continue ;; esac
    tintcoat__trim "${line#*=}";  theme=$TINTCOAT_T
    tintcoat__trim "${line%%=*}"; rest=$TINTCOAT_T
    kind=${rest%%[ 	]*}
    tintcoat__trim "${rest#"$kind"}"; pat=$TINTCOAT_T
    if [ -z "$pat" ] || [ "$kind" != "$1" ]; then continue; fi
    case $kind in
      dir)
        case $pat in "~"*) pat="$HOME${pat#\~}" ;; esac
        pat=${pat%/}
        case $2 in
          "$pat"|"$pat"/*) TINTCOAT_RULE=$theme; return 0 ;;
        esac ;;
      host)
        tintcoat__match "$2" "$pat" && { TINTCOAT_RULE=$theme; return 0; } ;;
    esac
  done < "$TINTCOAT_HOME/rules"
  return 1
}

# What should this terminal be showing? Pin beats rule beats default.
tintcoat_here_theme() {       # -> TINTCOAT_WANT
  TINTCOAT_WANT=''
  local n
  if [ -n "$TINTCOAT_TTY_KEY" ] && [ -r "$TINTCOAT_HOME/sessions/$TINTCOAT_TTY_KEY" ]; then
    IFS= read -r n < "$TINTCOAT_HOME/sessions/$TINTCOAT_TTY_KEY"
    tintcoat__trim "$n"; TINTCOAT_WANT=$TINTCOAT_T
    [ -n "$TINTCOAT_WANT" ] && return 0
  fi
  if tintcoat_rule_lookup dir "$PWD"; then
    TINTCOAT_WANT=$TINTCOAT_RULE
    return 0
  fi
  for n in "$TINTCOAT_HOME/default" "$TINTCOAT_HOME/active"; do
    [ -r "$n" ] || continue
    IFS= read -r TINTCOAT_WANT < "$n"
    tintcoat__trim "$TINTCOAT_WANT"; TINTCOAT_WANT=$TINTCOAT_T
    [ -n "$TINTCOAT_WANT" ] && return 0
  done
  return 1
}

# Repaint only when the answer changed, so cd inside one project is free.
TINTCOAT_SHOWING=''
tintcoat_sync() {
  [ -n "${TINTCOAT_DISABLE:-}" ] && return 0
  [ -t 1 ] || return 0
  tintcoat_here_theme || return 0
  [ "$TINTCOAT_WANT" = "$TINTCOAT_SHOWING" ] && return 0
  tintcoat_paint "$TINTCOAT_WANT" || return 0
  TINTCOAT_SHOWING=$TINTCOAT_WANT
}

# --- wrapping a single command ----------------------------------------------
# Set while a wrapped command owns the window. It is deliberately not `local`:
# suspending the command drops you back to your prompt with this function still
# part-way through, and the prompt hook needs to see that the colors on screen
# are not the ones this terminal should be wearing.
TINTCOAT_WRAP_ACTIVE=''

tintcoat_run() {              # <theme-or-empty> <command> [args...]
  local theme=$1
  shift
  if [ ! -t 1 ] || [ -n "${TINTCOAT_WRAPPED:-}" ]; then
    command "$@"
    return $?
  fi

  local rc=0 name=${1##*/}
  # Registered before the command starts, so an interrupt still hands the
  # terminal back rather than stranding it mid-theme.
  #
  # Suspension is handled by the prompt hook rather than by a CONT trap here.
  # The two shells suspend different things -- zsh stops the whole function,
  # bash stops only the child and runs the rest of this function immediately --
  # so there is no one signal this wrapper can catch on the way back in. See
  # tintcoat_prompt_hook, and the note about resuming in the README.
  trap 'tintcoat_restore; trap - INT TERM' INT TERM

  TINTCOAT_WRAP_ACTIVE=1
  if [ -n "$theme" ]; then
    tintcoat_paint "$theme"
    TINTCOAT_SHOWING=$theme
  fi
  printf '\033]0;%s\a' "$name"

  TINTCOAT_WRAPPED=1 command "$@" || rc=$?

  trap - INT TERM
  TINTCOAT_WRAP_ACTIVE=''
  tintcoat_restore
  printf '\033]0;%s\a' "${PWD##*/}"
  return $rc
}

# Put the terminal back on whatever it should be showing.
tintcoat_restore() {
  TINTCOAT_SHOWING=''
  tintcoat_sync
}

tintcoat_wrap() {             # <command> [theme]
  local cmd=$1 theme=${2:-}
  case $cmd in
    ''|*[!A-Za-z0-9_-]*)
      printf 'tintcoat_wrap: not a usable command name: %s\n' "$cmd" >&2
      return 1 ;;
  esac
  if [ -z "$theme" ]; then
    # No theme named: use whatever this terminal is on, so the wrapper only
    # sets the window title and restores state after.
    eval "${cmd}() { tintcoat_run \"\${TINTCOAT_SHOWING}\" '${cmd}' \"\$@\"; }"
  else
    eval "${cmd}() { tintcoat_run '${theme}' '${cmd}' \"\$@\"; }"
  fi
}

# ssh, themed by destination. `host prod-* = ember` in the rules file means
# every production box looks different from your laptop, which is the point.
tintcoat_wrap_ssh() {
  ssh() {
    local a dest='' skip=0
    for a in "$@"; do
      if [ "$skip" = 1 ]; then skip=0; continue; fi
      case $a in
        -[bcDEeFIiJLlmOoPpQRSWw]) skip=1 ;;
        -*) ;;
        *) dest=$a; break ;;
      esac
    done
    dest=${dest#*@}
    dest=${dest%%:*}
    if [ -n "$dest" ] && tintcoat_rule_lookup host "$dest"; then
      tintcoat_run "$TINTCOAT_RULE" ssh "$@"
    else
      command ssh "$@"
    fi
  }
}

# Runs just before each prompt. Almost always a single variable test, so it is
# cheap enough to sit in the prompt path.
#
# The case it exists for: you suspend a wrapped command with ctrl-Z. You are
# back at your own prompt, but the window is still wearing the colors of the
# thing you suspended. Nothing else can notice that, because the wrapper is
# suspended part-way through its own cleanup.
tintcoat_prompt_hook() {
  [ -n "$TINTCOAT_WRAP_ACTIVE" ] || return 0
  TINTCOAT_WRAP_ACTIVE=''
  tintcoat_restore
}

# --- hooks -------------------------------------------------------------------
tintcoat_enable_auto() {
  if [ -n "${ZSH_VERSION:-}" ]; then
    if autoload -Uz add-zsh-hook 2>/dev/null; then
      add-zsh-hook chpwd  tintcoat_sync
      add-zsh-hook precmd tintcoat_prompt_hook
    fi
  else
    case ";${PROMPT_COMMAND:-};" in
      *";tintcoat_sync;tintcoat_prompt_hook;"*) ;;
      *) PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND;}tintcoat_sync;tintcoat_prompt_hook" ;;
    esac
  fi
  tintcoat_sync
}
