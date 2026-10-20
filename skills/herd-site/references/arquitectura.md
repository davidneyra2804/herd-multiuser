# Arquitectura del Herd compartido

Cómo está montado, por qué está montado así, y qué significa para el que opera.

## Las piezas de Herd (y por qué se pueden compartir)

| Pieza | Dónde | Nota |
|---|---|---|
| nginx | `/Applications/Herd.app/Contents/Resources/nginx-arm64` | el **master** corre como root vía el helper privilegiado `de.beyondco.herd.helper`; los workers como el usuario dueño de Herd (`user "dueño" staff;`) |
| php-fpm | `$HERD_HOME/config/fpm/<ver>-fpm.conf` | un pool por versión, `user=dueño`, `group=staff`, socket `$HERD_HOME/herd<ver>.sock`, `listen.mode=0777` |
| DNS | dnsmasq + `/etc/resolver/<tld>` | `address=/.<tld>/127.0.0.1` → `*.<tld>` resuelve a 127.0.0.1 **para todo el Mac** |
| registro de sitios | `$HERD_HOME/config/valet/Sites/<nombre>` | symlink al directorio del proyecto |
| vhosts | `$HERD_HOME/config/valet/Nginx/<nombre>.<tld>` | el `nginx.conf` hace `include` de todo lo que haya ahí |
| plantilla de vhost | `valet/cli/stubs/site.valet.conf` | el núcleo la replica |
| CA de TLS | `$HERD_HOME/config/valet/CA/` | "Laravel Valet CA", **ya está en el keychain del Sistema** → la confían todos los usuarios |

Lo que **no** se comparte (y es lo que había que resolver): el CLI, los
binarios de PHP y el `php.ini` viven en `~/Library/Application Support/Herd`, y
`~/Library` es `drwx------` en macOS → ningún otro usuario puede ejecutarlos.

## Qué añade este proyecto

1. **Runtime PHP compartido**: copia los binarios de PHP de Herd a
   `$PREFIX/share/herd-shared/php/<ver>/` (legibles por todos) y genera
   `php74`, `php83`… en `$PREFIX/bin`.
2. **CLI `herd-site`**: valida la petición en el usuario y llama al núcleo
   privilegiado.
3. **Núcleo `herd-site-core`**: crea el symlink del sitio, escribe el vhost,
   aplica los permisos de grupo, valida la config y recarga nginx.
4. **Recarga automática**: un LaunchAgent (`StartInterval 10`) que compara la
   marca de tiempo del directorio de vhosts y recarga nginx si ha cambiado.

## El manifiesto de sitios

`$PREFIX/share/herd-shared/sites.tsv` — una línea por sitio gestionado por
`herd-site`, con campos separados por tabulador:

```
nombre<TAB>ruta<TAB>versión_php<TAB>https(0|1)<TAB>dueño
```

Es lo que permite regenerar los vhosts (`reapply`) y auditarlos (`doctor`)
tras una actualización de Herd. `herd-site prune` quita las entradas cuyo
proyecto ya no existe.

## Modelo de permisos

- nginx y php-fpm corren como `dueño:staff` → **todo** proyecto publicado debe
  ser legible por el grupo `staff`.
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
  permiso de escritura (o que están bajo su home).
- El nombre del sitio se valida: `^[a-z0-9-]{1,48}$`.
- La regla sudoers es mínima: `%staff` puede ejecutar **sólo** el núcleo, que
  sólo sabe hacer cuatro cosas: vincular, desvincular, recargar y auditar.

## Recuperación

| Síntoma | Qué hacer |
|---|---|
| `herd-site link` dice que no se pudo recargar nginx | `sudo $PREFIX/libexec/herd-shared-setup --root` (repara el PID del helper) y luego `herd-site reapply` |
| Un sitio no responde tras actualizar Herd | `herd-site doctor` y `herd-site reapply` |
| Un sitio sirve contenido viejo | `herd-site link <ruta> --force` (republica y recarga los workers del fpm) |
| `herd php` se cuelga | usar `herd-site php` (los PHAR de Herd necesitan TTY) |
| Un usuario no puede publicar | `herd-site selftest` para ver qué falla; si dice lo de sudo, falta `sudo … --root` |
| El sitio da 404 y el symlink existe | el directorio empieza por punto → renómbralo (fallo 6) |
| Aparecen `nginx.pid` y `*_temp` en un proyecto | se validó la config desde ese directorio → bórralos y valida con `-p <prefijo>` (fallo 4) |

## Ver cómo está el Mac

```bash
herd-site links --all    # todos los sitios y su dueño
herd-site doctor         # auditoría
cat $PREFIX/share/herd-shared/config.env
cat $PREFIX/share/herd-shared/sites.tsv
```

## Compatibilidad con actualizaciones de Herd

Herd se actualiza solo y lo que hay **fuera** de la app no se toca: el CLI, el
runtime PHP compartido, el manifiesto y los vhosts se quedan como están.

Lo único que puede cambiar es lo que Herd tiene **dentro** de su app, y el
núcleo lo lee **en tiempo de ejecución**, no hardcodeado:

| Qué | Cómo lo resuelve |
|---|---|
| `server.php` y su prefijo estático (UUID) | se leen de la app en cada escritura → si Herd cambia el UUID, los vhosts se regeneran con el nuevo |
| mapa de sockets `$herd_sock_XX` | se comprueba en `config/pro/nginx/debug.conf`; si desaparece, se usa `unix:.../herdXX.sock` |
| plantilla del vhost | se replica la de `valet/cli/stubs/site.valet.conf` |
| versión de PHP de la app | el runtime compartido se refresca con `herd-shared-setup` |

Procedimiento tras una actualización (30 segundos):

```bash
$PREFIX/libexec/herd-shared-setup   # refresca el runtime PHP compartido
herd-site doctor                    # comprueba cada sitio
herd-site reapply                   # regenera los vhosts con la plantilla nueva
```
