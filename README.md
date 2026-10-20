# 🐄 Herd compartido para macOS

**Un solo [Laravel Herd](https://herd.laravel.com) para todos los usuarios del Mac.**

En un Mac con varias cuentas, Herd no sirve de nada para el resto: cada usuario
tendría que instalar su propio Herd, pero **solo puede haber uno** (el nginx ya
ocupa el puerto 80) y además el estado de Herd vive en `~/Library`, que en macOS
es `drwx------` → los demás usuarios ni siquiera pueden leer sus binarios de PHP.

Este proyecto resuelve las dos cosas:

- **Un único stack** (nginx + php-fpm) compartido por todo el equipo.
- **Un CLI propio** (`herd-site`) para que cada usuario publique sus proyectos
  sin permisos y sin tocar el Herd de los demás.

```console
$ cd ~/proyectos/mi-app
$ herd-site link .
  sitio: alice-mi-app.backend.test   php: 7.4   https: 0
  URL   http://alice-mi-app.backend.test
```

Y ya está: `http://alice-mi-app.backend.test` funciona en el Mac y en la LAN.

---

## ¿Qué te da?

| | Herd normal (por usuario) | Aquí |
|---|---|---|
| Publicar un proyecto | `herd link` | `herd-site link .` |
| Fijar la versión de PHP | `herd isolate 7.4` | `herd-site link . --php 7.4` |
| Ejecutar el PHP del proyecto | `herd php` | `herd-site php` |
| Composer con esa versión | `herd composer` | `herd-site composer` |
| Ver tus enlaces | `herd links` | `herd-site links` |
| Despublicar | `herd unlink` | `herd-site unlink <host>` |
| HTTPS | `herd secure` | `herd-site link . --https` |

Además, cosas que Herd no tiene porque en un Mac multiusuario hacen falta:

- **`herd-site links --all`** — qué ha publicado cada uno, con su dueño.
- **`herd-site doctor`** — auditoría: listeners, versión de PHP, certificado,
  php-fpm en marcha, UUID de Herd… y avisa de lo que se ha quedado obsoleto.
- **`herd-site reapply`** — regenera los vhosts (para cuando actualizas Herd).
- **`herd-site selftest`** — prueba de extremo a extremo: publica un proyecto de
  prueba, comprueba HTTP, HTTPS, escritura en `storage/` y acceso desde la LAN, y
  lo borra.
- **Nombres con prefijo de usuario** (`alice-mi-app`) para que nadie pise el
  sitio de otro.
- **Certificado comodín** `*.backend.test` firmado por la CA de Herd, que ya
  está en el keychain del Sistema → **todos los usuarios confían en él** sin
  avisos del navegador.
- **Acceso desde la LAN** (listeners en `0.0.0.0`), no sólo desde el Mac.

---

## Instalación

Requisitos: **Herd** instalado e inicializado (abre la app una vez), **Homebrew**
y ser miembro del grupo `staff` (por defecto, todos los usuarios del Mac).

```bash
git clone https://github.com/davidneyra2804/herd-multiuser.git
cd herd-multiuser
./install.sh                 # scripts, runtime PHP compartido, wrappers, recarga automática
sudo ./install.sh --root     # sudoers, /usr/local/bin, permisos de logs y firewall
```

`install.sh` es **idempotente**: ejecútalo cuando quieras para sincronizar con
el repositorio (`git pull` + `./install.sh`).

### ¿Qué instala?

| Qué | Dónde |
|---|---|
| CLI de usuario | `$PREFIX/bin/herd-site` |
| Núcleo privilegiado | `$PREFIX/libexec/herd-site-core` |
| Instalador / reparador | `$PREFIX/libexec/herd-shared-setup` |
| Runtime PHP compartido (7.4, 8.3, 8.4, 8.5…) | `$PREFIX/share/herd-shared/php/<ver>/` |
| Configuración | `$PREFIX/share/herd-shared/config.env` |
| Manifiesto de sitios | `$PREFIX/share/herd-shared/sites.tsv` |
| Recarga automática de nginx | `~/Library/LaunchAgents/com.herd.multiusuario.reload.plist` |
| Regla sudoers | `/etc/sudoers.d/herd-site` |

(`$PREFIX` = `brew --prefix`, normalmente `/opt/homebrew`.)

---

## Uso diario

### Publicar un proyecto

```bash
cd ~/proyectos/mi-app
herd-site link .
```

La versión de PHP y el HTTPS salen del `herd.yml` del proyecto:

```yaml
name: mi-app
php: '7.4'        # 7.4 | 8.0 | 8.1 | 8.2 | 8.3 | 8.4 | 8.5
secured: true     # publica por HTTPS
```

…o se fuerzan en la línea de comandos:

```bash
herd-site link . --php 8.3 --https
```

### Trabajar con la versión correcta

```bash
cd ~/proyectos/mi-app
herd-site php --version        # PHP 7.4.33  (la de tu proyecto)
herd-site composer install     # composer con PHP 7.4
herd-site php artisan migrate  # artisan con PHP 7.4
```

La versión se resuelve igual que en Herd: la del sitio publicado → un
`.valetphprc` en el proyecto → el `herd.yml` → la versión por defecto de Herd.

### Ver qué hay publicado

```bash
herd-site links          # sólo lo tuyo
herd-site links --all    # todo el Mac, con el dueño de cada sitio
herd-site list           # vista global, con versión de PHP y HTTPS
```

### Otros

```bash
herd-site unlink mi-app  # despublicar
herd-site doctor         # auditoría
herd-site reapply        # regenerar los vhosts (tras actualizar Herd)
herd-site prune          # limpiar el manifiesto de sitios borrados
herd-site selftest       # prueba de extremo a extremo
```

---

## Cómo funciona (en breve)

- El **nginx** de Herd ya corre como **root** (vía su helper privilegiado) y
  sus workers como el usuario dueño de Herd, en el grupo `staff`.
- El **php-fpm** de cada versión de PHP está en un pool con
  `user=dueño`, `group=staff`.
- El **DNS** ya resolvía `*.backend.test` → `127.0.0.1` para todo el Mac
  (dnsmasq + `/etc/resolver/test`).
- El **registro de sitios** de Herd son symlinks en
  `~/Library/Application Support/Herd/config/valet/Sites/`.
- Los **vhosts** son ficheros en `.../config/valet/Nginx/`, y el `nginx.conf`
  hace `include` de todo lo que haya ahí.

Lo que este proyecto añade:

1. **Runtime PHP compartido**: copia los binarios de PHP de Herd a un sitio
   legible por todos y genera `php74`, `php83`… en el `PATH`.
2. **`herd-site`**: valida la petición en el usuario y pide al núcleo
   privilegiado que registre el sitio.
3. **Permisos de grupo**: el proyecto se deja legible (y con `storage/`
   escribible) por el grupo `staff`, para que el php-fpm pueda servirlo y
   escribir en él aunque sea de otro usuario.
4. **Recarga automática**: un LaunchAgent comprueba cada 10 segundos si han
   cambiado los vhosts y recarga nginx si es así.

El detalle completo (incluidos los nueve problemas que hubo que resolver
—cachés de `realpath()`, PIDs obsoletos del helper, el prefijo de nginx, el
modelo de seguridad…) está en **[docs/arquitectura.md](docs/arquitectura.md)**.

---

## Seguridad

- El núcleo exige saber **quién** pregunta (`SUDO_USER`) y valida cada petición.
- No se puede publicar desde rutas sensibles (`/etc`, `/usr`, `/Applications`,
  `/Library`…) ni desde rutas con `.ssh`, `.gnupg`, `.aws`, `Keychains`…
- Solo se puede publicar sobre rutas en las que el usuario tiene permiso de
  escritura.
- Los directorios de Herd **no** son group-writable: nadie puede inyectar un
  vhost que exponga ficheros privados de otro usuario.
- La regla sudoers es mínima: el núcleo sólo sabe registrar y auditar sitios.

---

## Documentación

- **[docs/guia.md](docs/guia.md)** — guía práctica para el equipo.
- **[docs/arquitectura.md](docs/arquitectura.md)** — diseño, permisos,
  seguridad y problemas resueltos.

## Licencia

MIT — ver [LICENSE](LICENSE).

## Desinstalar

```bash
./uninstall.sh                 # borra scripts, runtime y sitios publicados
./uninstall.sh --keep-sites    # conserva los sitios publicados
```

---

## Nota

Este proyecto no modifica Herd: se apoya en él. Si Herd se actualiza, la
mayoría sigue funcionando (el núcleo lee en tiempo de ejecución lo que puede
cambiar: el `server.php`, el prefijo de los estáticos y el mapa de sockets) y
con `herd-site reapply` se regeneran los vhosts con la plantilla nueva.

Si le resultaba útil, ⭐️ y a compartirlo con quien tenga el mismo problema.
