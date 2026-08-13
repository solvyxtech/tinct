# tinct -- command dispatch. Run through bin/tinct, which picks the interpreter.

# zsh defaults differ from bash in two ways that matter here. Line them up
# once, and the rest of the codebase is a single dialect.
if [ -n "${ZSH_VERSION:-}" ]; then
  setopt ksh_arrays 2>/dev/null      # 0-indexed arrays
  setopt no_nomatch 2>/dev/null      # an unmatched glob stays literal
fi

: "${TINCT_ROOT:=$(cd -- "$(dirname "$0")/.." && pwd -P)}"

. "$TINCT_ROOT/lib/core.sh"
. "$TINCT_ROOT/lib/ui.sh"
. "$TINCT_ROOT/lib/edit.sh"

tinct_read_config

# --- non-interactive commands ------------------------------------------------
cmd_ls() {
  local active n
  active=$(tinct_default) || { printf 'tinct: no themes found\n' >&2; return 1; }
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    tinct_load "$n" || continue
    if [ "$n" = "$active" ]; then
      printf '\033[38;5;2m*\033[0m %-20s \033[2m%s\033[0m\n' "$n" "$TH_DESC"
    else
      printf '  %-20s \033[2m%s\033[0m\n' "$n" "$TH_DESC"
    fi
  done <<EOF
$(tinct_list)
EOF
}

# The foreground program in a terminal, for the sessions table.
tinct_tty_program() {      # <ttyname>
  local line st comm best=""
  while IFS= read -r line; do
    st=${line%% *}
    comm=${line#* }
    tinct_trim_into "$comm"; comm=$TRIMMED
    case $st in *+*) best=${comm##*/} ;; esac
  done <<EOF
$(ps -t "$1" -o stat=,comm= 2>/dev/null)
EOF
  printf '%s' "$best"
}

cmd_set() {
  local name='' all=0 mkdefault=0 tty='' a
  while [ $# -gt 0 ]; do
    a=$1; shift
    case $a in
      --all|-a)     all=1 ;;
      --default|-d) mkdefault=1 ;;
      --tty)        tty=${1#/dev/}; shift ;;
      --) ;;
      -*) printf 'tinct: unknown option %s\n' "$a" >&2; return 1 ;;
      *)  [ -z "$name" ] && name=$a || { printf 'tinct: unexpected argument %s\n' "$a" >&2; return 1; } ;;
    esac
  done

  [ -n "$name" ] || { printf 'usage: tinct set <name> [--all] [--default] [--tty NAME]\n' >&2; return 1; }
  tinct_load "$name" || { printf 'tinct: no such theme: %s\n' "$name" >&2; return 1; }

  [ "$mkdefault" = 1 ] && tinct_set_default "$name"

  if [ "$all" = 1 ]; then
    local devs d count=0
    devs=$(tinct_ttys)
    tinct_seq_into
    while IFS= read -r d; do
      [ -n "$d" ] || continue
      tinct_emit_to "$SEQ" "$d" || continue
      tinct_session_set "${d#/dev/}" "$name"
      count=$((count+1))
    done <<EOF
$devs
EOF
    printf '%s applied to %d terminals\n' "$name" "$count"
    [ "$mkdefault" = 1 ] && printf 'and set as the default for new ones\n'
    return 0
  fi

  if [ -n "$tty" ]; then
    tinct_seq_into
    tinct_emit_to "$SEQ" "/dev/$tty" || {
      printf 'tinct: cannot write to /dev/%s\n' "$tty" >&2; return 1; }
    tinct_session_set "$tty" "$name"
    printf '%s applied to %s\n' "$name" "$tty"
    return 0
  fi

  local here
  here=$(tinct_this_tty 2>/dev/null) || here=''
  tinct_apply_live
  if [ -n "$here" ]; then
    tinct_session_set "$here" "$name"
    if [ "$mkdefault" = 1 ]; then
      printf '%s set for this terminal, and as the default\n' "$name"
    else
      printf '%s set for this terminal\n' "$name"
    fi
  else
    [ "$mkdefault" = 1 ] || tinct_set_default "$name"
    printf '%s set as the default\n' "$name"
  fi
}

cmd_default() {
  local n=$1
  [ -n "$n" ] || { printf '%s\n' "$(tinct_default)"; return 0; }
  tinct_set_default "$n" || { printf 'tinct: no such theme: %s\n' "$n" >&2; return 1; }
  printf '%s is now the default for new terminals\n' "$n"
}

cmd_clear() {
  local here
  if [ "${1:-}" = "--all" ] || [ "${1:-}" = "-a" ]; then
    rm -rf "$TINCT_SESSION_DIR"
    printf 'cleared every terminal, all back to the default (%s)\n' "$(tinct_default)"
    return 0
  fi
  here=$(tinct_this_tty 2>/dev/null) || {
    printf 'tinct: not attached to a terminal\n' >&2; return 1; }
  tinct_session_clear "$here"
  tinct_resolve "$here"
  tinct_load "$RESOLVED" && tinct_apply_live
  printf 'this terminal is back on the default (%s)\n' "$RESOLVED"
}

cmd_sessions() {
  tinct_session_gc
  local here d name theme prog mark
  here=$(tinct_this_tty 2>/dev/null) || here=''
  printf '  %-10s %-20s %-10s %s\n' TERMINAL THEME RUNNING ''
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    name=${d#/dev/}
    tinct_resolve "$name"
    theme=$RESOLVED
    case $RESOLVED_BY in
      pinned*) mark='pinned' ;;
      *)       mark='default' ;;
    esac
    prog=$(tinct_tty_program "$name")
    if [ "$name" = "$here" ]; then
      printf '\033[1m▸ %-10s %-20s %-10s %s\033[0m\n' "$name" "$theme" "${prog:--}" "$mark"
    else
      printf '  %-10s %-20s %-10s \033[2m%s\033[0m\n' "$name" "$theme" "${prog:--}" "$mark"
    fi
  done <<EOF
$(tinct_ttys)
EOF
}

cmd_which() {
  local here
  here=$(tinct_this_tty 2>/dev/null) || here=''
  if [ -z "$here" ]; then
    printf '%s \033[2m(no terminal here, showing the default)\033[0m\n' "$(tinct_default)"
    return 0
  fi
  tinct_resolve "$here"
  printf '%s \033[2m(%s, on %s)\033[0m\n' "$RESOLVED" "$RESOLVED_BY" "$here"
}

cmd_rules() {
  if [ ! -r "$TINCT_RULES_FILE" ]; then
    printf 'no rules yet. create %s, for example:\n\n' "$TINCT_RULES_FILE"
    printf '  dir  ~/work/prod = high-contrast-dark\n'
    printf '  host prod-*      = ember\n\n'
    printf 'directory rules match a path prefix, host rules match the ssh destination.\n'
    return 0
  fi
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    tinct_trim_into "$line"; line=$TRIMMED
    case $line in ''|'#'*) continue ;; esac
    printf '  %s\n' "$line"
  done < "$TINCT_RULES_FILE"
  local m
  if m=$(tinct_rule_match dir "$PWD"); then
    printf '\n\033[2mhere (%s) matches:\033[0m %s\n' "$PWD" "$m"
  fi
}

cmd_apply() {
  local n=$1
  if [ -z "$n" ]; then
    tinct_resolve "$(tinct_this_tty 2>/dev/null)"
    n=$RESOLVED
  fi
  tinct_load "$n" || { printf 'tinct: no such theme: %s\n' "$n" >&2; return 1; }
  tinct_apply_live
}

cmd_new() {
  local n=$1 base=$2 src dest
  [ -n "$n" ] || { printf 'usage: tinct new <name> [from]\n' >&2; return 1; }
  n=$(tinct_slug "$n")
  [ -n "$n" ] || { printf 'tinct: that name has no usable characters\n' >&2; return 1; }
  dest=$TINCT_THEME_DIR/$n.theme
  [ -e "$dest" ] && { printf 'tinct: %s already exists\n' "$dest" >&2; return 1; }
  [ -n "$base" ] || base=$(tinct_default)
  src=$(tinct_theme_file "$base") || { printf 'tinct: no such theme: %s\n' "$base" >&2; return 1; }
  mkdir -p "$TINCT_THEME_DIR"
  sed -e "s/^LABEL=.*/LABEL=$n/" -e "s/^DESC=.*/DESC=based on $base/" "$src" > "$dest"
  printf 'created %s\n' "$dest"
  printf 'edit it with: tinct edit %s\n' "$n"
}

cmd_where() {
  printf 'root     %s\n' "$TINCT_ROOT"
  printf 'config   %s\n' "$TINCT_HOME"
  printf 'themes   %s\n' "$TINCT_THEME_DIR"
  printf 'bundled  %s\n' "$TINCT_BUNDLED_DIR"
  printf 'sessions %s\n' "$TINCT_SESSION_DIR"
  printf 'rules    %s\n' "$TINCT_RULES_FILE"
  printf 'default  %s\n' "$(tinct_default 2>/dev/null)"
  printf 'here     %s\n' "$(tinct_this_tty 2>/dev/null || printf '(not a terminal)')"
}

cmd_help() {
  cat <<'EOF'
tinct -- terminal color themes, applied to the session you are already in

  tinct                     pick a theme, previewing as you move
  tinct set <name>          set this terminal's theme
  tinct set <name> --all    every open terminal
  tinct set <name> --default   ...and for new terminals too
  tinct set <name> --tty X  one specific terminal
  tinct clear [--all]       drop the override, go back to the default

  tinct sessions            every terminal and what it is showing
  tinct which               what this terminal is on, and why
  tinct default [name]      show or set the default for new terminals

  tinct edit [name]         adjust colors by hand
  tinct new <name>          copy a theme to start a new one
  tinct ls                  list themes
  tinct rules               show the automatic theme rules
  tinct reset               hand the terminal back its own colors
  tinct where               show paths

Each terminal keeps its own theme. New terminals get the default, and any
one of them can be pinned to something else without disturbing the rest.

In the picker: arrows move, / narrows the list, e opens the editor,
enter sets it here, d also makes it the default, A applies to every
terminal, q leaves everything as it was.

Themes are plain KEY=value text; see the README for the keys.
EOF
}

# --- test hook ---------------------------------------------------------------
# Renders a single frame to stdout with no alt screen and no key handling, so
# the layout can be asserted on without driving a real terminal.
cmd_frame() {
  local idx=${1:-0} rows=${2:-24} cols=${3:-100} filter=${4:-}
  local i=0 n
  THEMES=()
  while IFS= read -r n; do THEMES[$i]=$n; i=$((i+1)); done <<EOF
$(tinct_list)
EOF
  ACTIVE_NAME=$(tinct_default)
  TINCT_HEADER_NOTE="here: ${ACTIVE_NAME}"
  FILTER=$filter; MODE=normal; TOP=0; IDX=$idx
  tinct_filter_apply
  [ "$IDX" -ge ${#SHOWN[@]} ] && IDX=$(( ${#SHOWN[@]} - 1 ))
  [ "$IDX" -lt 0 ] && IDX=0
  [ ${#SHOWN[@]} -gt 0 ] && tinct_load "${SHOWN[$IDX]}"
  TINCT_ROWS=$rows TINCT_COLS=$cols
  tinct_draw_picker
}

case ${1:-select} in
  ''|select)      tinct_select ;;
  set|s)          shift; cmd_set "$@" ;;
  default)        shift; cmd_default "$@" ;;
  clear)          shift; cmd_clear "$@" ;;
  sessions|ps)    cmd_sessions ;;
  which)          cmd_which ;;
  rules)          cmd_rules ;;
  apply)          shift; cmd_apply "$@" ;;
  edit|e)         shift; tinct_edit "$@" ;;
  new|n)          shift; cmd_new "$@" ;;
  ls|list|l)      cmd_ls ;;
  reset)          tinct_reset_live; printf 'terminal colors reset\n' ;;
  where)          cmd_where ;;
  help|-h|--help) cmd_help ;;
  __frame)        shift; cmd_frame "$@" ;;
  *)              printf 'tinct: unknown command: %s\n' "$1" >&2; cmd_help >&2; exit 1 ;;
esac
