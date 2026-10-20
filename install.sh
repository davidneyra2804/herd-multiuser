#!/bin/bash
# install.sh — instala el Herd compartido en este Mac.
#
#   ./install.sh          -> parte de usuario (sin sudo): scripts, runtime PHP, wrappers, launchd, skill
#   sudo ./install.sh --root -> parte de root: sudoers, /usr/local/bin, logs, firewall
#   ./install.sh --skill  -> instala sólo la skill de agente (sin tocar el resto)
#
# Es idempotente: se puede volver a ejecutar para sincronizar los scripts
# con los del repositorio (p.ej. tras un `git pull`).

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# si se ejecuta con sudo, el "dueño de Herd" es el usuario que lo invocó
if [ "$(id -u)" = "0" ] && [ -n "${SUDO_USER:-}" ]; then
  HERD_USER="$SUDO_USER"
else
  HERD_USER="$(id -un)"
fi
HERD_HOME="${HERD_HOME:-/Users/$HERD_USER/Library/Application Support/Herd}"

say()  { printf '  %s\n' "$1"; }
step() { printf '\n== %s\n' "$1"; }
die()  { printf 'error: %s\n' "$1" >&2; exit 1; }

# --------------------------------------------------------------- skill

# Instala la skill de agente (SKILL.md + references/) para que un LLM sepa
# usar herd-site. Se instala en los tres directorios que descubren los agentes
# habituales.
#
# Si el usuario ha EDITADO la skill a mano, no se pisa: se deja como está y se
# avisa. Para saberlo se guarda el hash de lo que se instaló en
# .source-hash; si el fichero instalado ya no casa con ese hash, es que lo
# editaron y se respeta su versión.
install_skill() {
  local src="$REPO_DIR/skills/herd-site"
  [ -d "$src" ] || return 0

  step "Skill de agente (herd-site)"
  local src_hash dst
  src_hash=$(cat "$src/SKILL.md" "$src"/references/*.md 2>/dev/null | shasum | cut -d' ' -f1)

  for dst in "$HOME/.config/opencode/skills/herd-site" \
             "$HOME/.claude/skills/herd-site" \
             "$HOME/.agents/skills/herd-site"; do
    mkdir -p "$dst" || continue
    # el hash guardado es del CONTENIDO INSTALADO: si ya no coincide con lo
    # que se instaló, el usuario lo editó a mano -> no se pisa
    if [ -f "$dst/SKILL.md" ] && [ -f "$dst/.source-hash" ]; then
      local now_hash
      now_hash=$(cat "$dst/SKILL.md" "$dst"/references/*.md 2>/dev/null | shasum | cut -d' ' -f1)
      if [ "$now_hash" != "$(cat "$dst/.source-hash")" ]; then
        say "$dst: editada a mano -> no se toca (bórrala para reinstalar)"
        continue
      fi
    fi
    cp -f "$src/SKILL.md" "$dst/SKILL.md"
    mkdir -p "$dst/references"
    cp -f "$src"/references/*.md "$dst/references/" 2>/dev/null
    printf '%s\n' "$src_hash" > "$dst/.source-hash"
    say "$dst"
  done
  say "con esto, un LLM sabe publicar y diagnosticar con 'herd-site'"
}

# --------------------------------------------------------------- parte root

# instalar sólo la skill, sin tocar el resto del stack
if [ "${1:-}" = "--skill" ]; then
  install_skill
  exit $?
fi

if [ "${1:-}" = "--root" ]; then
  [ "$(id -u)" = "0" ] || die "esta parte necesita sudo"
  command -v brew >/dev/null 2>&1 || die "no encuentro Homebrew"
  # brew puede no estar en el PATH de root
  BREW_PREFIX="$(sudo -u "$HERD_USER" -H brew --prefix 2>/dev/null || echo /opt/homebrew)"
  LIBEXEC="$BREW_PREFIX/libexec"
  [ -x "$LIBEXEC/herd-shared-setup" ] || die "no está instalado $LIBEXEC/herd-shared-setup (ejecuta antes ./install.sh)"
  su - "$HERD_USER" -c "HERD_USER='$HERD_USER' HERD_HOME='$HERD_HOME' '$LIBEXEC/herd-shared-setup' --root"
  exit $?
fi

# ---------------------------------------------------------- parte de usuario

step "Comprobaciones"
command -v brew >/dev/null 2>&1 || die "no encuentro Homebrew (instálalo primero: https://brew.sh)"
BREW_PREFIX="$(brew --prefix)"
BIN="$BREW_PREFIX/bin"
LIBEXEC="$BREW_PREFIX/libexec"
say "Homebrew:  $BREW_PREFIX"

[ -d "$HERD_HOME" ] || die "no encuentro Herd en $HERD_HOME (instala Herd: https://herd.laravel.com)"
say "Herd:      $HERD_HOME"
[ -x "$HERD_HOME/bin/herd" ] || die "Herd no está inicializado (abre la app de Herd una vez)"

step "Instalando scripts"
mkdir -p "$BIN" "$LIBEXEC"
install -m 755 "$REPO_DIR/bin/herd-site"        "$BIN/herd-site"
install -m 755 "$REPO_DIR/bin/herd-site-core"   "$LIBEXEC/herd-site-core"
install -m 755 "$REPO_DIR/bin/herd-shared-setup" "$LIBEXEC/herd-shared-setup"
say "$BIN/herd-site"
say "$LIBEXEC/herd-site-core"
say "$LIBEXEC/herd-shared-setup"

step "Runtime PHP compartido, wrappers y recarga automática"
HERD_USER="$HERD_USER" HERD_HOME="$HERD_HOME" "$LIBEXEC/herd-shared-setup" || die "falló la instalación"

step "Permisos de los sitios ya publicados"
# los sitios publicados por otros usuarios necesitan que el grupo staff pueda
# leer (y escribir en storage/) el proyecto
say "se aplican al publicar con 'herd-site link'"

install_skill

cat <<EOF

Listo. Falta un paso de root (una sola vez, lo hace el admin):

    sudo $LIBEXEC/herd-shared-setup --root

Después, cualquier usuario del Mac (grupo 'staff') podrá publicar con:

    herd-site link .
    herd-site links

EOF
