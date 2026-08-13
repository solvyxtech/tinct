# tinct shell integration -- source this from ~/.zshrc or ~/.bashrc:
#
#     . /path/to/tinct/shell/init.sh
#
# What it gives you:
#   * this terminal gets its own theme back when you open it
#   * directories can carry a theme, applied as you cd into them
#   * ssh can carry a theme per host, so prod does not look like your laptop
#   * tinct_wrap, to theme a single command while it runs
#
# A note on why there is real code here rather than calls to tinct: launching
# the program costs about 20ms, which is fine once but not on every prompt.
# The lookups below are pure shell and fork nothing, so tinct is only launched
# when the answer actually changes.

if [ -n "${ZSH_VERSION:-}" ]; then
  TINCT_SHELL_DIR=${${(%):-%x}:A:h}
else
  TINCT_SHELL_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
fi
TINCT_REPO=${TINCT_SHELL_DIR%/*}
TINCT_BIN_DIR=$TINCT_REPO/bin
: "${TINCT_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/tinct}"

case ":$PATH:" in
  *":$TINCT_BIN_DIR:"*) ;;
  *) PATH="$TINCT_BIN_DIR:$PATH" ;;
esac
export PATH

# Which terminal is this? Asked once, because `tty` is a fork.
TINCT_TTY_NAME=$(tty 2>/dev/null) || TINCT_TTY_NAME=''
TINCT_TTY_NAME=${TINCT_TTY_NAME#/dev/}
case $TINCT_TTY_NAME in /*|'') TINCT_TTY_NAME='' ;; esac

if [ -n "${ZSH_VERSION:-}" ]; then
  tinct__match() { case $1 in ${~2}) return 0 ;; esac; return 1; }
else
  tinct__match() { case $1 in $2) return 0 ;; esac; return 1; }
fi

tinct__trim() {            # -> TINCT_T
  local s=$1
  while :; do case $s in ' '*|"	"*) s=${s#?} ;; *) break ;; esac; done
  while :; do case $s in *' '|*"	") s=${s%?} ;; *) break ;; esac; done
  TINCT_T=$s
}

tinct__theme_file() {      # <name> -> TINCT_F
  TINCT_F=''
  if [ -f "$TINCT_HOME/themes/$1.theme" ]; then TINCT_F=$TINCT_HOME/themes/$1.theme
  elif [ -f "$TINCT_REPO/themes/$1.theme" ]; then TINCT_F=$TINCT_REPO/themes/$1.theme
  fi
  [ -n "$TINCT_F" ]
}

# Same rule as lib/core.sh: never forward a value we cannot vouch for.
tinct__is_hex() {
  case $1 in
    '#'[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]) return 0 ;;
    '#'[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]) return 0 ;;
  esac
  return 1
}

# Write a theme straight to this terminal. Same OSC sequences lib/core.sh
# builds; kept here so the prompt path never launches a process.
tinct_paint() {            # <theme name>
  tinct__theme_file "$1" || return 1
  local line key val out esc bel
  esc=$(printf '\033'); bel=$(printf '\a')
  out="${esc}]104${bel}"
  while IFS= read -r line || [ -n "$line" ]; do
    case $line in ''|'#'*) continue ;; esac
    case $line in *=*) ;; *) continue ;; esac
    tinct__trim "${line%%=*}"; key=$TINCT_T
    tinct__trim "${line#*=}"; val=$TINCT_T
    tinct__is_hex "$val" || continue
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
  done < "$TINCT_F"
  printf '%s' "$out"
}

# First rule whose pattern matches, or nothing.
tinct_rule_lookup() {      # <dir|host> <value> -> TINCT_RULE
  TINCT_RULE=''
  [ -r "$TINCT_HOME/rules" ] || return 1
  local line kind pat theme rest
  while IFS= read -r line || [ -n "$line" ]; do
    tinct__trim "$line"; line=$TINCT_T
    case $line in ''|'#'*) continue ;; esac
    case $line in *=*) ;; *) continue ;; esac
    tinct__trim "${line#*=}";  theme=$TINCT_T
    tinct__trim "${line%%=*}"; rest=$TINCT_T
    kind=${rest%%[ 	]*}
    tinct__trim "${rest#"$kind"}"; pat=$TINCT_T
    [ -n "$pat" ] && [ "$kind" = "$1" ] || continue
    case $kind in
      dir)
        case $pat in "~"*) pat="$HOME${pat#\~}" ;; esac
        pat=${pat%/}
        case $2 in
          "$pat"|"$pat"/*) TINCT_RULE=$theme; return 0 ;;
        esac ;;
      host)
        tinct__match "$2" "$pat" && { TINCT_RULE=$theme; return 0; } ;;
    esac
  done < "$TINCT_HOME/rules"
  return 1
}

# What should this terminal be showing? Pin beats rule beats default.
tinct_here_theme() {       # -> TINCT_WANT
  TINCT_WANT=''
  local n
  if [ -n "$TINCT_TTY_NAME" ] && [ -r "$TINCT_HOME/sessions/$TINCT_TTY_NAME" ]; then
    IFS= read -r n < "$TINCT_HOME/sessions/$TINCT_TTY_NAME"
    tinct__trim "$n"; TINCT_WANT=$TINCT_T
    [ -n "$TINCT_WANT" ] && return 0
  fi
  if tinct_rule_lookup dir "$PWD"; then
    TINCT_WANT=$TINCT_RULE
    return 0
  fi
  for n in "$TINCT_HOME/default" "$TINCT_HOME/active"; do
    [ -r "$n" ] || continue
    IFS= read -r TINCT_WANT < "$n"
    tinct__trim "$TINCT_WANT"; TINCT_WANT=$TINCT_T
    [ -n "$TINCT_WANT" ] && return 0
  done
  return 1
}

# Repaint only when the answer changed, so cd inside one project is free.
TINCT_SHOWING=''
tinct_sync() {
  [ -n "${TINCT_DISABLE:-}" ] && return 0
  [ -t 1 ] || return 0
  tinct_here_theme || return 0
  [ "$TINCT_WANT" = "$TINCT_SHOWING" ] && return 0
  tinct_paint "$TINCT_WANT" || return 0
  TINCT_SHOWING=$TINCT_WANT
}

# --- wrapping a single command ----------------------------------------------
# Set while a wrapped command owns the window. It is deliberately not `local`:
# suspending the command drops you back to your prompt with this function still
# part-way through, and the prompt hook needs to see that the colors on screen
# are not the ones this terminal should be wearing.
TINCT_WRAP_ACTIVE=''

tinct_run() {              # <theme-or-empty> <command> [args...]
  local theme=$1
  shift
  if [ ! -t 1 ] || [ -n "${TINCT_WRAPPED:-}" ]; then
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
  # tinct_prompt_hook, and the note about resuming in the README.
  trap 'tinct_restore; trap - INT TERM' INT TERM

  TINCT_WRAP_ACTIVE=1
  if [ -n "$theme" ]; then
    tinct_paint "$theme"
    TINCT_SHOWING=$theme
  fi
  printf '\033]0;%s\a' "$name"

  TINCT_WRAPPED=1 command "$@" || rc=$?

  trap - INT TERM
  TINCT_WRAP_ACTIVE=''
  tinct_restore
  printf '\033]0;%s\a' "${PWD##*/}"
  return $rc
}

# Put the terminal back on whatever it should be showing.
tinct_restore() {
  TINCT_SHOWING=''
  tinct_sync
}

tinct_wrap() {             # <command> [theme]
  local cmd=$1 theme=${2:-}
  case $cmd in
    ''|*[!A-Za-z0-9_-]*)
      printf 'tinct_wrap: not a usable command name: %s\n' "$cmd" >&2
      return 1 ;;
  esac
  if [ -z "$theme" ]; then
    # No theme named: use whatever this terminal is on, so the wrapper only
    # sets the window title and restores state after.
    eval "${cmd}() { tinct_run \"\${TINCT_SHOWING}\" '${cmd}' \"\$@\"; }"
  else
    eval "${cmd}() { tinct_run '${theme}' '${cmd}' \"\$@\"; }"
  fi
}

# ssh, themed by destination. `host prod-* = ember` in the rules file means
# every production box looks different from your laptop, which is the point.
tinct_wrap_ssh() {
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
    if [ -n "$dest" ] && tinct_rule_lookup host "$dest"; then
      tinct_run "$TINCT_RULE" ssh "$@"
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
tinct_prompt_hook() {
  [ -n "$TINCT_WRAP_ACTIVE" ] || return 0
  TINCT_WRAP_ACTIVE=''
  tinct_restore
}

# --- hooks -------------------------------------------------------------------
tinct_enable_auto() {
  if [ -n "${ZSH_VERSION:-}" ]; then
    if autoload -Uz add-zsh-hook 2>/dev/null; then
      add-zsh-hook chpwd  tinct_sync
      add-zsh-hook precmd tinct_prompt_hook
    fi
  else
    case ";${PROMPT_COMMAND:-};" in
      *";tinct_sync;tinct_prompt_hook;"*) ;;
      *) PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND;}tinct_sync;tinct_prompt_hook" ;;
    esac
  fi
  tinct_sync
}
