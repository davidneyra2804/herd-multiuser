# Herd compartido en este Mac

Un único stack web (nginx + php-fpm) que **todos los usuarios del Mac** pueden
usar para publicar sus proyectos, igual que hace Herd pero sin tener que
instalar Herd en cada cuenta.

- Dueño del stack: el usuario dueño de Herd (Herd en `/Applications/Herd.app`)
- Dominio: `*.<tld>` — el que tenga configurado Herd (`herd tld`; por
  defecto `.test`). Este setup lo lee de la configuración de Herd, así que
  no hay que tocar nada. Se resuelve a 127.0.0.1 por dnsmasq + `/etc/resolver/test`
- Versiones de PHP servidas: 7.4, 8.3, 8.4, 8.5 (una por proyecto, vía `herd.yml`)

---

## Uso diario (cualquier usuario)

```bash
cd ~/proyectos/mi-app
herd-site link .            # publica https://<usuario>-mi-app.<tld>
herd-site link . --php 8.3  # fuerza la versión de PHP
herd-site link . --https    # fuerza HTTPS
herd-site list              # ver todos los sitios
herd-site unlink mi-app     # quitar un sitio
```

El nombre por defecto lleva el prefijo del usuario (`alice-mi-app`) para que
dos personas no colisionen. Se puede forzar con `--name` o desactivar con
`--no-namespace`.

La versión de PHP sale de `herd.yml` del proyecto:

```yaml
name: mi-app
php: '7.4'        # 7.4 | 8.0 | 8.1 | 8.2 | 8.3 | 8.4 | 8.5
secured: true     # publica por HTTPS
```

## PHP y Composer desde cualquier usuario

```bash
php74 -v              # PHP 7.4 del Herd compartido
php83 -v php84 -v php85 -v
herd-composer install # usa la versión de PHP del herd.yml del proyecto
composer74 install    # composer con PHP 7.4
```

`php` (sin sufijo) es el de Homebrew (8.5) y **no** lo toca este setup.

## Desde la LAN

Los vhosts que genera `herd-site` escuchan en `0.0.0.0:80` y `0.0.0.0:443`,
así que se ven desde otros equipos:

```bash
ipconfig getifaddr en0        # IP del Mac
curl -H "Host: mi-app.<tld>" http://192.168.18.200/
```

El certificado es comodín (`*.<tld>`) y está firmado por la CA de Herd
(*Laravel Valet CA*), que ya está en el **keychain del Sistema** → lo confían
todos los usuarios del Mac, sin avisos del navegador.

---

## Cómo está montado

| Pieza | Dónde | Qué hace |
|---|---|---|
| nginx | `/Applications/Herd.app/.../nginx-arm64` | master como **root** (helper `de.beyondco.herd.helper`), workers como el usuario dueño de Herd |
| php-fpm | `~/Library/Application Support/Herd/config/fpm/*.conf` | un pool por versión, `user=dueño group=staff`, socket `herdXX.sock` |
| DNS | dnsmasq + `/etc/resolver/test` | `*.test` → 127.0.0.1 para todo el Mac |
| Registro de sitios | `.../config/valet/Sites/<nombre>` | symlink al directorio del proyecto |
| vhosts | `.../config/valet/Nginx/<nombre>.<tld>` | los genera `herd-site-core` |
| CLI | `/opt/homebrew/bin/herd-site` | publica/quita sitios (valida y llama al núcleo) |
| Núcleo | `/opt/homebrew/libexec/herd-site-core` | lo ejecuta root vía sudo (regla en `/etc/sudoers.d/herd-site`) |
| Runtime PHP | `/opt/homebrew/share/herd-shared/php/<ver>/` | copias de los binarios de Herd, legibles por todos |
| Recarga | `~/Library/LaunchAgents/com.herd.multiusuario.reload.plist` | cada 10s comprueba el dir de vhosts y recarga nginx si cambió |

### Modelo de permisos

- nginx y php-fpm corren como `dueño:staff`; por eso **todo** proyecto
  publicado necesita ser legible por el grupo `staff`.
- `herd-site` deja el proyecto en grupo `staff`, con `g+rX` en todo el árbol y
  `g+rwX` en `storage/`, `bootstrap/cache/`, `public/build/` y `var/logs/`
  (que es donde la app escribe).
- Los directorios de Herd (`Sites/`, `Nginx/`) **no** son group-writable: sólo
  los escribe el núcleo privilegiado. Así ningún usuario puede inyectar un
  vhost que exponga ficheros privados de otro usuario.

### Aislamiento entre usuarios

El objetivo de este setup es que **un usuario no vea ni toque lo de otro**:

| | Qué ve | Qué puede tocar |
|---|---|---|
| **Usuario normal** | sólo sus sitios (`links`, `list`, `doctor`) | sólo publicar/despublicar **sus** sitios |
| **Dueño de Herd** | todos los sitios (`links --all`) | todos (repara el stack, restaura sitios) |

- `herd-site links --all` (la visión global) está reservado al dueño de Herd:
  si lo pide otro usuario, el CLI lo rechaza con un mensaje explícito.
- El **núcleo** comprueba la propiedad en cada operación: no se puede
  despublicar el sitio de otro (`el sitio 'X' no es tuyo (es de Y)`) ni
  publicar sobre el nombre de otro.
- Cada sitio se atribuye a quien lo publicó; el manifiesto guarda esa columna
  (las entradas anteriores a esa columna se migran solas al instalar).
- El dueño de Herd puede publicar sobre rutas de otros (para repararlas). Si
  restaura el sitio de alguien, debe pasarlo con `--owner <usuario>` para que
  el sitio siga siendo de ese usuario:

  ```bash
  herd-site link /Users/<otro>/proyectos/mi-app --name <nombre> --owner <otro>
  ```

### Qué se bloquea

El núcleo rechaza publicar rutas de `/etc`, `/usr`, `/bin`, `/opt`, `/var`,
`/System`, `/Applications`, `/Library`, `/private/etc`, y cualquier ruta que
contenga `.ssh`, `.gnupg`, `.aws`, `.kube`, `.config`, `Keychains`, etc.
Además sólo se puede publicar sobre rutas en las que el usuario que pregunta
tiene permiso de escritura.

---

## Instalación / reparación

```bash
# parte de el-owner (sin sudo): runtime PHP, wrappers, LaunchAgent
$PREFIX/libexec/herd-shared-setup

# parte de root (una vez): sudoers, /usr/local/bin, logs, firewall
# ($PREFIX = `brew --prefix`)
sudo $PREFIX/libexec/herd-shared-setup --root
```

## Primeros pasos para un usuario nuevo (ej. `alice`)

```bash
# 1. Comprobar que todo está en su sitio (publica un proyecto de prueba y lo borra)
herd-site selftest

# 2. Publicar su proyecto
cd ~/projects/mi-app
herd-site link .                 # → https://alice-mi-app.<tld>
```

`herd-site link` lee el `herd.yml` del proyecto:

```yaml
php: '7.4'        # versión de PHP con la que se sirve
secured: true     # publica por HTTPS
```

Y a partir de ahí, la web está en `https://alice-mi-app.<tld>`
(tanto desde el Mac como desde la LAN) y el proyecto se sirve con el PHP que
pida su `herd.yml`.

## Equivalencias con Herd

| Herd (por usuario) | Aquí |
|---|---|
| `herd link` | `herd-site link .` (lee `herd.yml`: `php:` y `secured:`) |
| `herd isolate 7.4` | `herd-site link . --php 7.4` (o dejar `php: '7.4'` en `herd.yml` una sola vez) |
| `herd php` | `herd-site php` (usa la versión aislada del proyecto) |
| `herd composer` | `herd-site composer` (composer con esa versión de PHP) |
| `herd links` | `herd-site links` (sólo los del usuario; `--all` para ver todo) |
| `herd unlink` | `herd-site unlink <host>` |
| `herd list` | `herd-site list` |
| `herd secure` | `herd-site link . --https` (cert comodín `*.<tld>`) |
| `herd park` | no aplica (el registro es por proyecto) |

`herd-site link` hace en un solo paso lo que en Herd son dos (link + isolate),
y republicar con `--php` cambia la versión en caliente (verificado: 7.4 → 8.3).

### Cómo se resuelve la versión de PHP (igual que Herd)

`herd-site php` y `herd-site composer` eligen la versión así:

1. Si el directorio actual es un sitio publicado → la versión con la que se
   está sirviendo (la del manifiesto).
2. Si no, un fichero `.valetphprc` en el proyecto (convención de Herd).
3. Si no, el `herd.yml` del proyecto (aunque aún no esté publicado).
4. Si no, la versión por defecto de Herd.

```bash
cd ~/proyectos/mi-app
herd-site php --version        # PHP 7.4.33
herd-site composer install     # composer con PHP 7.4
herd-site php artisan migrate  # artisan con PHP 7.4
```

Comandos útiles:

```bash
herd-site links                  # los enlaces del usuario actual (como 'herd links')
herd-site links --all            # los de todo el Mac, con su dueño
herd-site list                   # todos los sitios (vista global)
herd-site doctor                 # auditoría: listeners, UUID, versión, fpm, cert
herd-site reapply                # regenera los vhosts (tras actualizar Herd)
herd-site unlink alice-mi-app # quitar un sitio
herd-site prune                  # limpia del manifiesto los sitios borrados
```

`herd-site links` es el equivalente de `herd links`: muestra sólo lo publicado
por el usuario que lo ejecuta, con su ruta, versión de PHP y si va por HTTPS.
Con `--all` se ve todo el Mac (útil para saber qué ha publicado el equipo).

Requisitos: estar en el grupo `staff` (todos los usuarios del Mac lo están) y
que el admin haya instalado la regla sudoers una vez
(`sudo $PREFIX/libexec/herd-shared-setup --root`).

## Si se actualiza Herd

Herd se actualiza solo (la app en `/Applications/Herd.app`). Lo que hay **fuera**
de la app no se toca: el CLI, el runtime PHP compartido, el manifiesto de sitios
y los vhosts que genera `herd-site` se quedan como están.

Lo único que puede cambiar es lo que Herd tiene **dentro** de su app, y el
núcleo lo lee **en tiempo de ejecución**, no hardcodeado:

| Qué | Cómo lo resuelve |
|---|---|
| `server.php` y su prefijo estático (UUID) | se leen de la app en cada escritura → si Herd cambia el UUID, los vhosts se regeneran con el nuevo |
| mapa de sockets `$herd_sock_XX` | se comprueba en `config/pro/nginx/debug.conf`; si desaparece, se usa `unix:.../herdXX.sock` |
| plantilla del vhost | se replica la de `valet/cli/stubs/site.valet.conf` |
| versión de PHP de la app | el runtime compartido se refresca con `herd-shared-setup` |

**Procedimiento tras una actualización (30 segundos):**

```bash
$PREFIX/libexec/herd-shared-setup   # refresca el runtime PHP compartido
herd-site doctor                           # comprueba cada sitio
herd-site reapply                          # regenera los vhosts con la plantilla nueva
```

`herd-site doctor` avisa de: vhost que falta, listener de LAN o de local
perdido, UUID obsoleto, versión de PHP distinta de la del manifiesto, symlink
desalineado, `php-fpm` parado o certificado ausente.

`herd-site reapply` regenera los vhosts de **todos** los sitios del manifiesto
(`$PREFIX/share/herd-shared/sites.tsv`) y recarga nginx. Si la config
resultante no valida, **no recarga nada** y deja los vhosts como estaban.

Lo que **no** se rompe nunca: los sitios ya publicados siguen existiendo
(el symlink en `config/valet/Sites/` está en el home de Herd, no en la app) y
sus URLs no cambian.

## Notas

- `herd secure <sitio>` (el CLI de Herd) **reemplaza** el vhost generado por
  `herd-site` y lo deja sólo en loopback. Para volver a HTTPS usa
  `herd-site link <ruta> --https`.
- `herd link` (el CLI de Herd) sigue funcionando, pero crea vhosts que sólo
  escuchan en `127.0.0.1`. Para que se vean desde la LAN, republica con
  `herd-site`.
- El stack depende de que el usuario dueño de Herd tenga sesión iniciada (Herd.app es lo
  que mantiene vivos los php-fpm).
- `herd-site` arranca el `php-fpm` de la versión pedida si no estaba en marcha
  (si no, la web responde 502).
- Los vhosts deben escuchar **en los dos sitios**: `0.0.0.0` (LAN) y
  `127.0.0.1` (local). Si sólo escuchan en `0.0.0.0`, las peticiones a
  127.0.0.1 las atiende el `default_server` de Herd en vez del sitio.
- Log de la recarga automática:
  `tail -f ~/Library/Logs/herd-multiusuario.log`
