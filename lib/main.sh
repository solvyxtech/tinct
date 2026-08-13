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
  active=$(tinct_active) || { printf 'tinct: no themes found\n' >&2; return 1; }
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

cmd_set() {
  local n=$1
  [ -n "$n" ] || { printf 'usage: tinct set <name>\n' >&2; return 1; }
  tinct_load "$n" || { printf 'tinct: no such theme: %s\n' "$n" >&2; return 1; }
  tinct_set_active "$n"
  tinct_apply_live
  printf 'theme set to %s\n' "$n"
}

cmd_apply() {
  local n=${1:-$(tinct_active)}
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
  [ -n "$base" ] || base=$(tinct_active)
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
  printf 'active   %s\n' "$(tinct_active 2>/dev/null)"
  printf 'watching %s\n' "${TINCT_WATCH:-(nothing, just this terminal)}"
  printf 'targets\n'
  tinct_ttys | sed 's/^/         /'
}

cmd_help() {
  cat <<'EOF'
tinct -- terminal colour themes, applied to the session you are already in

  tinct                  pick a theme, previewing as you move
  tinct set <name>       apply it and remember it
  tinct apply [name]     apply without changing the saved default
  tinct edit [name]      adjust colours by hand
  tinct new <name>       copy a theme to start a new one
  tinct ls               list themes
  tinct reset            hand the terminal back its own colours
  tinct where            show paths and what is being repainted

In the picker: arrows move, / narrows the list, e opens the editor,
enter accepts, q leaves everything as it was.

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
  ACTIVE_NAME=$(tinct_active)
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
  apply)          shift; cmd_apply "$@" ;;
  edit|e)         shift; tinct_edit "$@" ;;
  new|n)          shift; cmd_new "$@" ;;
  ls|list|l)      cmd_ls ;;
  reset)          tinct_reset_live; printf 'terminal colours reset\n' ;;
  where)          cmd_where ;;
  help|-h|--help) cmd_help ;;
  __frame)        shift; cmd_frame "$@" ;;
  *)              printf 'tinct: unknown command: %s\n' "$1" >&2; cmd_help >&2; exit 1 ;;
esac
