# tintcoat core: theme files, color math, and talking to the terminal.
#
# Written for the zsh/bash intersection -- see bin/tintcoat for how the
# interpreter gets picked. Two rules keep it portable:
#   * arrays are 0-indexed (zsh gets ksh_arrays set for us)
#   * associative subscripts are always quoted, or zsh reads them as globs

# --- paths -------------------------------------------------------------------
# This program used to be called tinct. If the old config directory is still
# there and the new one is not, move it across once, so an upgrade keeps its
# pins, rules and themes. Skipped entirely when the caller has pointed
# TINTCOAT_HOME somewhere itself -- the test suite does exactly that, and it
# has no business touching a real config directory.
if [ -z "${TINTCOAT_HOME:-}" ]; then
  TINTCOAT_HOME=${XDG_CONFIG_HOME:-$HOME/.config}/tintcoat
  tintcoat_legacy_home=${XDG_CONFIG_HOME:-$HOME/.config}/tinct
  if [ ! -e "$TINTCOAT_HOME" ] && [ -d "$tintcoat_legacy_home" ] &&
     [ ! -L "$tintcoat_legacy_home" ]; then
    mv "$tintcoat_legacy_home" "$TINTCOAT_HOME" 2>/dev/null || :
  fi
  unset tintcoat_legacy_home
fi
: "${TINTCOAT_THEME_DIR:=$TINTCOAT_HOME/themes}"
: "${TINTCOAT_ACTIVE_FILE:=$TINTCOAT_HOME/active}"
: "${TINTCOAT_CONFIG_FILE:=$TINTCOAT_HOME/config}"
: "${TINTCOAT_SESSION_DIR:=$TINTCOAT_HOME/sessions}"
: "${TINTCOAT_RULES_FILE:=$TINTCOAT_HOME/rules}"

# Themes ship with the checkout and are also read from the user's config dir.
# The user's copy wins, so editing a bundled theme never touches the repo.
: "${TINTCOAT_BUNDLED_DIR:=$TINTCOAT_ROOT/themes}"

# --- config ------------------------------------------------------------------
# config is KEY=value, '#' comments. Recognized keys:
#   watch=psql,vim     also repaint the terminals of these running programs
#   scrolloff=2        rows of context to keep above/below the picker cursor
TINTCOAT_WATCH=""
TINTCOAT_SCROLLOFF=2

tintcoat_read_config() {
  local line key val
  [ -r "$TINTCOAT_CONFIG_FILE" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%$'\r'}
    case $line in ''|'#'*) continue ;; esac
    case $line in *=*) ;; *) continue ;; esac
    tintcoat_trim_into "${line%%=*}"; key=$TRIMMED
    tintcoat_trim_into "${line#*=}"; val=$TRIMMED
    case $key in
      watch)     TINTCOAT_WATCH=$val ;;
      scrolloff) TINTCOAT_SCROLLOFF=$val ;;
    esac
  done < "$TINTCOAT_CONFIG_FILE"
}

# --- small string helpers ----------------------------------------------------
TINTCOAT_TAB=$(printf '\t')

# Strip ASCII space and tab from both ends. The result lands in TRIMMED rather
# than on stdout: theme parsing calls this a few thousand times over a full
# listing, and a fork per call is the difference between instant and sluggish.
tintcoat_trim_into() {
  local s=$1
  while :; do
    case $s in
      ' '*|"$TINTCOAT_TAB"*) s=${s#?} ;;
      *) break ;;
    esac
  done
  while :; do
    case $s in
      *' '|*"$TINTCOAT_TAB") s=${s%?} ;;
      *) break ;;
    esac
  done
  TRIMMED=$s
}

tintcoat_trim() { tintcoat_trim_into "$1"; printf '%s' "$TRIMMED"; }

tintcoat_upper() { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }

# Is this a color we are willing to hand to a terminal? Anything else in a
# theme file gets dropped rather than forwarded -- a hand-edited theme should
# lose one color, not send garbage down the wire inside an escape sequence.
tintcoat_is_hex() {
  case $1 in
    '#'[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]) return 0 ;;
    '#'[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]) return 0 ;;
  esac
  return 1
}

# Does a value match a glob pattern held in a variable? bash treats an
# unquoted $var in a case pattern as a pattern; zsh does not without
# GLOB_SUBST, and ${~var} is the local way of asking for it.
if [ -n "${ZSH_VERSION:-}" ]; then
  tintcoat_glob_match() { case $1 in ${~2}) return 0 ;; esac; return 1; }
else
  tintcoat_glob_match() { case $1 in $2) return 0 ;; esac; return 1; }
fi

# Names become filenames, so keep them to a safe set.
tintcoat_slug() {
  printf '%s' "$1" | tr ' ' '-' | tr -cd 'A-Za-z0-9_-'
}

# --- color math ------------------------------------------------------------
# Hex parsing happens in the shell (cheap). Anything needing floats goes to
# awk -- and deliberately to POSIX awk, so no gawk-only strtonum()/tolower().

tintcoat_hex2rgb() {          # "#RRGGBB" -> "R G B"
  local h=${1#\#}
  # Length alone is not enough: a hand-edited theme can hold six characters
  # that are not hex, and feeding those to printf produces shell errors rather
  # than a color. Anything unusable becomes mid gray.
  case $h in
    *[!0-9A-Fa-f]*) h=808080 ;;
  esac
  case ${#h} in
    3) h="${h:0:1}${h:0:1}${h:1:1}${h:1:1}${h:2:1}${h:2:1}" ;;
    6) ;;
    *) h=808080 ;;
  esac
  printf '%d %d %d' "0x${h:0:2}" "0x${h:2:2}" "0x${h:4:2}"
}

# Same conversion into R/G/B globals, without a subshell. Base-16 arithmetic
# expansion is understood by both shells, which matters because the preview
# converts every palette entry on every frame.
tintcoat_hex2rgb_into() {     # "#RRGGBB" -> R, G, B
  local h=${1#\#}
  case $h in
    *[!0-9A-Fa-f]*) h=808080 ;;
  esac
  case ${#h} in
    3) h="${h:0:1}${h:0:1}${h:1:1}${h:1:1}${h:2:1}${h:2:1}" ;;
    6) ;;
    *) h=808080 ;;
  esac
  R=$(( 16#${h:0:2} )); G=$(( 16#${h:2:2} )); B=$(( 16#${h:4:2} ))
}

tintcoat_hex2hsl() {          # "#RRGGBB" -> "H S L" as floats
  local rgb; rgb=$(tintcoat_hex2rgb "$1")
  awk -v rgb="$rgb" 'BEGIN{
    split(rgb, c, " ")
    r = c[1]/255; g = c[2]/255; b = c[3]/255
    mx = (r>g) ? ((r>b)?r:b) : ((g>b)?g:b)
    mn = (r<g) ? ((r<b)?r:b) : ((g<b)?g:b)
    d = mx - mn
    l = (mx + mn) / 2
    if (d == 0) { h = 0; s = 0 }
    else {
      a = 2*l - 1; if (a < 0) a = -a
      s = d / (1 - a)
      if (mx == r)      h = 60 * ((g - b)/d)
      else if (mx == g) h = 60 * ((b - r)/d + 2)
      else              h = 60 * ((r - g)/d + 4)
      while (h < 0)    h += 360
      while (h >= 360) h -= 360
    }
    printf "%.6f %.6f %.6f", h, s*100, l*100
  }'
}

tintcoat_hsl2hex() {          # H S L -> "#RRGGBB"
  awk -v h="$1" -v s="$2" -v l="$3" 'BEGIN{
    while (h < 0)    h += 360
    while (h >= 360) h -= 360
    s /= 100; l /= 100
    a = 2*l - 1; if (a < 0) a = -a
    c = (1 - a) * s
    m = h / 60
    while (m >= 2) m -= 2
    m -= 1; if (m < 0) m = -m
    x = c * (1 - m)
    o = l - c/2
    seg = int(h / 60)
    if      (seg == 0) { r=c; g=x; b=0 }
    else if (seg == 1) { r=x; g=c; b=0 }
    else if (seg == 2) { r=0; g=c; b=x }
    else if (seg == 3) { r=0; g=x; b=c }
    else if (seg == 4) { r=x; g=0; b=c }
    else               { r=c; g=0; b=x }
    ri = int((r+o)*255 + 0.5); gi = int((g+o)*255 + 0.5); bi = int((b+o)*255 + 0.5)
    if (ri<0) ri=0; if (ri>255) ri=255
    if (gi<0) gi=0; if (gi>255) gi=255
    if (bi<0) bi=0; if (bi>255) bi=255
    printf "#%02X%02X%02X", ri, gi, bi
  }'
}

# Ratio plus verdict in one awk call, memoized by color pair. The picker asks
# for this on every cursor move, and two forks per keystroke is most of the
# reason the old one felt sluggish.
typeset -A TINTCOAT_CONTRAST_MEMO 2>/dev/null || true

tintcoat_contrast_into() {    # <fg> <bg> -> CONTRAST, CONTRAST_LOW
  local key="$1/$2" cached
  cached=${TINTCOAT_CONTRAST_MEMO["$key"]}
  if [ -n "$cached" ]; then
    CONTRAST=${cached% *}; CONTRAST_LOW=${cached#* }
    return 0
  fi
  local a b out
  a=$(tintcoat_hex2rgb "$1"); b=$(tintcoat_hex2rgb "$2")
  out=$(awk -v A="$a" -v B="$b" 'BEGIN{
    split(A, x, " "); split(B, y, " ")
    la = lum(x[1],x[2],x[3]); lb = lum(y[1],y[2],y[3])
    r = (la > lb) ? ratio(la, lb) : ratio(lb, la)
    printf "%.1f %s", r, (r < 4.5) ? "low" : "ok"
  }
  function chan(v) { v /= 255; return (v <= 0.03928) ? v/12.92 : exp(2.4*log((v+0.055)/1.055)) }
  function lum(r,g,b) { return 0.2126*chan(r) + 0.7152*chan(g) + 0.0722*chan(b) }
  function ratio(hi,lo) { return (hi + 0.05) / (lo + 0.05) }')
  TINTCOAT_CONTRAST_MEMO["$key"]=$out
  CONTRAST=${out% *}; CONTRAST_LOW=${out#* }
}

tintcoat_contrast() {         # two hexes -> WCAG contrast ratio, one decimal
  local a; a=$(tintcoat_hex2rgb "$1")
  local b; b=$(tintcoat_hex2rgb "$2")
  awk -v A="$a" -v B="$b" 'BEGIN{
    split(A, x, " "); split(B, y, " ")
    printf "%.1f", (lum(x[1],x[2],x[3]) > lum(y[1],y[2],y[3])) \
      ? ratio(lum(x[1],x[2],x[3]), lum(y[1],y[2],y[3])) \
      : ratio(lum(y[1],y[2],y[3]), lum(x[1],x[2],x[3]))
  }
  function chan(v) { v /= 255; return (v <= 0.03928) ? v/12.92 : exp(2.4*log((v+0.055)/1.055)) }
  function lum(r,g,b) { return 0.2126*chan(r) + 0.7152*chan(g) + 0.0722*chan(b) }
  function ratio(hi,lo) { return (hi + 0.05) / (lo + 0.05) }'
}

# --- theme files -------------------------------------------------------------
# Format is KEY=value with '#' comments. Every color is optional: omit the
# ANSI block and the terminal keeps whatever palette it was configured with.
#
# Loading fills these globals:
TH_NAME=""; TH_LABEL=""; TH_DESC=""
TH_BG=""; TH_FG=""; TH_CURSOR=""; TH_SEL_BG=""; TH_SEL_FG=""
TH_ANSI=()

tintcoat_theme_file() {       # name -> readable path, user dir winning
  local n=$1
  # -f, not -e or -r: a directory called "something.theme" is readable, and
  # trying to read one is an error rather than an empty theme.
  if [ -f "$TINTCOAT_THEME_DIR/$n.theme" ] && [ -r "$TINTCOAT_THEME_DIR/$n.theme" ]; then
    printf '%s' "$TINTCOAT_THEME_DIR/$n.theme"
  elif [ -f "$TINTCOAT_BUNDLED_DIR/$n.theme" ] && [ -r "$TINTCOAT_BUNDLED_DIR/$n.theme" ]; then
    printf '%s' "$TINTCOAT_BUNDLED_DIR/$n.theme"
  else
    return 1
  fi
}

tintcoat_load() {             # name-or-path -> TH_* globals
  local file=$1 line key val i
  case $file in
    */*) ;;
    *) file=$(tintcoat_theme_file "$file") || return 1 ;;
  esac
  [ -f "$file" ] && [ -r "$file" ] || return 1

  TH_NAME=${file##*/}; TH_NAME=${TH_NAME%.theme}
  TH_LABEL=$TH_NAME; TH_DESC=""
  TH_BG=""; TH_FG=""; TH_CURSOR=""; TH_SEL_BG=""; TH_SEL_FG=""
  TH_ANSI=()
  i=0; while [ $i -lt 16 ]; do TH_ANSI[$i]=""; i=$((i+1)); done

  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%$'\r'}
    tintcoat_trim_into "$line"; line=$TRIMMED
    case $line in ''|'#'*) continue ;; esac
    case $line in *=*) ;; *) continue ;; esac
    tintcoat_trim_into "${line%%=*}"; key=$TRIMMED
    tintcoat_trim_into "${line#*=}"; val=$TRIMMED
    case $key in
      LABEL)  TH_LABEL=$val; continue ;;
      DESC)   TH_DESC=$val; continue ;;
    esac
    # Everything below here is a color, so anything unusable is discarded.
    tintcoat_is_hex "$val" || continue
    case $key in
      BG)     TH_BG=$val ;;
      FG)     TH_FG=$val ;;
      CURSOR) TH_CURSOR=$val ;;
      SEL_BG) TH_SEL_BG=$val ;;
      SEL_FG) TH_SEL_FG=$val ;;
      ANSI*)  i=${key#ANSI}
              case $i in
                ''|*[!0-9]*) ;;
                *) [ "$i" -lt 16 ] && TH_ANSI[$i]=$val ;;
              esac ;;
    esac
  done < "$file"
  return 0
}

tintcoat_list() {             # every theme name, user dir shadowing bundled
  local d f b
  for d in "$TINTCOAT_THEME_DIR" "$TINTCOAT_BUNDLED_DIR"; do
    [ -d "$d" ] || continue
    for f in "$d"/*.theme; do
      [ -f "$f" ] || continue
      b=${f##*/}
      printf '%s\n' "${b%.theme}"
    done
  done | sort -u
}

# --- escape sequences --------------------------------------------------------
# Colors are set with OSC escapes, so they retint the terminal that is already
# open -- no profile to edit, no new window, nothing to restart.
#   OSC 10/11/12   fg / bg / cursor
#   OSC 17/19      selection bg / fg
#   OSC 4;N        palette entry N
#   OSC 104/11x    reset the above
# Builds into SEQ rather than onto stdout. The picker rebuilds this on every
# cursor move, and $(...) costs a fork each time.
# Real ESC and BEL bytes, resolved once. Building the sequence out of literal
# "\033" text would mean a printf '%b' -- and therefore a fork -- every time it
# is written out, which in the picker is every keystroke.
TINTCOAT_ESC=$(printf '\033')
TINTCOAT_BEL=$(printf '\a')

tintcoat_seq_into() {
  local e=$TINTCOAT_ESC b=$TINTCOAT_BEL out i c
  out="${e}]104${b}"                    # clear whatever the last theme left
  [ -n "$TH_FG" ]     && out="${out}${e}]10;${TH_FG}${b}"
  [ -n "$TH_BG" ]     && out="${out}${e}]11;${TH_BG}${b}"
  [ -n "$TH_CURSOR" ] && out="${out}${e}]12;${TH_CURSOR}${b}"
  [ -n "$TH_SEL_BG" ] && out="${out}${e}]17;${TH_SEL_BG}${b}"
  [ -n "$TH_SEL_FG" ] && out="${out}${e}]19;${TH_SEL_FG}${b}"
  i=0
  while [ $i -lt 16 ]; do
    c=${TH_ANSI[$i]}
    [ -n "$c" ] && out="${out}${e}]4;${i};${c}${b}"
    i=$((i+1))
  done
  SEQ=$out
}

tintcoat_seq() { tintcoat_seq_into; printf '%s' "$SEQ"; }

tintcoat_reset_seq() {
  local e=$TINTCOAT_ESC b=$TINTCOAT_BEL
  printf '%s' "${e}]110${b}${e}]111${b}${e}]112${b}${e}]117${b}${e}]119${b}${e}]104${b}"
}

# --- which terminals get painted ---------------------------------------------
# A theme change usually has to reach a program that is ALREADY RUNNING, often
# in a different tab. /dev/tty is no help there, so resolve the tty *device* of
# each watched process and write to it directly -- we own the device, so the
# kernel allows it.
# Every terminal of mine that is currently alive, as device paths. A terminal
# counts as mine if it has a running process and I can write to the device.
#
# The result is cached for the life of the process: a picker session rebuilds
# this on every keypress otherwise, and scanning the process table is by far
# the most expensive thing in a redraw.
TINTCOAT_TTYS_CACHE=""
TINTCOAT_TTYS_CACHED=0

tintcoat_ttys_uncached() {
  local line tty d seen=""
  while IFS= read -r line; do
    # ps pads its columns, so the name arrives with trailing spaces attached.
    tintcoat_trim_into "$line"; tty=$TRIMMED
    [ -n "$tty" ] || continue
    [ "$tty" = "??" ] && continue
    d="/dev/$tty"
    [ -w "$d" ] || continue
    case ":$seen:" in *":$d:"*) continue ;; esac
    seen="$seen:$d"
    printf '%s\n' "$d"
  done <<EOF
$(ps -Ao tty= 2>/dev/null | sort -u)
EOF
}

tintcoat_ttys() {
  if [ -n "${TINTCOAT_TTY:-}" ]; then
    printf '%s\n' "$TINTCOAT_TTY"
    return 0
  fi
  if [ "$TINTCOAT_TTYS_CACHED" = 1 ]; then
    printf '%s' "$TINTCOAT_TTYS_CACHE"
    return 0
  fi
  TINTCOAT_TTYS_CACHE=$(tintcoat_ttys_uncached)
  [ -n "$TINTCOAT_TTYS_CACHE" ] && TINTCOAT_TTYS_CACHE="$TINTCOAT_TTYS_CACHE
"
  TINTCOAT_TTYS_CACHED=1
  printf '%s' "$TINTCOAT_TTYS_CACHE"
}

# The terminal this process is attached to, as a bare name (ttys009).
tintcoat_this_tty() {
  local t
  t=$(tty 2>/dev/null) || return 1
  case $t in
    /dev/*) printf '%s' "${t#/dev/}" ;;
    *) return 1 ;;
  esac
}

# Write a sequence to specific terminals. Appending rather than truncating is
# identical for a tty device, but it keeps TINTCOAT_TTY=<a regular file> usable as
# a capture log for the test suite.
tintcoat_emit_to() {          # <sequence> <device>...
  local s=$1 d any=0
  shift
  for d in "$@"; do
    [ -n "$d" ] || continue
    printf '%s' "$s" >> "$d" 2>/dev/null && any=1
  done
  [ "$any" = 1 ] || return 1
  return 0
}

# Default target: just this terminal. Per-terminal themes mean painting every
# terminal in sight is the wrong default -- that is what `--all` is for.
tintcoat_emit() {
  local s=$1 t
  if [ -n "${TINTCOAT_TTY:-}" ]; then
    tintcoat_emit_to "$s" "$TINTCOAT_TTY" && return 0
    printf '%b' "$s"
    return 0
  fi
  t=$(tty 2>/dev/null)
  case $t in
    /dev/*) tintcoat_emit_to "$s" "$t" && return 0 ;;
  esac
  printf '%s' "$s"
  return 0
}

tintcoat_apply_live() { tintcoat_seq_into; tintcoat_emit "$SEQ"; }
tintcoat_reset_live() { tintcoat_emit "$(tintcoat_reset_seq)"; }

# Paint a named list of devices with the loaded theme.
tintcoat_apply_to() {         # <device>...
  tintcoat_seq_into
  tintcoat_emit_to "$SEQ" "$@"
}

# --- per-terminal themes -----------------------------------------------------
# Each terminal remembers its own theme, keyed by tty name. A terminal with no
# record of its own falls back to the default, so new windows are predictable
# while any individual one can be pinned to something else.
#
#   sessions/ttys009   -> "nord"
#   default            -> "gruvbox-dark"

tintcoat_default() {
  local n
  for f in "$TINTCOAT_HOME/default" "$TINTCOAT_ACTIVE_FILE"; do
    [ -r "$f" ] || continue
    IFS= read -r n < "$f" || n=""
    tintcoat_trim_into "$n"; n=$TRIMMED
    if [ -n "$n" ] && tintcoat_theme_file "$n" >/dev/null 2>&1; then
      printf '%s' "$n"; return 0
    fi
  done
  n=$(tintcoat_list | head -1)
  [ -n "$n" ] || return 1
  printf '%s' "$n"
}

# Writing state with `>` truncates first, so a reader arriving mid-write sees
# an empty file and falls back to something else. Write beside the target and
# rename over it instead: rename is atomic, so a reader sees either the old
# value or the new one and never nothing.
tintcoat_write_atomic() {     # <path> <line>
  local dest=$1 tmp
  mkdir -p "${dest%/*}" 2>/dev/null || return 1
  tmp=$dest.$$
  printf '%s\n' "$2" > "$tmp" 2>/dev/null || return 1
  mv -f "$tmp" "$dest" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
  return 0
}

tintcoat_set_default() {
  tintcoat_theme_file "$1" >/dev/null 2>&1 || return 1
  tintcoat_write_atomic "$TINTCOAT_HOME/default" "$1" || return 1
  # Keep the older file in step so a half-upgraded setup cannot disagree
  # with itself about which theme is the default.
  [ -e "$TINTCOAT_ACTIVE_FILE" ] && tintcoat_write_atomic "$TINTCOAT_ACTIVE_FILE" "$1"
  return 0
}

# Linux calls its terminals pts/0, and a slash in a name would make the session
# record a nested directory rather than a file. Flatten it into a single
# filename component; macOS ttys009 is unaffected.
tintcoat_tty_key_into() { TTYKEY=${1//\//-}; }

tintcoat_session_get() {      # <ttyname> -> theme, or nothing
  tintcoat_tty_key_into "$1"
  local f=$TINTCOAT_SESSION_DIR/$TTYKEY n
  [ -r "$f" ] || return 1
  IFS= read -r n < "$f" || return 1
  tintcoat_trim_into "$n"; n=$TRIMMED
  [ -n "$n" ] && tintcoat_theme_file "$n" >/dev/null 2>&1 || return 1
  printf '%s' "$n"
}

tintcoat_session_set() {      # <ttyname> <theme>
  tintcoat_theme_file "$2" >/dev/null 2>&1 || return 1
  tintcoat_tty_key_into "$1"
  tintcoat_write_atomic "$TINTCOAT_SESSION_DIR/$TTYKEY" "$2"
}

tintcoat_session_clear() {
  tintcoat_tty_key_into "$1"
  rm -f "$TINTCOAT_SESSION_DIR/$TTYKEY" 2>/dev/null
  return 0
}

# tty names get recycled when a window closes and another opens, so records
# for terminals that no longer exist are dropped on every run.
tintcoat_session_gc() {
  local f name d live keys=""
  [ -d "$TINTCOAT_SESSION_DIR" ] || return 0
  # Build the set of live terminals using the same flattened keys the records
  # are stored under, or Linux names would never match and nothing would be
  # collected.
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    tintcoat_tty_key_into "${d#/dev/}"
    keys="$keys:$TTYKEY"
  done <<EOF
$(tintcoat_ttys)
EOF
  for f in "$TINTCOAT_SESSION_DIR"/*; do
    [ -f "$f" ] || continue
    name=${f##*/}
    case ":$keys:" in
      *":$name:"*) ;;
      *) rm -f "$f" ;;
    esac
  done
}

# What should this terminal be showing, and why? Sets RESOLVED and RESOLVED_BY
# rather than printing, so the reason survives -- a $(...) caller would run
# this in a subshell and throw the second half of the answer away.
tintcoat_resolve() {          # <ttyname>
  local t=$1 n
  if [ -n "$t" ] && n=$(tintcoat_session_get "$t"); then
    RESOLVED=$n; RESOLVED_BY="pinned to this terminal"
    return 0
  fi
  RESOLVED=$(tintcoat_default) || return 1
  RESOLVED_BY="default for new terminals"
  return 0
}

# --- rules -------------------------------------------------------------------
# Automatic themes, matched by the shell integration:
#
#   dir  ~/work/prod   = high-contrast-dark
#   host prod-*        = ember
#   host *.internal    = midnight-ink
#
# First match wins, so put the specific ones first. Directory rules match a
# path prefix; host rules are glob patterns against the ssh destination.
tintcoat_rule_match() {       # <kind> <value> -> theme, or nothing
  local kind=$1 val=$2 line rkind rpat rtheme rest
  [ -r "$TINTCOAT_RULES_FILE" ] || return 1

  while IFS= read -r line || [ -n "$line" ]; do
    tintcoat_trim_into "$line"; line=$TRIMMED
    case $line in ''|'#'*) continue ;; esac
    case $line in *=*) ;; *) continue ;; esac

    rtheme=${line#*=}; tintcoat_trim_into "$rtheme"; rtheme=$TRIMMED
    rest=${line%%=*};  tintcoat_trim_into "$rest";   rest=$TRIMMED
    rkind=${rest%%[ 	]*}
    rpat=${rest#"$rkind"}; tintcoat_trim_into "$rpat"; rpat=$TRIMMED
    [ -n "$rpat" ] || continue
    [ "$rkind" = "$kind" ] || continue

    case $rkind in
      dir)
        # ~ is expanded here rather than by the shell, since the file is data.
        case $rpat in "~"*) rpat="$HOME${rpat#\~}" ;; esac
        rpat=${rpat%/}
        case $val in
          "$rpat"|"$rpat"/*) printf '%s' "$rtheme"; return 0 ;;
        esac ;;
      host)
        tintcoat_glob_match "$val" "$rpat" && { printf '%s' "$rtheme"; return 0; } ;;
    esac
  done < "$TINTCOAT_RULES_FILE"
  return 1
}
