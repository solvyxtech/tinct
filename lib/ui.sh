# tinct interactive UI: the picker and the color editor.
#
# Layout is computed from the live terminal size on every frame. The list is a
# viewport into the theme array, never the whole array -- the old version drew
# all of it and let the terminal scroll, which meant the cursor was usually off
# screen on anything shorter than the theme count.

TINCT_EOL=$'\n'
TINCT_SAVED_STTY=""

# --- terminal plumbing -------------------------------------------------------
tinct_size() {             # -> TERM_ROWS / TERM_COLS, with sane fallbacks
  local sz
  # An explicit size wins over anything measured -- the tests pin a size to
  # assert the layout at window shapes nobody here happens to be using.
  if [ -n "${TINCT_ROWS:-}" ] && [ -n "${TINCT_COLS:-}" ]; then
    TERM_ROWS=$TINCT_ROWS; TERM_COLS=$TINCT_COLS
    return 0
  fi
  sz=$(stty size 2>/dev/null)
  TERM_ROWS=${sz%% *}
  TERM_COLS=${sz##* }
  case $TERM_ROWS in ''|*[!0-9]*) TERM_ROWS=${LINES:-24} ;; esac
  case $TERM_COLS in ''|*[!0-9]*) TERM_COLS=${COLUMNS:-80} ;; esac
  [ "$TERM_ROWS" -lt 1 ] && TERM_ROWS=24
  [ "$TERM_COLS" -lt 1 ] && TERM_COLS=80
}

tinct_raw_on() {
  TINCT_SAVED_STTY=$(stty -g 2>/dev/null)
  stty raw -echo 2>/dev/null
  printf '\033[?1049h\033[?25l'      # alt screen, hide cursor
  TINCT_EOL=$'\r\n'
}

tinct_raw_off() {
  printf '\033[?25h\033[?1049l'
  [ -n "$TINCT_SAVED_STTY" ] && stty "$TINCT_SAVED_STTY" 2>/dev/null
  TINCT_EOL=$'\n'
  return 0
}

# Frames are accumulated, not printed line by line, then flushed with a hard
# cap of TERM_ROWS and no trailing newline on the last row. Both matter: one
# line too many scrolls the alt screen and drags the header off the top, and
# an arithmetic budget spread across a dozen branches is the kind of thing
# that only breaks on somebody else's window size.
FRAME=()
FRAME_N=0

frame_reset() { FRAME=(); FRAME_N=0; }
out() { FRAME[$FRAME_N]=$1; FRAME_N=$((FRAME_N+1)); }

frame_flush() {
  local i=0 last=$FRAME_N
  [ "$last" -gt "$TERM_ROWS" ] && last=$TERM_ROWS
  while [ $i -lt "$last" ]; do
    if [ $i -eq $(( last - 1 )) ]; then
      printf '%b' "${FRAME[$i]}"
    else
      printf '%b%s' "${FRAME[$i]}" "$TINCT_EOL"
    fi
    i=$((i+1))
  done
}

# One-char reads. bash needs -N, not -n: with -n it treats CR as a delimiter
# and hands back an empty string, making Enter indistinguishable from NUL.
if [ -n "${ZSH_VERSION:-}" ]; then
  # -r matters even for a single character: without it a backslash is treated
  # as an escape rather than as the key somebody pressed.
  tinct_rd1()  { read -r -k 1 "$1"; }
  tinct_rd1t() { read -r -k 1 -t "$2" "$1"; }
else
  tinct_rd1()  { IFS= read -r -s -N 1 "$1"; }
  tinct_rd1t() { IFS= read -r -s -N 1 -t "$2" "$1"; }
fi

tinct_key() {              # -> KEY
  local k k2 k3 junk
  tinct_rd1 k || { KEY=quit; return; }
  case $k in
    $'\033')
      if tinct_rd1t k2 0.06 && { [ "$k2" = "[" ] || [ "$k2" = "O" ]; }; then
        tinct_rd1t k3 0.06
        case $k3 in
          A) KEY=up ;;    B) KEY=down ;;
          C) KEY=right ;; D) KEY=left ;;
          H) KEY=home ;;  F) KEY=end ;;
          5) tinct_rd1t junk 0.06; KEY=pgup ;;
          6) tinct_rd1t junk 0.06; KEY=pgdn ;;
          *) KEY=skip ;;
        esac
      else
        KEY=esc
      fi ;;
    $'\n'|$'\r') KEY=enter ;;
    $'\003')     KEY=quit ;;
    $'\025')     KEY=clear ;;      # ctrl-u
    $'\177'|$'\b') KEY=backspace ;;
    '')          KEY=skip ;;
    *)           KEY=$k ;;
  esac
}

tinct_ask() {              # cooked prompt inside the alt screen -> ANSWER
  local a
  [ -n "$TINCT_SAVED_STTY" ] && stty "$TINCT_SAVED_STTY" 2>/dev/null
  printf '\033[?25h'
  printf '%b ' "$TINCT_EOL$1"
  IFS= read -r a
  stty raw -echo 2>/dev/null
  printf '\033[?25l'
  ANSWER=$a
}

tinct_norm_hex() {         # fff / #FFF / aabbcc -> #AABBCC, else fail
  local h=${1#\#}
  case ${#h} in
    3|6) ;;
    *) return 1 ;;
  esac
  case $h in
    *[!0-9A-Fa-f]*) return 1 ;;
  esac
  [ ${#h} -eq 3 ] && h="${h:0:1}${h:0:1}${h:1:1}${h:1:1}${h:2:1}${h:2:1}"
  tinct_upper "#$h"
}

# --- viewport ----------------------------------------------------------------
# Pure scroll math, kept apart from any drawing so the tests can hammer it
# without a terminal. Given the previous top, return the new one such that idx
# is visible with `scrolloff` rows of context where the list allows it.
#
#   tinct_viewport_top <count> <height> <idx> <prev_top> <scrolloff> -> VIEW_TOP
tinct_viewport_top() {
  local n=$1 h=$2 idx=$3 top=$4 off=$5 max
  if [ "$h" -ge "$n" ]; then VIEW_TOP=0; return 0; fi

  # A margin bigger than half the window would fight itself at both edges.
  max=$(( (h - 1) / 2 ))
  [ "$off" -gt "$max" ] && off=$max
  [ "$off" -lt 0 ] && off=0

  [ "$top" -lt 0 ] && top=0
  [ $(( idx - off )) -lt "$top" ] && top=$(( idx - off ))
  [ $(( idx + off )) -gt $(( top + h - 1 )) ] && top=$(( idx + off - h + 1 ))

  # Never scroll past either end; the margin yields at the edges of the list.
  [ "$top" -gt $(( n - h )) ] && top=$(( n - h ))
  [ "$top" -lt 0 ] && top=0
  VIEW_TOP=$top
}

# Scrollbar glyph for one visible row, or a space when everything fits.
tinct_scroll_glyph() {     # <count> <height> <top> <row> -> GLYPH
  local n=$1 h=$2 top=$3 row=$4 size pos end
  if [ "$h" -ge "$n" ]; then GLYPH=' '; return 0; fi
  size=$(( h * h / n ))
  [ "$size" -lt 1 ] && size=1
  pos=$(( top * (h - size) / (n - h) ))
  end=$(( pos + size - 1 ))
  if [ "$row" -ge "$pos" ] && [ "$row" -le "$end" ]; then GLYPH='█'; else GLYPH='│'; fi
}

# --- preview -----------------------------------------------------------------
# The preview draws in the loaded theme's own colors rather than in palette
# entries. For the terminal you are sitting in the two look identical, because
# it has just been repainted to exactly those colors -- but when the target is
# a different terminal, this window has not been repainted and palette entries
# would show your colors while claiming to show theirs.
tinct_fg_esc() {           # <palette index> -> FGE
  local c=${TH_ANSI[$1]}
  if [ -n "$c" ]; then
    tinct_hex2rgb_into "$c"
    FGE="\033[38;2;${R};${G};${B}m"
  else
    FGE="\033[38;5;$1m"
  fi
}

# Sample output. Deliberately generic: it exercises bold, dim, and palette
# entries 1-6 the way a real session would, without pretending to be one.
tinct_sample_lines() {
  local f1 f2 f3 f4 f5 f6
  tinct_fg_esc 1; f1=$FGE
  tinct_fg_esc 2; f2=$FGE
  tinct_fg_esc 3; f3=$FGE
  tinct_fg_esc 4; f4=$FGE
  tinct_fg_esc 5; f5=$FGE
  tinct_fg_esc 6; f6=$FGE
  SAMPLE=()
  SAMPLE[0]="${f4}~/src/tinct\033[0m ${f2}main\033[0m ${f3}±\033[0m"
  SAMPLE[1]="${f5}\$\033[0m git commit -m 'retune the palette'"
  SAMPLE[2]="${f2} + accent = \"#8EC07C\"\033[0m"
  SAMPLE[3]="${f1} - accent = \"#83A598\"\033[0m"
  SAMPLE[4]="\033[1mbold primary\033[0m  \033[2mdim secondary\033[0m"
  SAMPLE[5]="${f6}✓ 24 passed\033[0m  ${f3}! 2 warn\033[0m  ${f1}✗ 1 failed\033[0m"
}

tinct_swatch_row() {       # <first> <last> -> ROW
  local i=$1 last=$2 s='' c
  while [ "$i" -le "$last" ]; do
    c=${TH_ANSI[$i]}
    if [ -n "$c" ]; then
      tinct_hex2rgb_into "$c"
      s="${s}\033[48;2;${R};${G};${B}m  \033[0m"
    else
      s="${s}\033[48;5;${i}m  \033[0m"
    fi
    i=$((i+1))
  done
  ROW=$s
}

# Pad or truncate plain text to exactly <width> columns, without forking.
# printf '%-*s' would need $(...) to capture, and the picker does this once
# per visible row per keystroke.
TINCT_SPACES='                                                                                                                                                                                                        '

tinct_pad() {              # <text> <width> -> PAD
  local s=$1 w=$2
  if [ "$w" -le 0 ]; then PAD=''; return 0; fi
  if [ ${#s} -ge "$w" ]; then PAD=${s:0:$w}; return 0; fi
  PAD="$s${TINCT_SPACES:0:$(( w - ${#s} ))}"
}

# Truncate plain text to a column count, with an ellipsis when it bites.
# Only ever applied to text before escapes are wrapped around it -- measuring
# a string that already contains escapes means counting past them, and cutting
# one in half puts the terminal into a state you cannot see to fix.
tinct_fit() {              # <text> <width> -> FIT
  local s=$1 w=$2
  if [ "$w" -le 0 ]; then FIT=''; return 0; fi
  if [ ${#s} -le "$w" ]; then FIT=$s; return 0; fi
  if [ "$w" -le 1 ]; then FIT=${s:0:$w}; return 0; fi
  FIT="${s:0:$(( w - 1 ))}…"
}

# Build the preview block for the loaded theme, in the width it has been given.
# Each row is composed to fit rather than truncated afterwards, so a long
# description or a narrow window costs detail instead of spilling over the edge.
tinct_preview_lines() {    # <want_sample 0|1> <width>
  local want=$1 w=$2 i=0
  PREVIEW=()

  tinct_fit "$TH_LABEL" "$w"
  PREVIEW[$i]="\033[1m${FIT}\033[0m"; i=$((i+1))
  if [ -n "$TH_DESC" ]; then
    tinct_fit "$TH_DESC" "$w"
    PREVIEW[$i]="\033[2m${FIT}\033[0m"; i=$((i+1))
  fi

  if [ "$w" -ge 16 ]; then
    PREVIEW[$i]=""; i=$((i+1))
    tinct_swatch_row 0 7;  PREVIEW[$i]=$ROW; i=$((i+1))
    tinct_swatch_row 8 15; PREVIEW[$i]=$ROW; i=$((i+1))
  fi

  PREVIEW[$i]=""; i=$((i+1))
  if [ "$w" -ge 22 ]; then
    PREVIEW[$i]="\033[2mbg\033[0m ${TH_BG:---------}  \033[2mfg\033[0m ${TH_FG:---------}"
    i=$((i+1))
  elif [ "$w" -ge 10 ]; then
    PREVIEW[$i]="\033[2mbg\033[0m ${TH_BG:---------}"; i=$((i+1))
  fi

  if [ -n "$TH_FG" ] && [ -n "$TH_BG" ] && [ "$w" -ge 15 ]; then
    tinct_contrast_into "$TH_FG" "$TH_BG"
    if [ "$w" -ge 27 ] && [ "$CONTRAST_LOW" = low ]; then
      PREVIEW[$i]="\033[2mcontrast\033[0m ${CONTRAST}:1 \033[38;5;1m· under AA\033[0m"
    else
      PREVIEW[$i]="\033[2mcontrast\033[0m ${CONTRAST}:1"
    fi
    i=$((i+1))
  fi

  # The sample is fixed text with escapes threaded through it, so it is shown
  # whole or not at all. 36 columns is its widest line.
  if [ "$want" = 1 ] && [ "$w" -ge 36 ]; then
    PREVIEW[$i]=""; i=$((i+1))
    tinct_sample_lines
    local j=0
    while [ $j -lt ${#SAMPLE[@]} ]; do
      PREVIEW[$i]=${SAMPLE[$j]}; i=$((i+1)); j=$((j+1))
    done
  fi
}

# --- picker ------------------------------------------------------------------
TINCT_NAMEW=20            # widest bundled name is 19 ("high-contrast-light")

# Where previewing writes. Empty means this terminal.
TARGET_DEV=''
tinct_target_apply() {
  if [ -n "$TARGET_DEV" ]; then
    tinct_apply_to "$TARGET_DEV"
  else
    tinct_apply_live
  fi
}

tinct_filter_apply() {     # THEMES + FILTER -> SHOWN
  local i=0 n
  SHOWN=()
  if [ -z "$FILTER" ]; then
    while [ $i -lt ${#THEMES[@]} ]; do SHOWN[$i]=${THEMES[$i]}; i=$((i+1)); done
    return 0
  fi
  local q; q=$(printf '%s' "$FILTER" | tr '[:upper:]' '[:lower:]')
  local j=0
  while [ $i -lt ${#THEMES[@]} ]; do
    n=$(printf '%s' "${THEMES[$i]}" | tr '[:upper:]' '[:lower:]')
    case $n in *"$q"*) SHOWN[$j]=${THEMES[$i]}; j=$((j+1)) ;; esac
    i=$((i+1))
  done
}

# Draw one frame to stdout. Reads SHOWN/IDX/TOP/FILTER and the loaded TH_*.
tinct_draw_picker() {
  local n=${#SHOWN[@]} band twopane leftw namew i row name mark dot sty rst
  local left right glyph plain

  tinct_size
  band=$(( TERM_ROWS - 5 ))
  [ "$band" -lt 1 ] && band=1

  if [ "$TERM_COLS" -ge 80 ]; then twopane=1; else twopane=0; fi

  namew=$TINCT_NAMEW
  # One column: let the name field take the width so the scrollbar sits on the
  # right edge instead of floating in the middle of an empty row.
  [ "$twopane" = 0 ] && namew=$(( TERM_COLS - 9 ))
  [ "$namew" -lt 6 ] && namew=6
  leftw=$(( namew + 8 ))

  # In one column the preview sits under the list, so it costs list rows.
  local listh=$band previewh=0 wantsample=0
  if [ "$twopane" = 1 ]; then
    wantsample=1
    [ "$band" -lt 15 ] && wantsample=0
  else
    previewh=5
    [ "$band" -ge 16 ] && { previewh=11; wantsample=1; }
    listh=$(( band - previewh - 1 ))
    if [ "$listh" -lt 3 ]; then listh=$band; previewh=0; wantsample=0; fi
  fi
  [ "$listh" -lt 1 ] && listh=1

  # Width available to the preview: beside the list, or the full row under it.
  local previeww
  if [ "$twopane" = 1 ]; then previeww=$(( TERM_COLS - leftw - 3 ))
  else                        previeww=$(( TERM_COLS - 2 )); fi
  [ "$previeww" -lt 0 ] && previeww=0

  tinct_preview_lines "$wantsample" "$previeww"
  tinct_viewport_top "$n" "$listh" "$IDX" "$TOP" "$TINCT_SCROLLOFF"
  TOP=$VIEW_TOP

  frame_reset
  out ""
  # "  tinct  " is 9 columns before the status text starts.
  local statusw=$(( TERM_COLS - 9 ))
  if [ -n "$FILTER" ]; then
    tinct_fit "${FILTER} · ${n} of ${#THEMES[@]}" "$statusw"
    out "  \033[1mtinct\033[0m  \033[2m/\033[0m\033[2m${FIT}\033[0m"
  else
    tinct_fit "${n} themes · ${TINCT_HEADER_NOTE}" "$statusw"
    out "  \033[1mtinct\033[0m  \033[2m${FIT}\033[0m"
  fi
  out ""

  if [ "$n" -eq 0 ]; then
    tinct_fit "nothing matches '${FILTER}'" $(( TERM_COLS - 2 ))
    out "  \033[38;5;1m${FIT}\033[0m"
    i=1
    while [ $i -lt "$band" ]; do out ""; i=$((i+1)); done
  else
    i=0
    while [ $i -lt "$listh" ]; do
      row=$(( TOP + i ))
      if [ "$row" -lt "$n" ]; then
        name=${SHOWN[$row]}
        if [ "$row" -eq "$IDX" ]; then mark='▸'; sty='\033[7m'; rst='\033[0m'
        else                           mark=' '; sty='';        rst=''; fi
        if [ "$name" = "$ACTIVE_NAME" ]; then dot='\033[38;5;2m●\033[0m'; else dot=' '; fi
        tinct_pad "$name" "$namew"
        tinct_scroll_glyph "$n" "$listh" "$TOP" "$i"
        left="  ${dot} ${sty}${mark} ${PAD} ${rst}\033[2m${GLYPH}\033[0m"
      else
        tinct_pad '' "$leftw"; left=$PAD
      fi

      if [ "$twopane" = 1 ]; then
        if [ $i -lt ${#PREVIEW[@]} ]; then right=${PREVIEW[$i]}; else right=''; fi
        if [ -n "$right" ]; then out "${left}   ${right}"; else out "${left}"; fi
      else
        out "${left}"
      fi
      i=$((i+1))
    done

    if [ "$twopane" = 0 ] && [ "$previewh" -gt 0 ]; then
      out ""
      i=0
      while [ $i -lt "$previewh" ]; do
        if [ $i -lt ${#PREVIEW[@]} ]; then out "  ${PREVIEW[$i]}"; else out ""; fi
        i=$((i+1))
      done
    fi
  fi

  out ""
  # Long hint where there is room, short hint where there is not.
  local hint
  if [ "$MODE" = filter ]; then
    hint=' type to narrow · ⏎ accept · esc clear'
    [ "$TERM_COLS" -lt 42 ] && hint=' ⏎ ok · esc clear'
  else
    hint=' ↑↓ move · ⏎ set here · d default · A all · / find · e edit · q'
    [ "$TERM_COLS" -lt 66 ] && hint=' ↑↓ · ⏎ here · d default · A all · / find · q'
    [ "$TERM_COLS" -lt 46 ] && hint=' ↑↓ · ⏎ set · / find · q'
    [ "$TERM_COLS" -lt 26 ] && hint=' ⏎ set · q'
  fi
  tinct_fit "$hint" $(( TERM_COLS - 2 ))
  out "  \033[2m${FIT}\033[0m"

  printf '\033[H\033[2J'
  frame_flush
}

tinct_select() {
  if [ ! -t 0 ] || [ ! -t 1 ]; then
    printf 'tinct: the picker needs a terminal.\n' >&2
    printf "try: tinct set <name>   (or 'tinct ls' to see them)\n" >&2
    return 1
  fi

  THEMES=()
  local i=0
  while IFS= read -r n; do THEMES[$i]=$n; i=$((i+1)); done <<EOF
$(tinct_list)
EOF
  [ ${#THEMES[@]} -gt 0 ] || { printf 'tinct: no themes found\n' >&2; return 1; }

  # With no argument the target is this terminal. With one, it is somebody
  # else's -- previewing then paints there while the picker keeps drawing here.
  local here
  if [ -n "${1:-}" ]; then
    # Accept either /dev/ttys004 or ttys004. The device path is what gets
    # written to; the bare name is what the session record is keyed by.
    case $1 in
      /*) TARGET_DEV=$1 ;;
      *)  TARGET_DEV=/dev/$1 ;;
    esac
    here=${TARGET_DEV#/dev/}
  else
    here=$(tinct_this_tty 2>/dev/null) || here=''
    TARGET_DEV=''
  fi
  tinct_resolve "$here"
  ACTIVE_NAME=$RESOLVED
  if [ -n "$TARGET_DEV" ]; then
    TINCT_HEADER_NOTE="${here}: ${RESOLVED}"
  else
    TINCT_HEADER_NOTE="here: ${RESOLVED}"
  fi
  local orig=$ACTIVE_NAME
  FILTER=""; MODE=normal; TOP=0; IDX=0
  tinct_filter_apply
  i=0
  while [ $i -lt ${#SHOWN[@]} ]; do
    [ "${SHOWN[$i]}" = "$orig" ] && IDX=$i
    i=$((i+1))
  done

  local chosen='' edit_next='' prev_idx=-1
  SCOPE=here

  tinct_raw_on
  trap 'tinct_raw_off' EXIT INT TERM
  while :; do
    if [ ${#SHOWN[@]} -gt 0 ] && [ "$IDX" != "$prev_idx" ]; then
      tinct_load "${SHOWN[$IDX]}" && tinct_target_apply
      prev_idx=$IDX
    fi
    tinct_draw_picker
    tinct_key

    if [ "$MODE" = filter ]; then
      case $KEY in
        enter)     MODE=normal ;;
        esc)       FILTER=""; MODE=normal; tinct_filter_apply; IDX=0; TOP=0; prev_idx=-1 ;;
        clear)     FILTER=""; tinct_filter_apply; IDX=0; TOP=0; prev_idx=-1 ;;
        backspace) FILTER=${FILTER%?}; tinct_filter_apply; IDX=0; TOP=0; prev_idx=-1 ;;
        up)        [ "$IDX" -gt 0 ] && IDX=$((IDX-1)) ;;
        down)      [ "$IDX" -lt $(( ${#SHOWN[@]} - 1 )) ] && IDX=$((IDX+1)) ;;
        quit)      break ;;
        skip)      ;;
        *)
          # Anything else that is a single printable character types into the
          # filter. Note [!-~] would be read as a negated set, not a range.
          if [ ${#KEY} -eq 1 ]; then
            case $KEY in
              [[:print:]])
                FILTER="${FILTER}${KEY}"
                tinct_filter_apply; IDX=0; TOP=0; prev_idx=-1 ;;
            esac
          fi ;;
      esac
      continue
    fi

    case $KEY in
      up|k)    [ "$IDX" -gt 0 ] && IDX=$((IDX-1)) ;;
      down|j)  [ "$IDX" -lt $(( ${#SHOWN[@]} - 1 )) ] && IDX=$((IDX+1)) ;;
      pgup)    IDX=$(( IDX - 10 )); [ "$IDX" -lt 0 ] && IDX=0 ;;
      pgdn)    IDX=$(( IDX + 10 ))
               [ "$IDX" -gt $(( ${#SHOWN[@]} - 1 )) ] && IDX=$(( ${#SHOWN[@]} - 1 )) ;;
      home|g)  IDX=0 ;;
      end|G)   IDX=$(( ${#SHOWN[@]} - 1 )) ;;
      /)       MODE=filter ;;
      enter)   [ ${#SHOWN[@]} -gt 0 ] && { chosen=${SHOWN[$IDX]}; SCOPE=here;    break; } ;;
      d)       [ ${#SHOWN[@]} -gt 0 ] && { chosen=${SHOWN[$IDX]}; SCOPE=default; break; } ;;
      A)       [ ${#SHOWN[@]} -gt 0 ] && { chosen=${SHOWN[$IDX]}; SCOPE=all;     break; } ;;
      e)       [ ${#SHOWN[@]} -gt 0 ] && { edit_next=${SHOWN[$IDX]}; break; } ;;
      q|quit|esc) break ;;
    esac
  done
  trap - EXIT INT TERM
  tinct_raw_off

  if [ -n "$edit_next" ]; then
    tinct_edit "$edit_next"
    return $?
  fi

  if [ -z "$chosen" ]; then
    tinct_load "$orig" && tinct_target_apply
    printf 'cancelled, still on %s\n' "$orig"
    return 0
  fi

  local devs d count=0
  tinct_load "$chosen"

  case $SCOPE in
    all)
      tinct_seq_into
      devs=$(tinct_ttys)
      while IFS= read -r d; do
        [ -n "$d" ] || continue
        tinct_emit_to "$SEQ" "$d" || continue
        tinct_session_set "${d#/dev/}" "$chosen"
        count=$((count+1))
      done <<EOF
$devs
EOF
      printf '%s applied to %d terminals\n' "$chosen" "$count" ;;
    default)
      tinct_target_apply
      tinct_set_default "$chosen"
      [ -n "$here" ] && tinct_session_set "$here" "$chosen"
      printf '%s set here, and as the default for new terminals\n' "$chosen" ;;
    *)
      tinct_target_apply
      if [ -n "$here" ]; then
        tinct_session_set "$here" "$chosen"
        if [ -n "$TARGET_DEV" ]; then
          printf '%s set for %s\n' "$chosen" "$here"
        else
          printf '%s set for this terminal\n' "$chosen"
        fi
      else
        tinct_set_default "$chosen"
        printf '%s set as the default\n' "$chosen"
      fi ;;
  esac
}

# --- terminal picker ---------------------------------------------------------
# Every terminal you have open, and what each is showing. Pick one and the
# theme picker opens aimed at it: moving the cursor repaints that window while
# this one keeps drawing the list.

tinct_terminals_collect() {   # -> TERM_DEV / TERM_NAME / TERM_THEME / TERM_PROG / TERM_WHY
  local d i=0
  TERM_DEV=(); TERM_NAME=(); TERM_THEME=(); TERM_PROG=(); TERM_WHY=()
  TINCT_TTYS_CACHED=0        # windows open and close while this is on screen
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    TERM_DEV[$i]=$d
    TERM_NAME[$i]=${d#/dev/}
    tinct_resolve "${d#/dev/}"
    TERM_THEME[$i]=$RESOLVED
    case $RESOLVED_BY in
      pinned*) TERM_WHY[$i]=pinned ;;
      *)       TERM_WHY[$i]=default ;;
    esac
    TERM_PROG[$i]=$(tinct_tty_program "${d#/dev/}")
    i=$((i+1))
  done <<EOF
$(tinct_ttys)
EOF
}

tinct_draw_terminals() {
  local n=${#TERM_DEV[@]} band twopane leftw i row sty rst mark here
  local left right previeww

  tinct_size
  band=$(( TERM_ROWS - 5 ))
  [ "$band" -lt 1 ] && band=1
  if [ "$TERM_COLS" -ge 84 ]; then twopane=1; else twopane=0; fi

  # marker(2) name(10) theme(20) program(11) state(8)
  leftw=52
  [ "$leftw" -gt $(( TERM_COLS - 2 )) ] && leftw=$(( TERM_COLS - 2 ))

  if [ "$twopane" = 1 ]; then previeww=$(( TERM_COLS - leftw - 3 )); else previeww=0; fi
  [ "$previeww" -lt 0 ] && previeww=0

  if [ "$n" -gt 0 ]; then
    tinct_load "${TERM_THEME[$TIDX]}" 2>/dev/null
    [ "$twopane" = 1 ] && tinct_preview_lines 1 "$previeww"
  fi

  tinct_viewport_top "$n" "$band" "$TIDX" "$TTOP" "$TINCT_SCROLLOFF"
  TTOP=$VIEW_TOP

  here=$(tinct_this_tty 2>/dev/null) || here=''

  frame_reset
  out ""
  tinct_fit "${n} open · ⏎ to change one" $(( TERM_COLS - 9 ))
  out "  \033[1mtinct\033[0m  \033[2m${FIT}\033[0m"
  out ""

  i=0
  while [ $i -lt "$band" ]; do
    row=$(( TTOP + i ))
    if [ "$row" -lt "$n" ]; then
      if [ "$row" -eq "$TIDX" ]; then mark='▸'; sty='\033[7m'; rst='\033[0m'
      else                            mark=' '; sty='';        rst=''; fi
      tinct_pad "${TERM_NAME[$row]}" 10;        left="${PAD}"
      tinct_pad "${TERM_THEME[$row]}" 20;       left="${left} ${PAD}"
      tinct_pad "${TERM_PROG[$row]:--}" 11;     left="${left} ${PAD}"
      tinct_pad "${TERM_WHY[$row]}" 7;          left="${left} ${PAD}"
      if [ "${TERM_NAME[$row]}" = "$here" ]; then
        left="  ${sty}${mark} ${left}${rst}\033[2m·you\033[0m"
      else
        left="  ${sty}${mark} ${left}${rst}"
      fi
      tinct_scroll_glyph "$n" "$band" "$TTOP" "$i"
      left="${left} \033[2m${GLYPH}\033[0m"
    else
      tinct_pad '' "$leftw"; left=$PAD
    fi

    if [ "$twopane" = 1 ] && [ $i -lt ${#PREVIEW[@]} ] && [ -n "${PREVIEW[$i]}" ]; then
      out "${left}  ${PREVIEW[$i]}"
    else
      out "${left}"
    fi
    i=$((i+1))
  done

  out ""
  local hint=' ↑↓ move · ⏎ change theme · c unpin · r refresh · q back'
  [ "$TERM_COLS" -lt 60 ] && hint=' ↑↓ · ⏎ theme · c unpin · q'
  tinct_fit "$hint" $(( TERM_COLS - 2 ))
  out "  \033[2m${FIT}\033[0m"

  printf '\033[H\033[2J'
  frame_flush
}

tinct_select_terminal() {
  if [ ! -t 0 ] || [ ! -t 1 ]; then
    printf 'tinct: picking a terminal needs a terminal.\n' >&2
    printf 'try: tinct sessions | cat   (plain listing)\n' >&2
    return 1
  fi

  TIDX=0; TTOP=0
  tinct_terminals_collect
  if [ ${#TERM_DEV[@]} -eq 0 ]; then
    printf 'tinct: no terminals found\n' >&2
    return 1
  fi

  # Start on the terminal you are sitting in, since it is the likeliest one.
  local here i
  here=$(tinct_this_tty 2>/dev/null) || here=''
  i=0
  while [ $i -lt ${#TERM_DEV[@]} ]; do
    [ "${TERM_NAME[$i]}" = "$here" ] && TIDX=$i
    i=$((i+1))
  done

  local target
  while :; do
    tinct_raw_on
    trap 'tinct_raw_off' EXIT INT TERM
    local leaving=''
    while :; do
      tinct_draw_terminals
      tinct_key
      case $KEY in
        up|k)    [ "$TIDX" -gt 0 ] && TIDX=$((TIDX-1)) ;;
        down|j)  [ "$TIDX" -lt $(( ${#TERM_DEV[@]} - 1 )) ] && TIDX=$((TIDX+1)) ;;
        pgup)    TIDX=$(( TIDX - 10 )); [ "$TIDX" -lt 0 ] && TIDX=0 ;;
        pgdn)    TIDX=$(( TIDX + 10 ))
                 [ "$TIDX" -gt $(( ${#TERM_DEV[@]} - 1 )) ] && TIDX=$(( ${#TERM_DEV[@]} - 1 )) ;;
        home|g)  TIDX=0 ;;
        end|G)   TIDX=$(( ${#TERM_DEV[@]} - 1 )) ;;
        r)       leaving=refresh; break ;;
        c)       tinct_session_clear "${TERM_NAME[$TIDX]}"
                 tinct_resolve "${TERM_NAME[$TIDX]}"
                 tinct_load "$RESOLVED" && tinct_apply_to "${TERM_DEV[$TIDX]}"
                 leaving=refresh; break ;;
        enter)   leaving=theme; break ;;
        q|quit|esc) leaving=stop; break ;;
      esac
    done
    trap - EXIT INT TERM
    tinct_raw_off

    case $leaving in
      theme)
        target=${TERM_DEV[$TIDX]}
        tinct_select "$target"
        tinct_terminals_collect ;;
      refresh)
        tinct_terminals_collect ;;
      *)
        return 0 ;;
    esac

    [ ${#TERM_DEV[@]} -gt 0 ] || return 0
    [ "$TIDX" -ge ${#TERM_DEV[@]} ] && TIDX=$(( ${#TERM_DEV[@]} - 1 ))
  done
}
