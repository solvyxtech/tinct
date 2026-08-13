#!/bin/sh
# Symlink tintcoat onto PATH and create its config directory.
# Everything else -- themes, shell integration -- is opt-in.

set -e
ROOT=$(cd -- "$(dirname "$0")" && pwd -P)
BIN=${TINTCOAT_INSTALL_BIN:-$HOME/.local/bin}
HOME_DIR=${TINTCOAT_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/tintcoat}

if ! command -v zsh >/dev/null 2>&1; then
  ok=0
  for cand in bash /opt/homebrew/bin/bash /usr/local/bin/bash; do
    b=$(command -v "$cand" 2>/dev/null) || continue
    major=$("$b" -c 'echo ${BASH_VERSINFO[0]}' 2>/dev/null) || continue
    case $major in ''|*[!0-9]*) continue ;; esac
    [ "$major" -ge 4 ] && ok=1 && break
  done
  if [ "$ok" -eq 0 ]; then
    echo "tintcoat needs zsh or bash 4+. Install one first:" >&2
    echo "    brew install zsh" >&2
    exit 1
  fi
fi

mkdir -p "$BIN" "$HOME_DIR/themes"
ln -sf "$ROOT/bin/tintcoat" "$BIN/tintcoat"
echo "installed $BIN/tintcoat"
echo "config    $HOME_DIR"

case ":$PATH:" in
  *":$BIN:"*) ;;
  *) echo
     echo "$BIN is not on your PATH. Add this to your shell rc:"
     echo "    export PATH=\"$BIN:\$PATH\"" ;;
esac

echo
echo "Optional, for themed command wrappers:"
echo "    . $ROOT/shell/init.sh"
