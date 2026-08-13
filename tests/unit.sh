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

# --- default theme -----------------------------------------------------------
tinct_set_default probe
eq "default: round trips" "probe" "$(tinct_default)"
tinct_set_default does-not-exist 2>/dev/null && ok "default: refuses unknown" 0 || ok "default: refuses unknown" 1
eq "default: unchanged after refusal" "probe" "$(tinct_default)"
printf 'ghost\n' > "$TINCT_HOME/default"
eq "default: falls back when the file names a ghost" "bare" "$(tinct_default)"
tinct_set_default probe

# an older install that only has the `active` file still works
rm -f "$TINCT_HOME/default"
printf 'bare\n' > "$TINCT_ACTIVE_FILE"
eq "default: reads a legacy active file" "bare" "$(tinct_default)"
tinct_set_default probe

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



# --- per-terminal sessions ---------------------------------------------------
TINCT_SESSION_DIR=$TINCT_HOME/sessions
mkdir -p "$TINCT_SESSION_DIR"
tinct_set_default probe

tinct_session_get ttys999 >/dev/null 2>&1 && ok "session: unknown terminal has none" 0 || ok "session: unknown terminal has none" 1
tinct_session_set ttys999 bare
eq "session: round trips"          "bare"  "$(tinct_session_get ttys999)"
tinct_session_set ttys999 nope 2>/dev/null && ok "session: refuses unknown theme" 0 || ok "session: refuses unknown theme" 1
eq "session: unchanged after refusal" "bare" "$(tinct_session_get ttys999)"

tinct_resolve ttys999
eq "resolve: a pinned terminal"    "bare"  "$RESOLVED"
eq "resolve: says it was pinned"   "pinned to this terminal" "$RESOLVED_BY"
tinct_resolve ttys998
eq "resolve: an unpinned terminal" "probe" "$RESOLVED"
case $RESOLVED_BY in default*) ok "resolve: says it was the default" 1 ;; *) ok "resolve: says it was the default" 0 ;; esac

tinct_session_clear ttys999
tinct_resolve ttys999
eq "resolve: after clearing"       "probe" "$RESOLVED"

# a record naming a theme that no longer exists must not win
printf 'deleted-theme\n' > "$TINCT_SESSION_DIR/ttys997"
tinct_resolve ttys997
eq "resolve: ignores a stale theme name" "probe" "$RESOLVED"

# garbage collection drops terminals that are gone
tinct_session_set ttys996 bare
TINCT_TTYS_CACHED=1 TINCT_TTYS_CACHE="/dev/ttys995
"
tinct_session_gc
[ -e "$TINCT_SESSION_DIR/ttys996" ] && ok "session: gc removes dead terminals" 0 || ok "session: gc removes dead terminals" 1
TINCT_TTYS_CACHED=0 TINCT_TTYS_CACHE=""

# --- rules -------------------------------------------------------------------
cat > "$TINCT_RULES_FILE" <<'EOF'
# comment
dir  ~/work/prod   = bare
dir  ~/work        = probe
host prod-*        = bare
host *.internal    = probe
host exact-host    = bare
EOF

eq "rule: deeper dir wins by order"  "bare"  "$(tinct_rule_match dir "$HOME/work/prod/x")"
eq "rule: parent dir still matches"  "probe" "$(tinct_rule_match dir "$HOME/work/other")"
eq "rule: exact dir matches"         "probe" "$(tinct_rule_match dir "$HOME/work")"
tinct_rule_match dir /nowhere >/dev/null 2>&1 && ok "rule: unrelated dir does not match" 0 || ok "rule: unrelated dir does not match" 1
eq "rule: prefix glob host"          "bare"  "$(tinct_rule_match host prod-db1)"
eq "rule: suffix glob host"          "probe" "$(tinct_rule_match host box.internal)"
eq "rule: exact host"                "bare"  "$(tinct_rule_match host exact-host)"
tinct_rule_match host example.com >/dev/null 2>&1 && ok "rule: unrelated host does not match" 0 || ok "rule: unrelated host does not match" 1
# a dir pattern must not be consulted for a host lookup
tinct_rule_match host "$HOME/work" >/dev/null 2>&1 && ok "rule: kinds do not cross over" 0 || ok "rule: kinds do not cross over" 1

# --- glob matching is identical in both shells -------------------------------
tinct_glob_match prod-db1 'prod-*'    && ok "glob: prefix"        1 || ok "glob: prefix"        0
tinct_glob_match a.internal '*.internal' && ok "glob: suffix"     1 || ok "glob: suffix"        0
tinct_glob_match exact exact          && ok "glob: literal"       1 || ok "glob: literal"       0
tinct_glob_match nope 'prod-*'        && ok "glob: rejects"       0 || ok "glob: rejects"       1

# --- contrast memoization returns the same answer twice ----------------------
tinct_contrast_into '#000000' '#FFFFFF'
eq "contrast: ratio"        "21.0" "$CONTRAST"
eq "contrast: verdict"      "ok"   "$CONTRAST_LOW"
tinct_contrast_into '#000000' '#FFFFFF'
eq "contrast: memo agrees"  "21.0" "$CONTRAST"
tinct_contrast_into '#777777' '#808080'
eq "contrast: flags low"    "low"  "$CONTRAST_LOW"

# --- padding is exact --------------------------------------------------------
tinct_pad "abc" 6;  eq "pad: pads"      "abc   " "$PAD"
tinct_pad "abcdef" 3; eq "pad: truncates" "abc"  "$PAD"
tinct_pad "" 4;     eq "pad: empty"     "    "   "$PAD"
tinct_pad "abc" 0;  eq "pad: zero"      ""       "$PAD"


# --- color validation --------------------------------------------------------
tinct_is_hex '#AABBCC' && ok "hex: six digits"        1 || ok "hex: six digits"        0
tinct_is_hex '#abc'    && ok "hex: three digits"      1 || ok "hex: three digits"      0
tinct_is_hex 'AABBCC'  && ok "hex: needs a hash"      0 || ok "hex: needs a hash"      1
tinct_is_hex '#zzzzzz' && ok "hex: rejects non-hex"   0 || ok "hex: rejects non-hex"   1
tinct_is_hex '#12345'  && ok "hex: rejects five"      0 || ok "hex: rejects five"      1
tinct_is_hex ''        && ok "hex: rejects empty"     0 || ok "hex: rejects empty"     1
tinct_is_hex '#AABBCC extra' && ok "hex: rejects trailing junk" 0 || ok "hex: rejects trailing junk" 1

# A theme carrying junk loses that one color rather than forwarding it.
cat > "$TINCT_THEME_DIR/junk.theme" <<'EOF'
LABEL=Junk
DESC=one good color and several bad ones
BG=#101010
FG=notacolor
CURSOR=#zzz
ANSI0=#00FF00
ANSI1=rgb(1,2,3)
EOF
tinct_load junk
eq "load: keeps the valid color"      "#101010" "$TH_BG"
eq "load: drops an invalid fg"        ""        "$TH_FG"
eq "load: drops an invalid cursor"    ""        "$TH_CURSOR"
eq "load: keeps a valid palette entry" "#00FF00" "${TH_ANSI[0]}"
eq "load: drops an invalid palette entry" ""     "${TH_ANSI[1]}"
case $(tinct_seq) in *notacolor*|*rgb\(*) ok "seq: never forwards junk to the terminal" 0 ;;
                     *) ok "seq: never forwards junk to the terminal" 1 ;; esac

# A directory that looks like a theme must not be read as one.
mkdir -p "$TINCT_THEME_DIR/adir.theme"
tinct_load adir 2>/dev/null && ok "load: refuses a directory" 0 || ok "load: refuses a directory" 1
eq "list: skips a directory" "0" "$(tinct_list | grep -c '^adir$')"

# --- atomic state writes -----------------------------------------------------
tinct_write_atomic "$TINCT_HOME/atomic-probe" "hello"
eq "atomic: writes the value" "hello" "$(cat "$TINCT_HOME/atomic-probe")"
tinct_write_atomic "$TINCT_HOME/atomic-probe" "second"
eq "atomic: overwrites cleanly" "second" "$(cat "$TINCT_HOME/atomic-probe")"
eq "atomic: leaves no temp files" "0" "$(find "$TINCT_HOME" -maxdepth 1 -name 'atomic-probe.*' | grep -c .)"
tinct_write_atomic "/nonexistent-root-dir-xyz/nope" "x" 2>/dev/null && ok "atomic: fails on an unwritable path" 0 || ok "atomic: fails on an unwritable path" 1

# --- terminal names containing a slash (Linux calls them pts/0) --------------
tinct_tty_key_into "pts/0";   eq "tty key: flattens a slash"   "pts-0"   "$TTYKEY"
tinct_tty_key_into "ttys009"; eq "tty key: leaves macOS alone" "ttys009" "$TTYKEY"
tinct_tty_key_into "pts/12";  eq "tty key: two digits"         "pts-12"  "$TTYKEY"

tinct_session_set "pts/3" bare
eq "session: a slashed name round trips" "bare" "$(tinct_session_get 'pts/3')"
[ -f "$TINCT_SESSION_DIR/pts-3" ] && ok "session: stored as one flat file" 1 || ok "session: stored as one flat file" 0
[ -d "$TINCT_SESSION_DIR/pts" ] && ok "session: no nested directory created" 0 || ok "session: no nested directory created" 1
tinct_resolve "pts/3"
eq "resolve: a slashed terminal" "bare" "$RESOLVED"
tinct_session_clear "pts/3"
tinct_session_get "pts/3" >/dev/null 2>&1 && ok "session: slashed clear works" 0 || ok "session: slashed clear works" 1

# gc has to match live terminals through the same flattening, or Linux records
# would never be recognised and would pile up forever.
tinct_session_set "pts/7" bare
tinct_session_set "pts/8" bare
TINCT_TTYS_CACHED=1 TINCT_TTYS_CACHE="/dev/pts/7
"
tinct_session_gc
[ -f "$TINCT_SESSION_DIR/pts-7" ] && ok "gc: keeps a live slashed terminal" 1 || ok "gc: keeps a live slashed terminal" 0
[ -f "$TINCT_SESSION_DIR/pts-8" ] && ok "gc: drops a dead slashed terminal" 0 || ok "gc: drops a dead slashed terminal" 1
TINCT_TTYS_CACHED=0 TINCT_TTYS_CACHE=""
tinct_session_clear "pts/7"

rm -rf "$TINCT_HOME"
printf '%s: %d passed, %d failed\n' "$SH" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
