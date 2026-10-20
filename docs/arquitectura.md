# Arquitectura

Cómo está montado el Herd compartido, por qué está montado así, y los
problemas que hubo que resolver (que son los que volverían a aparecer).

## Las piezas de Herd (y por qué se pueden compartir)

| Pieza | Dónde | Nota |
|---|---|---|
| nginx | `/Applications/Herd.app/Contents/Resources/nginx-arm64` | el **master** corre como root vía el helper privilegiado `de.beyondco.herd.helper`; los workers como el usuario dueño de Herd (`user "el-owner" staff;`) |
| php-fpm | `$HERD_HOME/config/fpm/<ver>-fpm.conf` | un pool por versión, `user=dueño`, `group=staff`, socket `$HERD_HOME/herd<ver>.sock`, `listen.mode=0777` |
| DNS | dnsmasq + `/etc/resolver/test` | `address=/.test/127.0.0.1` → `*.<tld>` ya resolvía a 127.0.0.1 **para todo el Mac** |
| registro de sitios | `$HERD_HOME/config/valet/Sites/<nombre>` | symlink al directorio del proyecto |
| vhosts | `$HERD_HOME/config/valet/Nginx/<nombre>.<tld>` | el `nginx.conf` hace `include ".../config/valet/Nginx/*"` → cualquier fichero de ahí es un vhost |
| plantilla de vhost | `valet/cli/stubs/site.valet.conf` | el núcleo la replica |
| CA de TLS | `$HERD_HOME/config/valet/CA/` | "Laravel Valet CA", **ya está en el keychain del Sistema** → la confían todos los usuarios |

Lo que **no** se comparte (y es lo que había que resolver): el CLI, los
binarios de PHP y el `php.ini` viven en `~/Library/Application Support/Herd`, y
`~/Library` es `drwx------` en macOS → ningún otro usuario puede ejecutarlos.

## Lo que hace este proyecto

1. **Runtime PHP compartido**: copia los binarios de PHP de Herd a
   `$PREFIX/share/herd-shared/php/<ver>/` (legibles por todos) y genera
   `php74`, `php83`… en `$PREFIX/bin`.
2. **CLI `herd-site`**: valida la petición en el usuario y llama al núcleo
   privilegiado.
3. **Núcleo `herd-site-core`**: crea el symlink del sitio, escribe el vhost,
   aplica los permisos de grupo y recarga nginx.
4. **Recarga automática**: un LaunchAgent (`StartInterval 10`) que compara la
   marca de tiempo del directorio de vhosts y recarga nginx si ha cambiado.

## Modelo de permisos

- nginx y php-fpm corren como `<dueño>:staff` → **todo** proyecto publicado
  debe ser legible por el grupo `staff`.
- `herd-site` deja el proyecto en grupo `staff`, con `g+rX` en el árbol y
  `g+rwX` en `storage/`, `bootstrap/cache/`, `public/build/`, `var/logs/`.
- `$HERD_HOME/config/valet/Sites/` y `.../Nginx/` **no** son group-writable:
  sólo escribe el núcleo. Si lo fueran, cualquier usuario del grupo `staff`
  podría inyectar un vhost que expusiera ficheros privados de otro (los
  workers de nginx leen como el dueño de Herd).

## Modelo de seguridad del núcleo

- Exige `SUDO_USER`/`SUDO_UID` (o que el ejecutor sea el dueño de Herd) →
  sabe siempre quién pregunta.
- Bloquea publicar desde `/System`, `/usr`, `/bin`, `/etc`, `/var`, `/opt`,
  `/private/etc`, `/Applications`, `/Library`, `/Volumes/{Preboot,Recovery,…}`
  y cualquier ruta con `.ssh`, `.gnupg`, `.aws`, `.kube`, `.config`,
  `Keychains`, `Mail`…
- Sólo se puede publicar sobre rutas en las que el usuario que pregunta tiene
  permiso de escritura (o que están bajo su home). El dueño de Herd sí puede
  sobre rutas de otros: es quien repara el stack.
- **Propiedad de los sitios**: cada sitio pertenece a quien lo publicó (columna
  `dueño` del manifiesto). El núcleo rechaza `unlink` de un sitio ajeno y
  publicar sobre el nombre de otro. Sólo el dueño de Herd puede saltarse esa
  comprobación (para reparar), y entonces puede atribuir el sitio a su
  propietario real con `--owner`.
- El nombre del sitio se valida: `^[a-z0-9-]{1,48}$`.
- La regla sudoers es mínima: `%staff ALL=(root) NOPASSWD: <núcleo>` → el
  núcleo sólo sabe hacer cuatro cosas (vincular, desvincular, recargar,
 auditar).

## Aislamiento entre usuarios

Es el objetivo del proyecto, y se aplica en tres capas:

1. **Visibilidad** (en el CLI): `links` y `list` filtran por propietario;
   `doctor` y `reapply` sólo tocan los sitios del usuario que pregunta. La
   visión global (`links --all`) es sólo del dueño de Herd.
2. **Propiedad** (en el núcleo): cada operación comprueba a quién pertenece el
   sitio. Un usuario no puede despublicar el sitio de otro ni publicar sobre su
   nombre.
3. **Permisos de ruta**: cada usuario sólo publica donde tiene permiso de
   escritura.

El manifiesto (`$PREFIX/share/herd-shared/sites.tsv`) guarda una línea por
sitio: `nombre<TAB>ruta<TAB>php<TAB>https<TAB>dueño`. Esa última columna es
la que hace posible el aislamiento; las entradas antiguas (sin ella) se
migran solas al instalar, deduciendo el dueño de la ruta.

> El aislamiento es **de la herramienta**, no del sistema de ficheros: el
> manifiesto y los vhosts son legibles por el grupo `staff`. Quien tenga
> acceso a la consola del Mac puede leerlos con `cat`. Para cerrar esa vía
> habría que restringir los permisos de esos ficheros (y que el CLI consultase
> al núcleo en vez de leerlos directamente).

## Problemas reales encontrados (y su arreglo)

1. **El helper de Herd puede quedarse con el PID obsoleto.** Guarda el PID del
   master en `.pid/nginx.pid` y el real en `bin/nginx.pid`. Si divergen, sus
   "restart" responden *"Nginx has been restarted"* y **no recargan nada**.
   → El núcleo sincroniza el fichero él mismo y, como root, hace el `SIGHUP`
   estándar al master; el helper queda como fallback.

2. **La caché de `realpath()` del php-fpm (120 s)** hacía que, al republicar un
   sitio con el mismo nombre, se siguiera sirviendo el directorio anterior (o un
   404 si ya no existía). → Al cambiar el destino del symlink se envía
   `SIGUSR2` al master de ese pool (recarga graceful).

3. **El socket `127.0.0.1` le gana al `0.0.0.0`.** Un vhost que sólo declare
   `listen 0.0.0.0:80;` no se sirve al entrar por loopback (responde el
   `default_server` de Herd). → Todos los vhosts declaran los dos listeners.

4. **`nginx -t` crea `nginx.pid` y `*_temp` en el directorio actual**, y el
   binario de Herd no tiene prefijo compilado → la validación de la config
   ensuciaba el proyecto del usuario. → Se valida con `-p` hacia un prefijo
   propio (`$PREFIX/share/herd-shared/nginx-test`), nunca el de Herd (truncaría
   su `nginx.pid` real).

5. **Un vhost con error deja nginx caído para todos** (el CLI dice "reiniciado"
   y devuelve 0 aunque nginx no levante). → El núcleo valida la config antes
   de recargar y, si no valida, **revierte** el vhost anterior.

6. **Los directorios ocultos no los resuelve `server.php`** (un proyecto en
   `~/mi.proyecto` da 404 aunque el symlink exista).

7. **El CLI de Herd necesita `php` en el PATH** (es un script bash que llama a
   `find-usable-php.php`); bajo launchd el PATH es `/usr/bin:/bin:…` → el
   script de recarga debe exportarlo.

8. **El PHP compilado por Herd ignora `PHP_INI_SCAN_DIR`**, así que el ini
   compartido se carga dos veces (extensión "already loaded"). → El ini
   compartido no lleva `extension=` ni `auto_prepend_file=`.

9. **El master de nginx corre como root** → un usuario normal no puede
   señalarlo (`kill -0` da EPERM); para comprobar si vive hay que usar `ps -p`.

## Recuperación

| Síntoma | Qué hacer |
|---|---|
| `herd-site link` dice que no se pudo recargar nginx | `sudo $PREFIX/libexec/herd-shared-setup --root` (repara el PID del helper) y luego `herd-site reapply` |
| Un sitio no responde tras actualizar Herd | `herd-site doctor` y `herd-site reapply` |
| Un sitio sirve contenido viejo | `herd-site link <ruta> --force` (republica y recarga los workers del fpm) |
| `herd php` se cuelga | usar `herd-site php` (el CLI de Herd son PHAR que necesitan TTY) |
| Un usuario no puede publicar | `herd-site selftest` para ver qué falla; si dice lo de sudo, falta `sudo … --root` |

## Ver cómo está el Mac

```bash
herd-site links --all    # todos los sitios y su dueño
herd-site doctor         # auditoría
cat $PREFIX/share/herd-shared/config.env
cat $PREFIX/share/herd-shared/sites.tsv
```
