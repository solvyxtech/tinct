# tintcoat unit tests -- pure functions, no terminal required.
# Run via tests/run.sh, which executes this under both zsh and bash.

if [ -n "${ZSH_VERSION:-}" ]; then
  setopt ksh_arrays 2>/dev/null
  setopt no_nomatch 2>/dev/null
  SH=zsh
else
  SH=bash
fi

TINTCOAT_ROOT=${TINTCOAT_ROOT:-$(cd -- "$(dirname "$0")/.." && pwd -P)}
TINTCOAT_HOME=$(mktemp -d)
TINTCOAT_THEME_DIR=$TINTCOAT_HOME/themes
TINTCOAT_ACTIVE_FILE=$TINTCOAT_HOME/active
TINTCOAT_CONFIG_FILE=$TINTCOAT_HOME/config
# Hermetic: point the bundled dir at an empty directory so the repo's own
# themes cannot influence listing, fallback or shadowing assertions.
TINTCOAT_BUNDLED_DIR=$TINTCOAT_HOME/bundled
mkdir -p "$TINTCOAT_THEME_DIR" "$TINTCOAT_BUNDLED_DIR"

. "$TINTCOAT_ROOT/lib/core.sh"
. "$TINTCOAT_ROOT/lib/ui.sh"
. "$TINTCOAT_ROOT/lib/edit.sh"

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
          tintcoat_viewport_top "$n" "$h" "$idx" "$top" 2
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
    tintcoat_viewport_top "$n" "$h" "$idx" "$top" 2
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

tintcoat_viewport_top 36 23 0 0 2;  eq "viewport: top of list"    0  "$VIEW_TOP"
tintcoat_viewport_top 36 23 35 0 2; eq "viewport: bottom of list" 13 "$VIEW_TOP"
tintcoat_viewport_top 5 23 4 0 2;   eq "viewport: list fits"      0  "$VIEW_TOP"
tintcoat_viewport_top 36 5 10 0 99; eq "viewport: absurd scrolloff clamps" 8 "$VIEW_TOP"

# --- scrollbar ---------------------------------------------------------------
sb_matrix() {
  local n h top row bad=0
  for n in 10 36 100; do
    for h in 3 10 23; do
      [ "$h" -ge "$n" ] && continue
      for top in 0 1 $(( n - h )); do
        row=0
        while [ "$row" -lt "$h" ]; do
          tintcoat_scroll_glyph "$n" "$h" "$top" "$row"
          case $GLYPH in '█'|'│') ;; *) bad=1 ;; esac
          row=$((row+1))
        done
      done
    done
  done
  eq "scrollbar: only ever draws track or thumb" 0 "$bad"
}
sb_matrix
tintcoat_scroll_glyph 36 23 0 0;  eq "scrollbar: thumb at top when scrolled up" '█' "$GLYPH"
tintcoat_scroll_glyph 36 23 13 22; eq "scrollbar: thumb at end when scrolled down" '█' "$GLYPH"
tintcoat_scroll_glyph 5 23 0 0;   eq "scrollbar: blank when everything fits" ' ' "$GLYPH"

# --- color math ------------------------------------------------------------
eq "hex2rgb 6 digit" "40 40 40"    "$(tintcoat_hex2rgb '#282828')"
eq "hex2rgb 3 digit" "255 255 255" "$(tintcoat_hex2rgb '#fff')"
eq "hex2rgb no hash" "204 36 29"   "$(tintcoat_hex2rgb 'CC241D')"
eq "hex2rgb garbage falls back" "128 128 128" "$(tintcoat_hex2rgb 'zzz~~~')"

roundtrip() {   # hex -> hsl -> hex must land back on itself
  local hex=$1 hsl h s l back
  hsl=$(tintcoat_hex2hsl "$hex")
  read -r h s l <<EOF
$hsl
EOF
  back=$(tintcoat_hsl2hex "$h" "$s" "$l")
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

eq "contrast black on white" "21.0" "$(tintcoat_contrast '#000000' '#FFFFFF')"
eq "contrast identical"      "1.0"  "$(tintcoat_contrast '#282828' '#282828')"
eq "contrast is symmetric"   "$(tintcoat_contrast '#EBDBB2' '#282828')" "$(tintcoat_contrast '#282828' '#EBDBB2')"

eq "norm_hex short"  "#AABBCC" "$(tintcoat_norm_hex 'abc')"
eq "norm_hex hashed" "#AABBCC" "$(tintcoat_norm_hex '#AaBbCc')"
tintcoat_norm_hex 'nothex' >/dev/null 2>&1 && ok "norm_hex rejects junk" 0 || ok "norm_hex rejects junk" 1
tintcoat_norm_hex '#12345' >/dev/null 2>&1 && ok "norm_hex rejects 5 digits" 0 || ok "norm_hex rejects 5 digits" 1

eq "slug strips spaces"  "my-theme"  "$(tintcoat_slug 'my theme')"
eq "slug strips slashes" "etcpasswd" "$(tintcoat_slug '/etc/passwd')"

# --- theme files -------------------------------------------------------------
cat > "$TINTCOAT_THEME_DIR/probe.theme" <<'EOF'
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

tintcoat_load probe
eq "load: label"        "Probe Theme"          "$TH_LABEL"
eq "load: desc trimmed" "spaces get trimmed"   "$TH_DESC"
eq "load: bg"           "#101010"              "$TH_BG"
eq "load: spaces around ="  "#F0F0F0"          "$TH_FG"
eq "load: ansi0"        "#000000"              "${TH_ANSI[0]}"
eq "load: ansi15"       "#FFFFFF"              "${TH_ANSI[15]}"
eq "load: unset stays empty" ""                "${TH_ANSI[7]}"
eq "load: out of range ansi ignored" "16"      "${#TH_ANSI[@]}"
tintcoat_load nonexistent-theme 2>/dev/null && ok "load: missing theme fails" 0 || ok "load: missing theme fails" 1

# --- escape sequences --------------------------------------------------------
case $(tintcoat_seq) in *']11;#101010'*) ok "seq: sets bg via OSC 11" 1 ;;
                     *) ok "seq: sets bg via OSC 11" 0 ;; esac
case $(tintcoat_seq) in *']10;#F0F0F0'*) ok "seq: sets fg via OSC 10" 1 ;;
                     *) ok "seq: sets fg via OSC 10" 0 ;; esac
case $(tintcoat_seq) in *']104'*) ok "seq: clears the old palette first" 1 ;;
                     *) ok "seq: clears the old palette first" 0 ;; esac
case $(tintcoat_reset_seq) in *']110'*']111'*']112'*) ok "reset: restores fg/bg/cursor" 1 ;;
                           *) ok "reset: restores fg/bg/cursor" 0 ;; esac

# A theme with no palette block must not emit any OSC 4 entries.
cat > "$TINTCOAT_THEME_DIR/bare.theme" <<'EOF'
LABEL=Bare
BG=#111111
EOF
tintcoat_load bare
case $(tintcoat_seq) in *']4;'*) ok "seq: no palette means no OSC 4" 0 ;;
                     *) ok "seq: no palette means no OSC 4" 1 ;; esac

# --- default theme -----------------------------------------------------------
tintcoat_set_default probe
eq "default: round trips" "probe" "$(tintcoat_default)"
tintcoat_set_default does-not-exist 2>/dev/null && ok "default: refuses unknown" 0 || ok "default: refuses unknown" 1
eq "default: unchanged after refusal" "probe" "$(tintcoat_default)"
printf 'ghost\n' > "$TINTCOAT_HOME/default"
eq "default: falls back when the file names a ghost" "bare" "$(tintcoat_default)"
tintcoat_set_default probe

# an older install that only has the `active` file still works
rm -f "$TINTCOAT_HOME/default"
printf 'bare\n' > "$TINTCOAT_ACTIVE_FILE"
eq "default: reads a legacy active file" "bare" "$(tintcoat_default)"
tintcoat_set_default probe

# A user theme of the same name must shadow the bundled one.
printf 'LABEL=Bundled\nBG=#AAAAAA\n' > "$TINTCOAT_BUNDLED_DIR/probe.theme"
printf 'LABEL=Mine\nBG=#BBBBBB\n'    > "$TINTCOAT_THEME_DIR/probe.theme"
tintcoat_load probe
eq "themes: user copy shadows bundled" "Mine" "$TH_LABEL"
eq "themes: shadowed name listed once" "1" "$(tintcoat_list | grep -c '^probe$')"
printf 'LABEL=OnlyBundled\n' > "$TINTCOAT_BUNDLED_DIR/bundled-only.theme"
tintcoat_load bundled-only
eq "themes: bundled-only still loads" "OnlyBundled" "$TH_LABEL"

# --- emitting to a target ----------------------------------------------------
cap=$TINTCOAT_HOME/cap
TINTCOAT_TTY=$cap
printf 'LABEL=Emit\nBG=#123456\n' > "$TINTCOAT_THEME_DIR/emit.theme"
tintcoat_load emit
tintcoat_apply_live
case $(cat "$cap") in *'#123456'*) ok "emit: writes to TINTCOAT_TTY" 1 ;;
                      *) ok "emit: writes to TINTCOAT_TTY" 0 ;; esac
before=$(wc -c < "$cap")
tintcoat_apply_live
after=$(wc -c < "$cap")
[ "$after" -gt "$before" ] && ok "emit: appends rather than truncating" 1 || ok "emit: appends rather than truncating" 0
unset TINTCOAT_TTY

# --- config ------------------------------------------------------------------
cat > "$TINTCOAT_CONFIG_FILE" <<'EOF'
# comment
watch = psql, vim
scrolloff=4
EOF
tintcoat_read_config
eq "config: watch"     "psql, vim" "$TINTCOAT_WATCH"
eq "config: scrolloff" "4"           "$TINTCOAT_SCROLLOFF"



# --- per-terminal sessions ---------------------------------------------------
TINTCOAT_SESSION_DIR=$TINTCOAT_HOME/sessions
mkdir -p "$TINTCOAT_SESSION_DIR"
tintcoat_set_default probe

tintcoat_session_get ttys999 >/dev/null 2>&1 && ok "session: unknown terminal has none" 0 || ok "session: unknown terminal has none" 1
tintcoat_session_set ttys999 bare
eq "session: round trips"          "bare"  "$(tintcoat_session_get ttys999)"
tintcoat_session_set ttys999 nope 2>/dev/null && ok "session: refuses unknown theme" 0 || ok "session: refuses unknown theme" 1
eq "session: unchanged after refusal" "bare" "$(tintcoat_session_get ttys999)"

tintcoat_resolve ttys999
eq "resolve: a pinned terminal"    "bare"  "$RESOLVED"
eq "resolve: says it was pinned"   "pinned to this terminal" "$RESOLVED_BY"
tintcoat_resolve ttys998
eq "resolve: an unpinned terminal" "probe" "$RESOLVED"
case $RESOLVED_BY in default*) ok "resolve: says it was the default" 1 ;; *) ok "resolve: says it was the default" 0 ;; esac

tintcoat_session_clear ttys999
tintcoat_resolve ttys999
eq "resolve: after clearing"       "probe" "$RESOLVED"

# a record naming a theme that no longer exists must not win
printf 'deleted-theme\n' > "$TINTCOAT_SESSION_DIR/ttys997"
tintcoat_resolve ttys997
eq "resolve: ignores a stale theme name" "probe" "$RESOLVED"

# garbage collection drops terminals that are gone
tintcoat_session_set ttys996 bare
TINTCOAT_TTYS_CACHED=1 TINTCOAT_TTYS_CACHE="/dev/ttys995
"
tintcoat_session_gc
[ -e "$TINTCOAT_SESSION_DIR/ttys996" ] && ok "session: gc removes dead terminals" 0 || ok "session: gc removes dead terminals" 1
TINTCOAT_TTYS_CACHED=0 TINTCOAT_TTYS_CACHE=""

# --- rules -------------------------------------------------------------------
cat > "$TINTCOAT_RULES_FILE" <<'EOF'
# comment
dir  ~/work/prod   = bare
dir  ~/work        = probe
host prod-*        = bare
host *.internal    = probe
host exact-host    = bare
EOF

eq "rule: deeper dir wins by order"  "bare"  "$(tintcoat_rule_match dir "$HOME/work/prod/x")"
eq "rule: parent dir still matches"  "probe" "$(tintcoat_rule_match dir "$HOME/work/other")"
eq "rule: exact dir matches"         "probe" "$(tintcoat_rule_match dir "$HOME/work")"
tintcoat_rule_match dir /nowhere >/dev/null 2>&1 && ok "rule: unrelated dir does not match" 0 || ok "rule: unrelated dir does not match" 1
eq "rule: prefix glob host"          "bare"  "$(tintcoat_rule_match host prod-db1)"
eq "rule: suffix glob host"          "probe" "$(tintcoat_rule_match host box.internal)"
eq "rule: exact host"                "bare"  "$(tintcoat_rule_match host exact-host)"
tintcoat_rule_match host example.com >/dev/null 2>&1 && ok "rule: unrelated host does not match" 0 || ok "rule: unrelated host does not match" 1
# a dir pattern must not be consulted for a host lookup
tintcoat_rule_match host "$HOME/work" >/dev/null 2>&1 && ok "rule: kinds do not cross over" 0 || ok "rule: kinds do not cross over" 1

# --- glob matching is identical in both shells -------------------------------
tintcoat_glob_match prod-db1 'prod-*'    && ok "glob: prefix"        1 || ok "glob: prefix"        0
tintcoat_glob_match a.internal '*.internal' && ok "glob: suffix"     1 || ok "glob: suffix"        0
tintcoat_glob_match exact exact          && ok "glob: literal"       1 || ok "glob: literal"       0
tintcoat_glob_match nope 'prod-*'        && ok "glob: rejects"       0 || ok "glob: rejects"       1

# --- contrast memoization returns the same answer twice ----------------------
tintcoat_contrast_into '#000000' '#FFFFFF'
eq "contrast: ratio"        "21.0" "$CONTRAST"
eq "contrast: verdict"      "ok"   "$CONTRAST_LOW"
tintcoat_contrast_into '#000000' '#FFFFFF'
eq "contrast: memo agrees"  "21.0" "$CONTRAST"
tintcoat_contrast_into '#777777' '#808080'
eq "contrast: flags low"    "low"  "$CONTRAST_LOW"

# --- padding is exact --------------------------------------------------------
tintcoat_pad "abc" 6;  eq "pad: pads"      "abc   " "$PAD"
tintcoat_pad "abcdef" 3; eq "pad: truncates" "abc"  "$PAD"
tintcoat_pad "" 4;     eq "pad: empty"     "    "   "$PAD"
tintcoat_pad "abc" 0;  eq "pad: zero"      ""       "$PAD"


# --- color validation --------------------------------------------------------
tintcoat_is_hex '#AABBCC' && ok "hex: six digits"        1 || ok "hex: six digits"        0
tintcoat_is_hex '#abc'    && ok "hex: three digits"      1 || ok "hex: three digits"      0
tintcoat_is_hex 'AABBCC'  && ok "hex: needs a hash"      0 || ok "hex: needs a hash"      1
tintcoat_is_hex '#zzzzzz' && ok "hex: rejects non-hex"   0 || ok "hex: rejects non-hex"   1
tintcoat_is_hex '#12345'  && ok "hex: rejects five"      0 || ok "hex: rejects five"      1
tintcoat_is_hex ''        && ok "hex: rejects empty"     0 || ok "hex: rejects empty"     1
tintcoat_is_hex '#AABBCC extra' && ok "hex: rejects trailing junk" 0 || ok "hex: rejects trailing junk" 1

# A theme carrying junk loses that one color rather than forwarding it.
cat > "$TINTCOAT_THEME_DIR/junk.theme" <<'EOF'
LABEL=Junk
DESC=one good color and several bad ones
BG=#101010
FG=notacolor
CURSOR=#zzz
ANSI0=#00FF00
ANSI1=rgb(1,2,3)
EOF
tintcoat_load junk
eq "load: keeps the valid color"      "#101010" "$TH_BG"
eq "load: drops an invalid fg"        ""        "$TH_FG"
eq "load: drops an invalid cursor"    ""        "$TH_CURSOR"
eq "load: keeps a valid palette entry" "#00FF00" "${TH_ANSI[0]}"
eq "load: drops an invalid palette entry" ""     "${TH_ANSI[1]}"
case $(tintcoat_seq) in *notacolor*|*rgb\(*) ok "seq: never forwards junk to the terminal" 0 ;;
                     *) ok "seq: never forwards junk to the terminal" 1 ;; esac

# A directory that looks like a theme must not be read as one.
mkdir -p "$TINTCOAT_THEME_DIR/adir.theme"
tintcoat_load adir 2>/dev/null && ok "load: refuses a directory" 0 || ok "load: refuses a directory" 1
eq "list: skips a directory" "0" "$(tintcoat_list | grep -c '^adir$')"

# --- atomic state writes -----------------------------------------------------
tintcoat_write_atomic "$TINTCOAT_HOME/atomic-probe" "hello"
eq "atomic: writes the value" "hello" "$(cat "$TINTCOAT_HOME/atomic-probe")"
tintcoat_write_atomic "$TINTCOAT_HOME/atomic-probe" "second"
eq "atomic: overwrites cleanly" "second" "$(cat "$TINTCOAT_HOME/atomic-probe")"
eq "atomic: leaves no temp files" "0" "$(find "$TINTCOAT_HOME" -maxdepth 1 -name 'atomic-probe.*' | grep -c .)"
tintcoat_write_atomic "/nonexistent-root-dir-xyz/nope" "x" 2>/dev/null && ok "atomic: fails on an unwritable path" 0 || ok "atomic: fails on an unwritable path" 1

# --- terminal names containing a slash (Linux calls them pts/0) --------------
tintcoat_tty_key_into "pts/0";   eq "tty key: flattens a slash"   "pts-0"   "$TTYKEY"
tintcoat_tty_key_into "ttys009"; eq "tty key: leaves macOS alone" "ttys009" "$TTYKEY"
tintcoat_tty_key_into "pts/12";  eq "tty key: two digits"         "pts-12"  "$TTYKEY"

tintcoat_session_set "pts/3" bare
eq "session: a slashed name round trips" "bare" "$(tintcoat_session_get 'pts/3')"
[ -f "$TINTCOAT_SESSION_DIR/pts-3" ] && ok "session: stored as one flat file" 1 || ok "session: stored as one flat file" 0
[ -d "$TINTCOAT_SESSION_DIR/pts" ] && ok "session: no nested directory created" 0 || ok "session: no nested directory created" 1
tintcoat_resolve "pts/3"
eq "resolve: a slashed terminal" "bare" "$RESOLVED"
tintcoat_session_clear "pts/3"
tintcoat_session_get "pts/3" >/dev/null 2>&1 && ok "session: slashed clear works" 0 || ok "session: slashed clear works" 1

# gc has to match live terminals through the same flattening, or Linux records
# would never be recognised and would pile up forever.
tintcoat_session_set "pts/7" bare
tintcoat_session_set "pts/8" bare
TINTCOAT_TTYS_CACHED=1 TINTCOAT_TTYS_CACHE="/dev/pts/7
"
tintcoat_session_gc
[ -f "$TINTCOAT_SESSION_DIR/pts-7" ] && ok "gc: keeps a live slashed terminal" 1 || ok "gc: keeps a live slashed terminal" 0
[ -f "$TINTCOAT_SESSION_DIR/pts-8" ] && ok "gc: drops a dead slashed terminal" 0 || ok "gc: drops a dead slashed terminal" 1
TINTCOAT_TTYS_CACHED=0 TINTCOAT_TTYS_CACHE=""
tintcoat_session_clear "pts/7"

rm -rf "$TINTCOAT_HOME"
printf '%s: %d passed, %d failed\n' "$SH" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
