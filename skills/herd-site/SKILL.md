---
name: herd-site
description: Publica y opera sitios PHP en un Laravel Herd compartido por varios usuarios del mismo Mac mediante el CLI `herd-site`. Cubre link/unlink/list/links/doctor/selftest/reapply/prune/certs, versión de PHP por proyecto, HTTPS con certificado comodín, permisos de grupo, y los 9 fallos reales de Herd con su síntoma y su arreglo. Se activa cuando el usuario menciona "herd-site", "Herd compartido", "Herd multiusuario", "publicar mi proyecto en Herd", "el sitio no carga desde la LAN", "no me carga desde el móvil", "502 en mi sitio", "herd link no funciona para otro usuario", o cuando pide diagnosticar/reparar un vhost de Herd en un Mac con varias cuentas. NO usar para Herd de un solo usuario (ahí vale `herd link` normal).
license: MIT
compatibility: macOS con Homebrew y Laravel Herd instalado; requiere el stack herd-multiuser instalado
metadata:
  version: "1.0.0"
  upstream: https://github.com/davidneyra2804/herd-multiuser
---

# herd-site — Herd compartido multiusuario (macOS)

Un Mac con varias cuentas de usuario **no puede tener un Herd por persona**:
el nginx ya ocupa el puerto 80 y el estado de Herd vive en `~/Library`, que en
macOS es `drwx------` → los demás usuarios ni siquiera pueden leer sus binarios
de PHP.

`herd-site` es la solución: **un único Herd** (nginx + php-fpm) compartido por
todo el equipo, más un CLI propio que permite a cada usuario publicar sus
proyectos sin permisos y sin tocar el Herd de los demás.

> Cuando exista `herd-site` en el PATH, **éste es el CLI de publicación**.
> `herd link` sigue funcionando pero genera vhosts que sólo escuchan en
> `127.0.0.1` (inaccesibles desde la LAN) y sin el aislamiento por usuario.

## Principio activo (REGLA DURA)

**Un vhost de Herd debe declarar LOS DOS listeners:**

```nginx
listen 0.0.0.0:80;      # acceso desde la LAN
listen 127.0.0.1:80;    # acceso local
```

Si declara sólo `0.0.0.0`, el `default_server` de Herd se apropia del sitio
cuando entras por loopback. Si declara sólo `127.0.0.1`, no se ve desde la LAN.
`herd-site` los genera así por ti — pero si editas vhosts a mano, respétalo.

**No lances `nginx -t` desde el directorio de un proyecto de usuario.** El
binario de Herd no tiene prefijo compilado, así que `nginx -t` crea `nginx.pid`
y las carpetas `*_temp` **en el directorio actual** → ensucia el proyecto del
usuario. Si necesitas validar, usa `-p <prefijo propio>` que nunca sea el de
Herd (truncaría su `nginx.pid` real).

## Cuándo usar `herd-site` y cuándo `herd`

| Necesitas | Usa |
|---|---|
| Publicar un proyecto (compartir Herd multiusuario) | `herd-site link .` |
| Publicar en un Mac con un solo usuario | `herd link` |
| Fijar la versión de PHP de un proyecto | `herd-site link . --php 7.4` |
| Ejecutar PHP/composer con la versión del proyecto | `herd-site php` / `herd-site composer` |
| Ver los enlaces | `herd-site links` (`--all` para todo el Mac) |
| Despublicar | `herd-site unlink <host>` |
| HTTPS | `herd-site link . --https` (cert comodín `*.<tld>`) |

`herd-site link` hace en un paso lo que en Herd son dos (link + isolate), y
**republicar con `--php` cambia la versión en caliente**.

## Uso

### Publicar un proyecto

```bash
cd ~/proyectos/mi-app
herd-site link .
```

El nombre por defecto lleva el **prefijo de usuario** (`alice-mi-app`) para que
dos personas no colisionen. Se fuerza con `--name`, o se quita con
`--no-namespace`.

La versión de PHP y el HTTPS salen del `herd.yml` del proyecto:

```yaml
name: mi-app
php: '7.4'        # 7.4 | 8.0 | 8.1 | 8.2 | 8.3 | 8.4 | 8.5
secured: true     # publica por HTTPS
```

…o se fuerzan en la línea de comandos:

```bash
herd-site link . --php 8.3 --https
herd-site link . --name otro-nombre --force   # reemplaza un sitio existente
```

Si el sitio ya existe apuntando a otro directorio, `link` se niega: usa otro
`--name` o `--force`.

### Trabajar con la versión correcta

```bash
cd ~/proyectos/mi-app
herd-site php --version        # PHP 7.4.33  (la de tu proyecto)
herd-site composer install     # composer con PHP 7.4
herd-site php artisan migrate  # artisan con PHP 7.4
```

La versión se resuelve en este orden:

1. Si el directorio actual es un sitio publicado → la versión con la que se
   está sirviendo (la del manifiesto).
2. Si no, un `.valetphprc` en el proyecto (convención de Herd).
3. Si no, el `herd.yml` del proyecto (aunque aún no esté publicado).
4. Si no, la versión por defecto de Herd.

> **Usa `herd-site php`, no `herd php`.** No porque `herd php` se cuelgue
> (con Herd 1.30.2 responde bien), sino porque `herd php` usa **la versión de
> PHP por defecto de Herd**, no la del proyecto. `herd-site php` invoca el
> binario de la versión aislada del proyecto, que es lo que quieres al ejecutar
> migrations, tests o un script que dependa de la versión.

También hay wrappers en el PATH para todo el Mac: `php74`, `php83`, `php84`,
`php85` y `composer74`… (en `$PREFIX/bin`). `php` a secas es el de
Homebrew y **no** lo toca este setup.

### Ver qué hay publicado

```bash
herd-site links          # sólo lo tuyo
herd-site links --all    # todo el Mac, con el dueño de cada sitio
herd-site list           # vista global, con versión de PHP y HTTPS
herd-site versions       # qué versiones de PHP hay disponibles
```

### Otros

```bash
herd-site unlink mi-app  # despublicar
herd-site doctor         # auditoría (listeners, PHP, cert, fpm, UUID…)
herd-site reapply        # regenera los vhosts (tras actualizar Herd)
herd-site prune          # limpia del manifiesto los sitios ya borrados
herd-site certs          # emite el certificado comodín *.<tld>
herd-site reload         # recarga nginx
herd-site selftest       # prueba de extremo a extremo
```

## El TLD no es fijo (REGLA DURA)

**No hardcodees `.test` ni `backend.test`.** El dominio lo tiene configurado
Herd (`herd tld`) y **se lee en tiempo de ejecución** de
`config/valet/config.json`. En un Herd estándar es `.test`; en otros equipos
puede ser `backend.test` o cualquier otro.

```bash
herd tld                    # el TLD real de este Mac
herd-site links             # los sitios ya salen con su TLD
```

Si el TLD cambia, `herd-site doctor` lo avisa ("cambió el TLD") y hay que
lanzar `herd-site reapply` para regenerar los vhosts.

## Diagnóstico

```bash
herd-site doctor      # ¿qué está mal? (listeners, PHP, symlink, fpm, cert)
herd-site selftest    # publica un proyecto de prueba y comprueba HTTP, HTTPS,
                      # escritura en storage/ y acceso desde la LAN, y lo borra
```

`selftest` es el primer paso cuando un usuario dice "no me funciona": separa
"el stack está roto" de "tu proyecto está mal".

### Los 9 fallos reales de Herd (síntoma → arreglo)

Estos son los problemas que aparecen una y otra vez. **No los inventes: aplícalos.**

1. **El helper de Herd se queda con el PID obsoleto.** Guarda el PID del
   master en `.pid/nginx.pid` y el real en `bin/nginx.pid`. Si divergen, sus
   "restart" dicen *"Nginx has been restarted"* y **no recargan nada**.
   *Síntoma*: publicas un sitio y no se sirve.
   *Arreglo*: `sudo $PREFIX/libexec/herd-shared-setup --root` (repara el PID) y
   recargar con `SIGHUP` al master real. El núcleo ya lo hace por su cuenta.

2. **La caché de `realpath()` del php-fpm (120 s).** Al republicar un sitio con
   el mismo nombre, los workers siguen sirviendo el directorio anterior.
   *Síntoma*: el sitio sirve contenido viejo o da 404 tras moverlo.
   *Arreglo*: recargar ese pool con `SIGUSR2`. `herd-site link` lo hace
   automáticamente cuando cambia el destino.

3. **El socket `127.0.0.1` le gana al `0.0.0.0`.** Un vhost que sólo declare
   `listen 0.0.0.0:80;` no se sirve al entrar por loopback.
   *Arreglo*: declarar los dos listeners.

4. **`nginx -t` crea `nginx.pid` y `*_temp` en el directorio actual** (el
   binario de Herd no tiene prefijo compilado).
   *Arreglo*: nunca lanzarlo desde el proyecto del usuario; usar `-p <prefijo
   propio>`. (También por eso los residuos `nginx.pid`/`client_body_temp`/
   `fastcgi_temp`/`proxy_temp` aparecen en el directorio desde el que se validó.)

5. **Un vhost con error deja nginx CAÍDO para todos** (y el CLI dice
   "reiniciado" y devuelve 0 aunque nginx no levante).
   *Arreglo*: validar la configuración **antes** de recargar y revertir si no
   valida. `herd-site link` y `herd-site reapply` ya lo hacen.

6. **Los directorios ocultos no los resuelve `server.php`**: un proyecto en
   `~/mi.proyecto` da 404 aunque el symlink exista.
   *Arreglo*: sin punto delante — `~/mi-proyecto`.

7. **El CLI de Herd necesita `php` en el PATH** (es un script bash que llama a
   `find-usable-php.php`); bajo `launchd` el PATH es `/usr/bin:/bin:…`.
   *Arreglo*: exportar el PATH en los scripts de launchd.

8. **El PHP compilado por Herd ignora `PHP_INI_SCAN_DIR`**, así que el ini
   compartido se cargaría dos veces (extensión "already loaded").
   *Arreglo*: el ini compartido no lleva `extension=` ni `auto_prepend_file=`.

9. **El master de nginx corre como root** → `kill -0` da EPERM desde un
   usuario normal; para comprobar si vive hay que usar `ps -p`.

Ver `references/fallos.md` para el detalle y `references/arquitectura.md` para
el diseño completo (permisos, seguridad, modelo multiusuario).

## Después de una actualización de Herd

Herd se actualiza solo. Lo que hay **fuera** de la app no se toca: el CLI, el
runtime PHP compartido, el manifiesto y los vhosts se quedan.

```bash
$PREFIX/libexec/herd-shared-setup   # refresca el runtime PHP compartido
herd-site doctor                    # comprueba cada sitio
herd-site reapply                   # regenera los vhosts con la plantilla nueva
```

Lo único que puede cambiar es lo que Herd tiene **dentro** de su app, y el
núcleo lo lee **en tiempo de ejecución**, no hardcodeado: el `server.php` y su
prefijo estático (UUID), el mapa de sockets `$herd_sock_XX` y la plantilla del
vhost.

`herd-site reapply` **no recarga nada** si la config resultante no valida:
deja los vhosts como estaban.

## Modelo de permisos y seguridad

- **nginx y php-fpm corren como `dueño:staff`** → todo proyecto publicado
  necesita ser legible por el grupo `staff`.
- `herd-site link` deja el proyecto en grupo `staff`, con `g+rX` en todo el
  árbol y `g+rwX` en `storage/`, `bootstrap/cache/`, `public/build/` y
  `var/logs/` (donde la app escribe).
- Los directorios de Herd (`Sites/`, `Nginx/`) **no** son group-writable: sólo
  escribe el núcleo privilegiado. Así ningún usuario puede inyectar un vhost
  que exponga ficheros privados de otro.
- El núcleo **exige saber quién pregunta** (`SUDO_USER`) y valida cada petición:
  rechaza publicar desde `/etc`, `/usr`, `/Applications`, `/Library`… y desde
  rutas con `.ssh`, `.gnupg`, `.aws`, `Keychains`… Sólo se puede publicar
  sobre rutas en las que el usuario tiene permiso de escritura.
- La regla sudoers es mínima: `%staff` puede ejecutar **sólo** el núcleo, que
  sólo sabe registrar, desvincular, recargar y auditar sitios.

## Instalar el stack (si no está instalado)

```bash
git clone https://github.com/davidneyra2804/herd-multiuser.git
cd herd-multiuser
./install.sh                 # scripts, runtime PHP, wrappers, recarga automática
sudo ./install.sh --root     # sudoers, /usr/local/bin, permisos de logs y firewall
```

`install.sh` es **idempotente**: ejecútalo cuando quieras para sincronizar con
el repositorio (`git pull` + `./install.sh`).

## Rutas

| Qué | Dónde |
|---|---|
| CLI de usuario | `$PREFIX/bin/herd-site` (`$PREFIX` = `brew --prefix`) |
| Núcleo privilegiado | `$PREFIX/libexec/herd-site-core` |
| Instalador / reparador | `$PREFIX/libexec/herd-shared-setup` |
| Runtime PHP compartido | `$PREFIX/share/herd-shared/php/<ver>/` |
| Configuración | `$PREFIX/share/herd-shared/config.env` |
| Manifiesto de sitios | `$PREFIX/share/herd-shared/sites.tsv` |
| Regla sudoers | `/etc/sudoers.d/herd-site` |
| Vhosts generados | `~<dueño>/Library/Application Support/Herd/config/valet/Nginx/` |
| Registro de sitios (symlinks) | `~<dueño>/Library/Application Support/Herd/config/valet/Sites/` |
| Log de la recarga automática | `~/Library/Logs/herd-multiusuario.log` |

## Cuándo invocar esta skill

Cargar cuando el usuario mencione:

- "herd-site", "Herd compartido", "Herd multiusuario", "publicar con herd-site"
- "no me carga desde la LAN / desde el móvil / desde otra máquina"
- "502 en mi sitio", "el sitio no responde", "sirve contenido viejo"
- "otro usuario no puede publicar su proyecto"
- "despublicar", "quitar el sitio", "cambiar la versión de PHP de mi proyecto"
- "diagnosticar Herd", "doctor", "selftest", "reapply"

**NO** cargar para: Herd de un solo usuario, Docker, Valet Linux, Devilbox,
Laragon, XAMPP, MAMP, o cualquier entorno que no sea Herd nativo de macOS.

## Fuentes

- Verificado en macOS con Herd 1.30.2 (Apple Silicon).
- Implementación y detalle: https://github.com/davidneyra2804/herd-multiuser
