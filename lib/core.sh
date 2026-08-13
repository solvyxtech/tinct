# tinct core: theme files, color math, and talking to the terminal.
#
# Written for the zsh/bash intersection -- see bin/tinct for how the
# interpreter gets picked. Two rules keep it portable:
#   * arrays are 0-indexed (zsh gets ksh_arrays set for us)
#   * associative subscripts are always quoted, or zsh reads them as globs

# --- paths -------------------------------------------------------------------
: "${TINCT_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/tinct}"
: "${TINCT_THEME_DIR:=$TINCT_HOME/themes}"
: "${TINCT_ACTIVE_FILE:=$TINCT_HOME/active}"
: "${TINCT_CONFIG_FILE:=$TINCT_HOME/config}"

# Themes ship with the checkout and are also read from the user's config dir.
# The user's copy wins, so editing a bundled theme never touches the repo.
: "${TINCT_BUNDLED_DIR:=$TINCT_ROOT/themes}"

# --- config ------------------------------------------------------------------
# config is KEY=value, '#' comments. Recognized keys:
#   watch=psql,vim     also repaint the terminals of these running programs
#   scrolloff=2        rows of context to keep above/below the picker cursor
TINCT_WATCH=""
TINCT_SCROLLOFF=2

tinct_read_config() {
  local line key val
  [ -r "$TINCT_CONFIG_FILE" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%$'\r'}
    case $line in ''|'#'*) continue ;; esac
    case $line in *=*) ;; *) continue ;; esac
    tinct_trim_into "${line%%=*}"; key=$TRIMMED
    tinct_trim_into "${line#*=}"; val=$TRIMMED
    case $key in
      watch)     TINCT_WATCH=$val ;;
      scrolloff) TINCT_SCROLLOFF=$val ;;
    esac
  done < "$TINCT_CONFIG_FILE"
}

# --- small string helpers ----------------------------------------------------
TINCT_TAB=$(printf '\t')

# Strip ASCII space and tab from both ends. The result lands in TRIMMED rather
# than on stdout: theme parsing calls this a few thousand times over a full
# listing, and a fork per call is the difference between instant and sluggish.
tinct_trim_into() {
  local s=$1
  while :; do
    case $s in
      ' '*|"$TINCT_TAB"*) s=${s#?} ;;
      *) break ;;
    esac
  done
  while :; do
    case $s in
      *' '|*"$TINCT_TAB") s=${s%?} ;;
      *) break ;;
    esac
  done
  TRIMMED=$s
}

tinct_trim() { tinct_trim_into "$1"; printf '%s' "$TRIMMED"; }

tinct_upper() { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }

# Names become filenames, so keep them to a safe set.
tinct_slug() {
  printf '%s' "$1" | tr ' ' '-' | tr -cd 'A-Za-z0-9_-'
}

# --- color math ------------------------------------------------------------
# Hex parsing happens in the shell (cheap). Anything needing floats goes to
# awk -- and deliberately to POSIX awk, so no gawk-only strtonum()/tolower().

tinct_hex2rgb() {          # "#RRGGBB" -> "R G B"
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

tinct_hex2hsl() {          # "#RRGGBB" -> "H S L" as floats
  local rgb; rgb=$(tinct_hex2rgb "$1")
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

tinct_hsl2hex() {          # H S L -> "#RRGGBB"
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

tinct_contrast() {         # two hexes -> WCAG contrast ratio, one decimal
  local a; a=$(tinct_hex2rgb "$1")
  local b; b=$(tinct_hex2rgb "$2")
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

tinct_theme_file() {       # name -> readable path, user dir winning
  local n=$1
  if [ -r "$TINCT_THEME_DIR/$n.theme" ]; then
    printf '%s' "$TINCT_THEME_DIR/$n.theme"
  elif [ -r "$TINCT_BUNDLED_DIR/$n.theme" ]; then
    printf '%s' "$TINCT_BUNDLED_DIR/$n.theme"
  else
    return 1
  fi
}

tinct_load() {             # name-or-path -> TH_* globals
  local file=$1 line key val i
  case $file in
    */*) ;;
    *) file=$(tinct_theme_file "$file") || return 1 ;;
  esac
  [ -r "$file" ] || return 1

  TH_NAME=${file##*/}; TH_NAME=${TH_NAME%.theme}
  TH_LABEL=$TH_NAME; TH_DESC=""
  TH_BG=""; TH_FG=""; TH_CURSOR=""; TH_SEL_BG=""; TH_SEL_FG=""
  TH_ANSI=()
  i=0; while [ $i -lt 16 ]; do TH_ANSI[$i]=""; i=$((i+1)); done

  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%$'\r'}
    tinct_trim_into "$line"; line=$TRIMMED
    case $line in ''|'#'*) continue ;; esac
    case $line in *=*) ;; *) continue ;; esac
    tinct_trim_into "${line%%=*}"; key=$TRIMMED
    tinct_trim_into "${line#*=}"; val=$TRIMMED
    case $key in
      LABEL)  TH_LABEL=$val ;;
      DESC)   TH_DESC=$val ;;
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

tinct_list() {             # every theme name, user dir shadowing bundled
  local d f b
  for d in "$TINCT_THEME_DIR" "$TINCT_BUNDLED_DIR"; do
    [ -d "$d" ] || continue
    for f in "$d"/*.theme; do
      [ -e "$f" ] || continue
      b=${f##*/}
      printf '%s\n' "${b%.theme}"
    done
  done | sort -u
}

tinct_active() {
  local n
  if [ -r "$TINCT_ACTIVE_FILE" ]; then
    IFS= read -r n < "$TINCT_ACTIVE_FILE" || n=""
    tinct_trim_into "$n"; n=$TRIMMED
    if [ -n "$n" ] && tinct_theme_file "$n" >/dev/null 2>&1; then
      printf '%s' "$n"; return 0
    fi
  fi
  n=$(tinct_list | head -1)
  [ -n "$n" ] || return 1
  printf '%s' "$n"
}

tinct_set_active() {
  tinct_theme_file "$1" >/dev/null 2>&1 || return 1
  mkdir -p "${TINCT_ACTIVE_FILE%/*}"
  printf '%s\n' "$1" > "$TINCT_ACTIVE_FILE"
}

# --- escape sequences --------------------------------------------------------
# Colors are set with OSC escapes, so they retint the terminal that is already
# open -- no profile to edit, no new window, nothing to restart.
#   OSC 10/11/12   fg / bg / cursor
#   OSC 17/19      selection bg / fg
#   OSC 4;N        palette entry N
#   OSC 104/11x    reset the above
tinct_seq() {
  local e out i c
  e=$(printf '\033')
  out="${e}]104\a"                      # clear whatever the last theme left
  [ -n "$TH_FG" ]     && out="${out}${e}]10;${TH_FG}\a"
  [ -n "$TH_BG" ]     && out="${out}${e}]11;${TH_BG}\a"
  [ -n "$TH_CURSOR" ] && out="${out}${e}]12;${TH_CURSOR}\a"
  [ -n "$TH_SEL_BG" ] && out="${out}${e}]17;${TH_SEL_BG}\a"
  [ -n "$TH_SEL_FG" ] && out="${out}${e}]19;${TH_SEL_FG}\a"
  i=0
  while [ $i -lt 16 ]; do
    c=${TH_ANSI[$i]}
    [ -n "$c" ] && out="${out}${e}]4;${i};${c}\a"
    i=$((i+1))
  done
  printf '%b' "$out"
}

tinct_reset_seq() {
  printf '\033]110\a\033]111\a\033]112\a\033]117\a\033]119\a\033]104\a'
}

# --- which terminals get painted ---------------------------------------------
# A theme change usually has to reach a program that is ALREADY RUNNING, often
# in a different tab. /dev/tty is no help there, so resolve the tty *device* of
# each watched process and write to it directly -- we own the device, so the
# kernel allows it.
tinct_ttys() {
  local cur pat line pid tty comm seen d
  seen=""

  if [ -n "${TINCT_TTY:-}" ]; then
    printf '%s\n' "$TINCT_TTY"
    return 0
  fi

  cur=$(tty 2>/dev/null)
  case $cur in
    /dev/*) [ -w "$cur" ] && { printf '%s\n' "$cur"; seen="$cur"; } ;;
  esac

  [ -n "$TINCT_WATCH" ] || return 0

  # TINCT_WATCH is a comma-separated list of program names.
  while IFS= read -r line; do
    read -r pid tty comm <<EOF
$line
EOF
    [ -n "$tty" ] || continue
    [ "$tty" = "??" ] && continue
    d="/dev/$tty"
    [ -w "$d" ] || continue
    case ":$seen:" in *":$d:"*) continue ;; esac
    comm=${comm##*/}
    local old_ifs=$IFS
    IFS=,
    for pat in $TINCT_WATCH; do
      tinct_trim_into "$pat"; pat=$TRIMMED
      [ -n "$pat" ] || continue
      case $comm in
        $pat) printf '%s\n' "$d"; seen="$seen:$d"; break ;;
      esac
    done
    IFS=$old_ifs
  done <<EOF
$(ps -Ao pid=,tty=,comm= 2>/dev/null)
EOF
}

# Write a sequence to every target terminal, falling back to stdout.
# Appending rather than truncating is identical for a tty device, but it keeps
# TINCT_TTY=<a regular file> usable as a capture log for the test suite.
tinct_emit() {
  local s=$1 d any=0
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    printf '%s' "$s" >> "$d" 2>/dev/null && any=1
  done <<EOF
$(tinct_ttys)
EOF
  [ "$any" = 1 ] || printf '%s' "$s"
  return 0
}

tinct_apply_live() { tinct_emit "$(tinct_seq)"; }
tinct_reset_live() { tinct_emit "$(tinct_reset_seq)"; }
