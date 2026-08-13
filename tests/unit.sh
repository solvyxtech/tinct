# tinct unit tests -- pure functions, no terminal required.
# Run via tests/run.sh, which executes this under both zsh and bash.

if [ -n "${ZSH_VERSION:-}" ]; then
  setopt ksh_arrays 2>/dev/null
  setopt no_nomatch 2>/dev/null
  SH=zsh
else
  SH=bash
fi

TINCT_ROOT=${TINCT_ROOT:-$(cd -- "$(dirname "$0")/.." && pwd -P)}
TINCT_HOME=$(mktemp -d)
TINCT_THEME_DIR=$TINCT_HOME/themes
TINCT_ACTIVE_FILE=$TINCT_HOME/active
TINCT_CONFIG_FILE=$TINCT_HOME/config
# Hermetic: point the bundled dir at an empty directory so the repo's own
# themes cannot influence listing, fallback or shadowing assertions.
TINCT_BUNDLED_DIR=$TINCT_HOME/bundled
mkdir -p "$TINCT_THEME_DIR" "$TINCT_BUNDLED_DIR"

. "$TINCT_ROOT/lib/core.sh"
. "$TINCT_ROOT/lib/ui.sh"
. "$TINCT_ROOT/lib/edit.sh"

PASS=0; FAIL=0
eq() {   # eq <label> <expected> <actual>
  if [ "$2" = "$3" ]; then PASS=$((PASS+1))
  else FAIL=$((FAIL+1)); printf '  FAIL %s: want [%s] got [%s]\n' "$1" "$2" "$3"; fi
}
ok() { if [ "$2" = 1 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; fi; }

# --- viewport: the property that was actually broken -------------------------
# For every list size, window height, cursor position and prior scroll offset,
# the cursor must end up inside the window and the window must stay in range.
vp_matrix() {
  local n h idx top bad_vis=0 bad_range=0 count=0
  for n in 1 2 5 23 36 37 100; do
    for h in 1 2 3 7 23 40; do
      idx=0
      while [ "$idx" -lt "$n" ]; do
        for top in 0 1 5 99 -3; do
          tinct_viewport_top "$n" "$h" "$idx" "$top" 2
          count=$((count+1))
          [ "$VIEW_TOP" -le "$idx" ] || bad_vis=1
          [ "$idx" -le $(( VIEW_TOP + h - 1 )) ] || bad_vis=1
          [ "$VIEW_TOP" -ge 0 ] || bad_range=1
          if [ "$h" -lt "$n" ]; then
            [ "$VIEW_TOP" -le $(( n - h )) ] || bad_range=1
          else
            [ "$VIEW_TOP" -eq 0 ] || bad_range=1
          fi
        done
        idx=$((idx+1))
      done
    done
  done
  eq "viewport: cursor always visible ($count cases)" 0 "$bad_vis"
  eq "viewport: top always in range"                  0 "$bad_range"
}
vp_matrix

# Walking the whole list one step at a time must never jump the view around.
vp_walk() {
  local n=36 h=10 idx=0 top=0 prev=0 bad=0
  while [ "$idx" -lt "$n" ]; do
    tinct_viewport_top "$n" "$h" "$idx" "$top" 2
    top=$VIEW_TOP
    [ "$top" -lt "$prev" ] && bad=1          # never scrolls backwards going down
    [ $(( top - prev )) -le 1 ] || bad=1     # never jumps more than a row
    prev=$top
    idx=$((idx+1))
  done
  eq "viewport: walking down scrolls smoothly" 0 "$bad"
  eq "viewport: ends at the bottom"            $(( 36 - 10 )) "$top"
}
vp_walk

tinct_viewport_top 36 23 0 0 2;  eq "viewport: top of list"    0  "$VIEW_TOP"
tinct_viewport_top 36 23 35 0 2; eq "viewport: bottom of list" 13 "$VIEW_TOP"
tinct_viewport_top 5 23 4 0 2;   eq "viewport: list fits"      0  "$VIEW_TOP"
tinct_viewport_top 36 5 10 0 99; eq "viewport: absurd scrolloff clamps" 8 "$VIEW_TOP"

# --- scrollbar ---------------------------------------------------------------
sb_matrix() {
  local n h top row bad=0
  for n in 10 36 100; do
    for h in 3 10 23; do
      [ "$h" -ge "$n" ] && continue
      for top in 0 1 $(( n - h )); do
        row=0
        while [ "$row" -lt "$h" ]; do
          tinct_scroll_glyph "$n" "$h" "$top" "$row"
          case $GLYPH in '█'|'│') ;; *) bad=1 ;; esac
          row=$((row+1))
        done
      done
    done
  done
  eq "scrollbar: only ever draws track or thumb" 0 "$bad"
}
sb_matrix
tinct_scroll_glyph 36 23 0 0;  eq "scrollbar: thumb at top when scrolled up" '█' "$GLYPH"
tinct_scroll_glyph 36 23 13 22; eq "scrollbar: thumb at end when scrolled down" '█' "$GLYPH"
tinct_scroll_glyph 5 23 0 0;   eq "scrollbar: blank when everything fits" ' ' "$GLYPH"

# --- color math ------------------------------------------------------------
eq "hex2rgb 6 digit" "40 40 40"    "$(tinct_hex2rgb '#282828')"
eq "hex2rgb 3 digit" "255 255 255" "$(tinct_hex2rgb '#fff')"
eq "hex2rgb no hash" "204 36 29"   "$(tinct_hex2rgb 'CC241D')"
eq "hex2rgb garbage falls back" "128 128 128" "$(tinct_hex2rgb 'zzz~~~')"

roundtrip() {   # hex -> hsl -> hex must land back on itself
  local hex=$1 hsl h s l back
  hsl=$(tinct_hex2hsl "$hex")
  read -r h s l <<EOF
$hsl
EOF
  back=$(tinct_hsl2hex "$h" "$s" "$l")
  eq "hsl round trip $hex" "$hex" "$back"
}
roundtrip '#282828'
roundtrip '#EBDBB2'
roundtrip '#CC241D'
roundtrip '#98971A'
roundtrip '#458588'
roundtrip '#000000'
roundtrip '#FFFFFF'
roundtrip '#8EC07C'

eq "contrast black on white" "21.0" "$(tinct_contrast '#000000' '#FFFFFF')"
eq "contrast identical"      "1.0"  "$(tinct_contrast '#282828' '#282828')"
eq "contrast is symmetric"   "$(tinct_contrast '#EBDBB2' '#282828')" "$(tinct_contrast '#282828' '#EBDBB2')"

eq "norm_hex short"  "#AABBCC" "$(tinct_norm_hex 'abc')"
eq "norm_hex hashed" "#AABBCC" "$(tinct_norm_hex '#AaBbCc')"
tinct_norm_hex 'nothex' >/dev/null 2>&1 && ok "norm_hex rejects junk" 0 || ok "norm_hex rejects junk" 1
tinct_norm_hex '#12345' >/dev/null 2>&1 && ok "norm_hex rejects 5 digits" 0 || ok "norm_hex rejects 5 digits" 1

eq "slug strips spaces"  "my-theme"  "$(tinct_slug 'my theme')"
eq "slug strips slashes" "etcpasswd" "$(tinct_slug '/etc/passwd')"

# --- theme files -------------------------------------------------------------
cat > "$TINCT_THEME_DIR/probe.theme" <<'EOF'
# a comment
LABEL=Probe Theme
DESC=  spaces get trimmed

BG=#101010
FG = #F0F0F0
ANSI0=#000000
ANSI15=#FFFFFF
ANSI16=#BADBAD
NOTAKEY
EOF

tinct_load probe
eq "load: label"        "Probe Theme"          "$TH_LABEL"
eq "load: desc trimmed" "spaces get trimmed"   "$TH_DESC"
eq "load: bg"           "#101010"              "$TH_BG"
eq "load: spaces around ="  "#F0F0F0"          "$TH_FG"
eq "load: ansi0"        "#000000"              "${TH_ANSI[0]}"
eq "load: ansi15"       "#FFFFFF"              "${TH_ANSI[15]}"
eq "load: unset stays empty" ""                "${TH_ANSI[7]}"
eq "load: out of range ansi ignored" "16"      "${#TH_ANSI[@]}"
tinct_load nonexistent-theme 2>/dev/null && ok "load: missing theme fails" 0 || ok "load: missing theme fails" 1

# --- escape sequences --------------------------------------------------------
case $(tinct_seq) in *']11;#101010'*) ok "seq: sets bg via OSC 11" 1 ;;
                     *) ok "seq: sets bg via OSC 11" 0 ;; esac
case $(tinct_seq) in *']10;#F0F0F0'*) ok "seq: sets fg via OSC 10" 1 ;;
                     *) ok "seq: sets fg via OSC 10" 0 ;; esac
case $(tinct_seq) in *']104'*) ok "seq: clears the old palette first" 1 ;;
                     *) ok "seq: clears the old palette first" 0 ;; esac
case $(tinct_reset_seq) in *']110'*']111'*']112'*) ok "reset: restores fg/bg/cursor" 1 ;;
                           *) ok "reset: restores fg/bg/cursor" 0 ;; esac

# A theme with no palette block must not emit any OSC 4 entries.
cat > "$TINCT_THEME_DIR/bare.theme" <<'EOF'
LABEL=Bare
BG=#111111
EOF
tinct_load bare
case $(tinct_seq) in *']4;'*) ok "seq: no palette means no OSC 4" 0 ;;
                     *) ok "seq: no palette means no OSC 4" 1 ;; esac

# --- active theme ------------------------------------------------------------
tinct_set_active probe
eq "active: round trips" "probe" "$(tinct_active)"
tinct_set_active does-not-exist 2>/dev/null && ok "active: refuses unknown" 0 || ok "active: refuses unknown" 1
eq "active: unchanged after refusal" "probe" "$(tinct_active)"
printf 'ghost\n' > "$TINCT_ACTIVE_FILE"
eq "active: falls back when the file names a ghost" "bare" "$(tinct_active)"

# A user theme of the same name must shadow the bundled one.
printf 'LABEL=Bundled\nBG=#AAAAAA\n' > "$TINCT_BUNDLED_DIR/probe.theme"
printf 'LABEL=Mine\nBG=#BBBBBB\n'    > "$TINCT_THEME_DIR/probe.theme"
tinct_load probe
eq "themes: user copy shadows bundled" "Mine" "$TH_LABEL"
eq "themes: shadowed name listed once" "1" "$(tinct_list | grep -c '^probe$')"
printf 'LABEL=OnlyBundled\n' > "$TINCT_BUNDLED_DIR/bundled-only.theme"
tinct_load bundled-only
eq "themes: bundled-only still loads" "OnlyBundled" "$TH_LABEL"

# --- emitting to a target ----------------------------------------------------
cap=$TINCT_HOME/cap
TINCT_TTY=$cap
printf 'LABEL=Emit\nBG=#123456\n' > "$TINCT_THEME_DIR/emit.theme"
tinct_load emit
tinct_apply_live
case $(cat "$cap") in *'#123456'*) ok "emit: writes to TINCT_TTY" 1 ;;
                      *) ok "emit: writes to TINCT_TTY" 0 ;; esac
before=$(wc -c < "$cap")
tinct_apply_live
after=$(wc -c < "$cap")
[ "$after" -gt "$before" ] && ok "emit: appends rather than truncating" 1 || ok "emit: appends rather than truncating" 0
unset TINCT_TTY

# --- config ------------------------------------------------------------------
cat > "$TINCT_CONFIG_FILE" <<'EOF'
# comment
watch = psql, vim
scrolloff=4
EOF
tinct_read_config
eq "config: watch"     "psql, vim" "$TINCT_WATCH"
eq "config: scrolloff" "4"           "$TINCT_SCROLLOFF"

rm -rf "$TINCT_HOME"
printf '%s: %d passed, %d failed\n' "$SH" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
