#!/bin/bash
# uninstall.sh — deja el Mac como estaba (opcionalmente, sin borrar los sitios).

set -uo pipefail

HERD_USER="$(id -un)"
HERD_HOME="$HOME/Library/Application Support/Herd"
BREW_PREFIX="$(command -v brew >/dev/null 2>&1 && brew --prefix || echo /opt/homebrew)"
BIN="$BREW_PREFIX/bin"
LIBEXEC="$BREW_PREFIX/libexec"

say()  { printf '  %s\n' "$1"; }
step() { printf '\n== %s\n' "$1"; }

KEEP_SITES="${1:-}"

step "Quitando los scripts"
for f in "$BIN/herd-site" "$LIBEXEC/herd-site-core" "$LIBEXEC/herd-shared-setup" \
         "$BIN/php74" "$BIN/php83" "$BIN/php84" "$BIN/php85" \
         "$BIN/composer74" "$BIN/composer83" "$BIN/composer84" "$BIN/composer85" \
         "$BIN/herd-composer" "$BIN/composer.phar" \
         "/usr/local/bin/herd-site" "/usr/local/bin/herd-composer"; do
  if [ -e "$f" ]; then rm -f "$f" && say "$(basename "$f")"; fi
done

step "Quitando la regla sudoers"
sudo -n rm -f /etc/sudoers.d/herd-site 2>/dev/null \
  && say "/etc/sudoers.d/herd-site" \
  || say "no se pudo quitar (házalo con: sudo rm -f /etc/sudoers.d/herd-site)"

step "Quitando el runtime compartido"
if [ "$KEEP_SITES" = "--keep-sites" ]; then
  rm -rf "$BREW_PREFIX/share/herd-shared/php" "$BREW_PREFIX/share/herd-shared/nginx-test"
  say "runtime PHP y certificados borrados (se han conservado los sitios)"
else
  rm -rf "$BREW_PREFIX/share/herd-shared"
  say "runtime compartido borrado"
fi

step "Quitando la recarga automática"
launchctl bootout "gui/$(id -u $HERD_USER)/com.herd.multiusuario.reload" 2>/dev/null
rm -f "$HOME/Library/LaunchAgents/com.herd.multiusuario.reload.plist"
say "LaunchAgent quitado"

if [ "$KEEP_SITES" != "--keep-sites" ]; then
  step "Quitando los sitios publicados"
  for v in "$HERD_HOME"/config/valet/Nginx/*.backend.test; do
    [ -e "$v" ] || continue
    name=$(basename "$v" | sed 's/\.backend\.test$//')
    rm -f "$HERD_HOME/config/valet/Sites/$name" "$v"
    say "$name.backend.test"
  done
fi

printf '\nHecho.\n'
