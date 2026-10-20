#!/bin/bash
# publish.sh — publica este repo en tu cuenta de GitHub.
#
#   ./publish.sh [cuenta] [--public]
#
# Por defecto crea el repositorio en privado; con --public, público.
# Necesitas haber hecho `gh auth login` con esa cuenta antes.
# El push se hace con la clave SSH de la cuenta (alias en ~/.ssh/config).

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VISIBILITY="private"
ACCOUNT=""
for a in "$@"; do
  case "$a" in
    --public) VISIBILITY="public" ;;
    --private) VISIBILITY="private" ;;
    *) ACCOUNT="$a" ;;
  esac
done
[ -n "$ACCOUNT" ] || ACCOUNT="$(gh api user -q .login 2>/dev/null)"
NAME="$(basename "$REPO_DIR")"
KEY_ALIAS="github-personal"

say()  { printf '  %s\n' "$1"; }
step() { printf '\n== %s\n' "$1"; }
die()  { printf 'error: %s\n' "$1" >&2; exit 1; }

command -v gh >/dev/null 2>&1 || die "no encuentro gh (instálalo: brew install gh)"

step "Cuenta"
ACTIVE="$(gh api user -q .login 2>/dev/null)" || die "gh no está autenticado: ejecuta 'gh auth login'"
say "activa:  $ACTIVE"
[ -n "$ACCOUNT" ] && say "destino: $ACCOUNT"
[ "$ACTIVE" != "$ACCOUNT" ] && die "la cuenta activa de gh es '$ACTIVE', no '$ACCOUNT'.
  → haz 'gh auth switch --user $ACCOUNT' o ejecuta './publish.sh $ACTIVE'"

step "Repositorio"
if gh repo view "$ACCOUNT/$NAME" >/dev/null 2>&1; then
  say "$ACCOUNT/$NAME ya existe"
else
  gh repo create "$ACCOUNT/$NAME" --"$VISIBILITY" --source=. --remote=origin --push \
    --description "Herd compartido multiusuario para macOS: un solo Herd (nginx + php-fpm) que todos los usuarios del Mac pueden usar para publicar sus proyectos" \
    && say "creado $ACCOUNT/$NAME ($VISIBILITY)" \
    || die "no se pudo crear el repositorio"
fi

step "Remoto y push"
if ssh -T -o BatchMode=yes "$KEY_ALIAS" 2>&1 | grep -q "$ACCOUNT"; then
  git remote set-url origin "git@$KEY_ALIAS:$ACCOUNT/$NAME.git"
  say "origin -> git@$KEY_ALIAS:$ACCOUNT/$NAME.git"
else
  say "AVISO: la clave SSH de $KEY_ALIAS no corresponde a $ACCOUNT; uso el remoto actual"
fi
git push -u origin HEAD 2>&1 | tail -3

printf '\nListo: https://github.com/%s/%s\n' "$ACCOUNT" "$NAME"
