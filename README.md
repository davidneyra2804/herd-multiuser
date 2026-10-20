# Herd compartido (multiusuario) para macOS

Un único stack web (nginx + php-fpm) de [Laravel Herd](https://herd.laravel.com)
que **todos los usuarios del Mac** pueden usar para publicar sus proyectos,
sin instalar Herd por usuario.

```
vyrglobal$ cd ~/projects/php_gts_api
vyrglobal$ herd-site link .
  sitio: vyrglobal-php-gts-api.backend.test   php: 7.4   https: 0
Listo. Desde este Mac:  http://vyrglobal-php-gts-api.backend.test
```

## Por qué hace falta

Herd es 100% por usuario: todo su estado vive en
`~/Library/Application Support/Herd` y `~/Library` es `drwx------` en macOS, así
que los demás usuarios no pueden ni leer los binarios de PHP ni el CLI `herd`.
Además el nginx de Herd ya ocupa el `:80`, de modo que un segundo Herd no
puede arrancar.

Este proyecto resuelve las dos cosas: **un solo Herd** (el del usuario
propietario) que sirve los proyectos de todos, y un **CLI propio**
(`herd-site`) que permite a cada usuario publicar lo suyo sinprivilegios.

## Requisitos

- macOS con [Herd](https://herd.laravel.com) instalado e inicializado (la app
  abierta al menos una vez).
- [Homebrew](https://brew.sh).
- Ser miembro del grupo `staff` (por defecto, todos los usuarios del Mac).

## Instalación

```bash
git clone <este-repo> herd-multiuser
cd herd-multiuser
./install.sh                      # sin sudo: scripts, runtime PHP, wrappers, launchd
sudo ./install.sh --root          # una vez: sudoers, /usr/local/bin, logs, firewall
```

`install.sh` es **idempotente**: tras un `git pull` se vuelve a ejecutar para
sincronizar los scripts con el repositorio.

## Uso

| Herd (por usuario) | Aquí |
|---|---|
| `herd link` | `herd-site link .` |
| `herd isolate 7.4` | `herd-site link . --php 7.4` |
| `herd php` | `herd-site php` |
| `herd composer` | `herd-site composer` |
| `herd links` | `herd-site links` (`--all` para ver todo el Mac) |
| `herd unlink` | `herd-site unlink <host>` |
| `herd list` | `herd-site list` |
| `herd secure` | `herd-site link . --https` |

Comandos propios:

```bash
herd-site doctor      # auditoría: listeners, UUID, versión de PHP, fpm, certificado
herd-site reapply     # regenera los vhosts (tras actualizar Herd)
herd-site prune       # quita del manifiesto los sitios ya borrados
herd-site selftest    # prueba de extremo a extremo (publica, comprueba y borra)
```

## Qué se instala

| Qué | Dónde |
|---|---|
| CLI de usuario | `$PREFIX/bin/herd-site` |
| Núcleo privilegiado | `$PREFIX/libexec/herd-site-core` |
| Instalador / reparador | `$PREFIX/libexec/herd-shared-setup` |
| Runtime PHP compartido (7.4, 8.3, 8.4, 8.5) | `$PREFIX/share/herd-shared/php/<ver>/` |
| Configuración | `$PREFIX/share/herd-shared/config.env` |
| Manifiesto de sitios | `$PREFIX/share/herd-shared/sites.tsv` |
| Certificados | `$PREFIX/share/herd-shared/certs/` |
| Recarga automática de nginx | `~/Library/LaunchAgents/com.herd.multiusuario.reload.plist` |
| Regla sudoers | `/etc/sudoers.d/herd-site` |

(`$PREFIX` = `brew --prefix`, normalmente `/opt/homebrew`.)

## Documentación

- [docs/guia.md](docs/guia.md) — guía para el equipo (usuarios).
- [docs/arquitectura.md](docs/arquitectura.md) — cómo funciona por dentro, el
  modelo de permisos y de seguridad, y los problemas que hubo que resolver.

## Desinstalar

```bash
./uninstall.sh                 # borra scripts, runtime y sitios publicados
./uninstall.sh --keep-sites    # conserva los sitios publicados
```
