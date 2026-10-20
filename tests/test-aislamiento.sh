#!/bin/bash
# test-aislamiento.sh — comprueba que los usuarios del Mac no pueden ver ni
# tocar los sitios de los demás.
#
# El núcleo (herd-site-core) se ejecuta normalmente como root vía sudo, y
# toma la identidad de quien pregunta de $SUDO_USER. Para probarlo sin la
# contraseña de otro usuario, este test coloca un shim de `id` delante en el
# PATH: `id -u` responde 0 (como root) y `id -un` responde con el usuario
# simulado. El código real se ejecuta sin modificar.
#
#   ./tests/test-aislamiento.sh
#
# Sale con 0 si todo correcto, 1 si algún fallo.

set -u

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE="$REPO_DIR/bin/herd-site-core"
CLI="$REPO_DIR/bin/herd-site"
SHARED="${SHARED:-/opt/homebrew/share/herd-shared}"
MANIFEST="$SHARED/sites.tsv"
FAKE_USER="${FAKE_USER:-vyrtech}"
HERD_OWNER="${HERD_OWNER:-agentmaster}"
PASS=0
FAIL=0

ok()  { printf '  [OK]    %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  [FALLO] %s\n' "$1"; FAIL=$((FAIL+1)); }

# --- shim de `id` ------------------------------------------------------
# `id -u`   -> 0            (como root, vía sudo)
# `id -un`  -> usuario simulado
# `id -u X` -> uid real de X
SHIM_DIR="$(mktemp -d)"
trap 'rm -rf "$SHIM_DIR"' EXIT
cat > "$SHIM_DIR/id" <<EOF
#!/bin/bash
case "\$1" in
  -u)   shift; [ -n "\$1" ] && /usr/bin/id -u "\$1" || echo 0 ;;
  -un)  echo "$FAKE_USER" ;;
  -nu)  echo "$FAKE_USER" ;;
  *)    exec /usr/bin/id "\$@" ;;
esac
EOF
chmod +x "$SHIM_DIR/id"

# Ejecuta el núcleo como lo haría 'herd-site' al ser invocado por otro
# usuario: root vía sudo, con SUDO_USER = el usuario simulado.
sim() {
  PATH="$SHIM_DIR:$PATH" \
  SUDO_USER="$FAKE_USER" SUDO_UID=503 \
  HERD_USER="$HERD_OWNER" \
  HERD_HOME="${HERD_HOME:-/Users/$HERD_OWNER/Library/Application Support/Herd}" \
  SHARED="$SHARED" MANIFEST="$MANIFEST" TLD="${TLD:-backend.test}" GROUP=staff \
  bash "$CORE" "$@" 2>&1
}

# Ejecuta el CLI como el usuario simulado (id -un dice el simulado).
sim_cli() {
  PATH="$SHIM_DIR:$PATH" \
  SUDO_USER="$FAKE_USER" SUDO_UID=503 \
  HERD_USER="$HERD_OWNER" \
  HERD_HOME="${HERD_HOME:-/Users/$HERD_OWNER/Library/Application Support/Herd}" \
  SHARED="$SHARED" MANIFEST="$MANIFEST" TLD="${TLD:-backend.test}" GROUP=staff \
  bash "$CLI" "$@" 2>&1
}

echo "== 0. preparación =="
if [ ! -f "$MANIFEST" ]; then
  bad "no hay manifiesto ($MANIFEST): la prueba no es válida"
  exit 1
fi
OTHER_NAME=$(awk -F'\t' 'NR==1{print $1}' "$MANIFEST")
OTHER_PATH=$(awk -F'\t' 'NR==1{print $2}' "$MANIFEST")
OTHER_OWNER=$(awk -F'\t' 'NR==1{print $5}' "$MANIFEST")
if [ -z "$OTHER_NAME" ]; then
  bad "el manifiesto está vacío: la prueba no es válida"
  exit 1
fi
ok "sitio de prueba: $OTHER_NAME (dueño: $OTHER_OWNER)"

echo
echo "== 1. unlink del sitio de otro: debe rechazarse =="
out=$(sim unlink --name "$OTHER_NAME")
if printf '%s' "$out" | grep -qi "no es tuyo"; then
  ok "rechazado: $(printf '%s' "$out" | head -1)"
else
  bad "NO se rechazó. Salida: $out"
fi
if grep -q "^$OTHER_NAME" "$MANIFEST"; then
  ok "el sitio ajeno sigue en el manifiesto"
else
  bad "¡el sitio ajeno fue BORRADO!"
fi

echo
echo "== 2. link sobre el nombre de otro: debe rechazarse =="
# OJO: la ruta debe estar permitida por la política del núcleo (fuera de
# /tmp y /var/folders, que están bloqueados a propósito).
PROJ_DIR="$HOME/herd-iso-test-proj"
rm -rf "$PROJ_DIR"
mkdir -p "$PROJ_DIR"
out=$(sim link --path "$PROJ_DIR" --name "$OTHER_NAME" --php 7.4)
if printf '%s' "$out" | grep -qi "ya existe y es de\|no es tuyo"; then
  ok "rechazado: $(printf '%s' "$out" | head -1)"
else
  bad "NO se rechazó. Salida: $out"
fi
if awk -F'\t' -v n="$OTHER_NAME" '$1==n{print $2}' "$MANIFEST" | grep -q "$OTHER_PATH"; then
  ok "el manifiesto sigue apuntando a la ruta original"
else
  bad "¡el manifiesto fue alterado!"
fi

echo
echo "== 3. doctor de un no-admin: no debe listar sitios ajenos =="
out=$(sim doctor)
if printf '%s' "$out" | grep -q "$OTHER_NAME"; then
  bad "el doctor del usuario simulado muestra el sitio ajeno"
else
  ok "el doctor del usuario simulado no muestra sitios ajenos"
fi

echo
echo "== 4. el CLI filtra 'links' y 'list' para un no-admin =="
out=$(sim_cli links)
if printf '%s' "$out" | grep -q "$OTHER_NAME"; then
  bad "'links' de un no-admin muestra sitios ajenos"
else
  ok "'links' de un no-admin no muestra sitios ajenos"
fi
out=$(sim_cli list)
if printf '%s' "$out" | grep -q "$OTHER_NAME"; then
  bad "'list' de un no-admin muestra sitios ajenos"
else
  ok "'list' de un no-admin no muestra sitios ajenos"
fi

echo
echo "== 5. el CLI rechaza '--all' a un no-admin =="
out=$(sim_cli links --all)
if printf '%s' "$out" | grep -qi "administrador"; then
  ok "rechazado: $(printf '%s' "$out" | head -1)"
else
  bad "NO se rechazó. Salida: $out"
fi

echo
echo "== 6. el admin conserva la visión global =="
out=$(bash "$CLI" links --all 2>&1)
if printf '%s' "$out" | grep -q "$OTHER_NAME"; then
  ok "el admin ve todos los sitios con --all"
else
  bad "el admin NO ve los sitios con --all (regresión)"
fi
out=$(bash "$CLI" doctor 2>&1)
if printf '%s' "$out" | grep -q "$OTHER_NAME"; then
  ok "el admin ve todos los sitios en el doctor"
else
  bad "el admin NO ve los sitios en el doctor (regresión)"
fi

echo
echo "== 7. el admin puede reparar el sitio de otro (y atribuirlo bien) =="
# el admin republica el sitio del otro con --owner: debe funcionar y el
# sitio debe seguir siendo del otro usuario.
out=$(bash "$CLI" link "$OTHER_PATH" --name "$OTHER_NAME" --owner "$OTHER_OWNER" --force 2>&1)
if printf '%s' "$out" | grep -q "^OK $OTHER_NAME"; then
  ok "el admin puede republicar el sitio de otro"
else
  bad "el admin NO pudo republicar el sitio de otro. Salida: $out"
fi
if awk -F'\t' -v n="$OTHER_NAME" '$1==n{print $5}' "$MANIFEST" | grep -q "$OTHER_OWNER"; then
  ok "el sitio sigue atribuido a $OTHER_OWNER"
else
  bad "el sitio cambió de dueño (quedó como $(awk -F'\t' -v n="$OTHER_NAME" '$1==n{print $5}' "$MANIFEST"))"
fi
# y un usuario normal NO puede hacer lo mismo
out=$(sim link --path "$PROJ_DIR" --name "$OTHER_NAME" --owner "$OTHER_OWNER" --php 7.4)
if printf '%s' "$out" | grep -qi "no es tuyo\|ya existe y es de\|sólo el dueño"; then
  ok "un no-admin no puede atribuir el sitio a otro: $(printf '%s' "$out" | head -1)"
else
  bad "un no-admin SÍ pudo atribuir el sitio. Salida: $out"
fi

echo
echo "== RESULTADO: $PASS correctos, $FAIL fallos =="
rm -rf "$PROJ_DIR"
[ "$FAIL" = "0" ]
