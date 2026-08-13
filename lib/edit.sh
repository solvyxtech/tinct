# tinct colour editor: nudge a theme's colours and watch the terminal follow.

# Slot order is the order the cursor walks: the five window colours, then the
# sixteen palette entries.
TINCT_SLOTS=(BG FG CURSOR SEL_BG SEL_FG)
TINCT_SLOTLBL=(bg fg cursor sel.bg sel.fg)
_i=0
while [ $_i -lt 16 ]; do
  TINCT_SLOTS[$(( _i + 5 ))]="ANSI$_i"
  TINCT_SLOTLBL[$(( _i + 5 ))]="$_i"
  _i=$(( _i + 1 ))
done
unset _i

# xterm's defaults, used to seed a slot that the theme leaves unset so nudging
# an empty palette entry starts somewhere sensible instead of at black.
TINCT_XTERM=(
  '#000000' '#CD0000' '#00CD00' '#CDCD00' '#0000EE' '#CD00CD' '#00CDCD' '#E5E5E5'
  '#7F7F7F' '#FF0000' '#00FF00' '#FFFF00' '#5C5CFF' '#FF00FF' '#00FFFF' '#FFFFFF'
)

TINCT_CELLW=23            # mark2 sp label7 sp swatch2 sp hex7 gap2

tinct_edit_cell() {       # <slot index, or -1 for filler> -> CELL
  local i=$1 key lbl hex mark sty rst sw rgb
  if [ "$i" -lt 0 ] || [ "$i" -ge ${#TINCT_SLOTS[@]} ]; then
    CELL=$(printf '%*s' "$TINCT_CELLW" '')
    return 0
  fi
  key=${TINCT_SLOTS[$i]}
  lbl=${TINCT_SLOTLBL[$i]}
  hex=${V["$key"]}
  if [ "$i" -eq "$CUR" ]; then mark=' \033[1m▸'; sty='\033[1m'; rst='\033[0m'
  else                         mark='  ';        sty='';        rst=''; fi
  if [ -n "$hex" ]; then
    rgb=$(tinct_hex2rgb "$hex")
    sw="\033[48;2;${rgb// /;}m  \033[0m"
  else
    sw='\033[2m··\033[0m'; hex='   --  '
  fi
  CELL="${mark} ${sty}$(printf '%-7.7s' "$lbl")${rst} ${sw} $(printf '%-7.7s' "$hex")  "
}

tinct_edit_push() {       # V -> TH_* -> the terminal
  TH_BG=${V["BG"]}; TH_FG=${V["FG"]}; TH_CURSOR=${V["CURSOR"]}
  TH_SEL_BG=${V["SEL_BG"]}; TH_SEL_FG=${V["SEL_FG"]}
  TH_ANSI=()
  local i=0
  while [ $i -lt 16 ]; do TH_ANSI[$i]=${V["ANSI$i"]}; i=$((i+1)); done
  tinct_apply_live
}

tinct_edit_seed() {       # cache float HSL for a slot
  local key=$1 cur hsl h s l
  cur=${V["$key"]}
  if [ -z "$cur" ]; then
    case $key in
      ANSI*) cur=${TINCT_XTERM[${key#ANSI}]} ;;
      *)     cur='#808080' ;;
    esac
  fi
  hsl=$(tinct_hex2hsl "$cur")
  read -r h s l <<EOF
$hsl
EOF
  HH["$key"]=$h; SS["$key"]=$s; LL["$key"]=$l
}

tinct_edit_nudge() {      # <h|s|l> <delta>
  local key=${TINCT_SLOTS[$CUR]} h s l
  # Nudge the cached float, never a value re-derived from the rounded hex --
  # otherwise left/right would not round-trip and the hue drifts as you hold
  # a key down.
  [ -n "${HH["$key"]}" ] || tinct_edit_seed "$key"
  h=${HH["$key"]}; s=${SS["$key"]}; l=${LL["$key"]}
  case $1 in
    h) h=$(awk -v v="$h" -v d="$2" 'BEGIN{v+=d; while(v<0)v+=360; while(v>=360)v-=360; print v}') ;;
    s) s=$(awk -v v="$s" -v d="$2" 'BEGIN{v+=d; if(v<0)v=0; if(v>100)v=100; print v}') ;;
    l) l=$(awk -v v="$l" -v d="$2" 'BEGIN{v+=d; if(v<0)v=0; if(v>100)v=100; print v}') ;;
  esac
  HH["$key"]=$h; SS["$key"]=$s; LL["$key"]=$l
  V["$key"]=$(tinct_hsl2hex "$h" "$s" "$l")
  DIRTY=1
}

tinct_edit_write() {      # <name>
  local dest=$TINCT_THEME_DIR/$1.theme i
  mkdir -p "$TINCT_THEME_DIR"
  {
    printf '# %s\n' "$1"
    printf 'LABEL=%s\n' "$LABEL"
    printf 'DESC=%s\n' "$DESC"
    printf '\n'
    for i in BG FG CURSOR SEL_BG SEL_FG; do
      [ -n "${V["$i"]}" ] && printf '%s=%s\n' "$i" "${V["$i"]}"
    done
    printf '\n'
    i=0
    while [ $i -lt 16 ]; do
      [ -n "${V["ANSI$i"]}" ] && printf 'ANSI%s=%s\n' "$i" "${V["ANSI$i"]}"
      i=$((i+1))
    done
  } > "$dest"
}

tinct_draw_edit() {
  local gcols grows band i r c slot line contrast warn

  tinct_size
  band=$(( TERM_ROWS - 5 ))
  [ "$band" -lt 1 ] && band=1

  gcols=$(( (TERM_COLS - 2) / TINCT_CELLW ))
  [ "$gcols" -gt 3 ] && gcols=3
  [ "$gcols" -lt 1 ] && gcols=1
  grows=$(( (${#TINCT_SLOTS[@]} + gcols - 1) / gcols ))

  frame_reset
  out ""
  if [ -n "$DIRTY" ]; then
    out "  \033[1m${NAME}\033[0m  \033[38;5;3mmodified\033[0m"
  else
    out "  \033[1m${NAME}\033[0m"
  fi
  out ""

  # Three columns get the tidy arrangement the slots were designed for:
  # window colours down the left, the two palette halves beside them.
  i=0
  while [ $i -lt "$grows" ]; do
    line=''
    c=0
    while [ $c -lt "$gcols" ]; do
      if [ "$gcols" -eq 3 ]; then
        case $c in
          0) slot=$([ $i -lt 5 ] && echo $i || echo -1) ;;
          1) slot=$(( 5 + i )) ;;
          *) slot=$(( 13 + i )) ;;
        esac
        [ $i -ge 8 ] && slot=-1
      else
        slot=$(( i * gcols + c ))
        [ "$slot" -ge ${#TINCT_SLOTS[@]} ] && slot=-1
      fi
      tinct_edit_cell "$slot"
      line="${line}${CELL}"
      c=$((c+1))
    done
    out "$line"
    i=$((i+1))
    [ "$gcols" -eq 3 ] && [ $i -ge 8 ] && break
  done

  out ""
  if [ -n "${V["FG"]}" ] && [ -n "${V["BG"]}" ]; then
    contrast=$(tinct_contrast "${V["FG"]}" "${V["BG"]}")
    warn=$(awk -v c="$contrast" 'BEGIN{print (c < 4.5) ? " \033[38;5;1m· under AA (4.5)\033[0m" : ""}')
    out "  \033[2mfg/bg contrast\033[0m ${contrast}:1${warn}"
  fi

  # What is left after the grid decides how much preview fits. The footer and
  # the message line are reserved first -- they are the two things you always
  # need to see.
  local spare=$(( TERM_ROWS - FRAME_N - 3 ))
  if [ "$spare" -ge 11 ]; then
    out ""
    tinct_swatch_row 0 7;  out "  $ROW"
    tinct_swatch_row 8 15; out "  $ROW"
    out ""
    tinct_sample_lines
    i=0
    while [ $i -lt ${#SAMPLE[@]} ]; do out "  ${SAMPLE[$i]}"; i=$((i+1)); done
  elif [ "$spare" -ge 3 ]; then
    out ""
    tinct_swatch_row 0 7;  out "  $ROW"
    tinct_swatch_row 8 15; out "  $ROW"
  fi

  out ""
  out "  \033[2m ↑↓ slot · ←→ light · ,. hue · -= sat · x hex · w save · a save as · r revert · q done\033[0m"
  [ -n "$MSG" ] && out "  $MSG"

  printf '\033[H\033[2J'
  frame_flush
}

tinct_edit() {
  if [ ! -t 0 ] || [ ! -t 1 ]; then
    printf 'tinct: the editor needs a terminal.\n' >&2
    printf 'themes are plain text in %s\n' "$TINCT_THEME_DIR" >&2
    return 1
  fi

  NAME=${1:-$(tinct_active)}
  local file
  file=$(tinct_theme_file "$NAME") || { printf 'tinct: no such theme: %s\n' "$NAME" >&2; return 1; }

  typeset -A V HH SS LL
  CUR=0; DIRTY=''; MSG=''
  local h newname

  tinct_edit_load() {
    tinct_load "$file"
    LABEL=$TH_LABEL; DESC=$TH_DESC
    V=(); HH=(); SS=(); LL=()          # drop cached HSL, reseed from the file
    V["BG"]=$TH_BG; V["FG"]=$TH_FG; V["CURSOR"]=$TH_CURSOR
    V["SEL_BG"]=$TH_SEL_BG; V["SEL_FG"]=$TH_SEL_FG
    local j=0
    while [ $j -lt 16 ]; do V["ANSI$j"]=${TH_ANSI[$j]}; j=$((j+1)); done
    DIRTY=''
  }
  tinct_edit_load

  tinct_raw_on
  trap 'tinct_raw_off' EXIT INT TERM
  while :; do
    tinct_edit_push
    tinct_draw_edit
    MSG=''
    tinct_key
    case $KEY in
      up|k)    [ "$CUR" -gt 0 ] && CUR=$((CUR-1)) ;;
      down|j)  [ "$CUR" -lt $(( ${#TINCT_SLOTS[@]} - 1 )) ] && CUR=$((CUR+1)) ;;
      home)    CUR=0 ;;
      end)     CUR=$(( ${#TINCT_SLOTS[@]} - 1 )) ;;
      left)    tinct_edit_nudge l -2 ;;
      right)   tinct_edit_nudge l  2 ;;
      ',')     tinct_edit_nudge h -6 ;;
      '.')     tinct_edit_nudge h  6 ;;
      '-'|'_') tinct_edit_nudge s -4 ;;
      '='|'+') tinct_edit_nudge s  4 ;;
      x)
        tinct_ask "hex for ${TINCT_SLOTLBL[$CUR]} (blank clears it):"
        if [ -z "$ANSWER" ]; then
          V["${TINCT_SLOTS[$CUR]}"]=''
          unset "HH[${TINCT_SLOTS[$CUR]}]"
          DIRTY=1
        elif h=$(tinct_norm_hex "$ANSWER"); then
          V["${TINCT_SLOTS[$CUR]}"]=$h
          tinct_edit_seed "${TINCT_SLOTS[$CUR]}"
          DIRTY=1
        else
          MSG="\033[38;5;1mnot a hex colour: ${ANSWER}\033[0m"
        fi ;;
      w)
        tinct_edit_write "$NAME"
        tinct_set_active "$NAME"
        file=$TINCT_THEME_DIR/$NAME.theme
        DIRTY=''
        MSG="\033[38;5;2msaved\033[0m ${TINCT_THEME_DIR}/${NAME}.theme" ;;
      a)
        tinct_ask "save as:"
        if [ -n "$ANSWER" ]; then
          newname=$(tinct_slug "$ANSWER")
          if [ -n "$newname" ]; then
            LABEL=$newname; NAME=$newname
            file=$TINCT_THEME_DIR/$NAME.theme
            tinct_edit_write "$NAME"
            tinct_set_active "$NAME"
            DIRTY=''
            MSG="\033[38;5;2mcreated\033[0m ${file}"
          fi
        fi ;;
      r) tinct_edit_load; MSG='reverted to the saved file' ;;
      q|quit|esc) break ;;
    esac
  done
  trap - EXIT INT TERM
  tinct_raw_off

  if [ -n "$DIRTY" ]; then
    printf 'unsaved changes to %s were discarded\n' "$NAME"
    local back
    back=$(tinct_active)
    tinct_load "$back" && tinct_apply_live
  else
    tinct_edit_push
    printf '%s applied\n' "$NAME"
  fi
}
