# Los 9 fallos reales de Herd (síntoma → diagnóstico → arreglo)

Problemas reales encontrados al montar el Herd compartido. Son los que
vuelven a aparecer, y ninguno se deduce del código de Herd.

---

## 1. El helper de Herd se queda con el PID obsoleto

**Qué pasa.** El helper privilegiado de Herd guarda el PID del master de nginx
en `~/Library/Application Support/Herd/.pid/nginx.pid`, pero el PID real está
en `~/Library/Application Support/Herd/bin/nginx.pid`. Si divergen, los
"restart" del helper responden *"Nginx has been restarted"* y **no recargan
nada**.

**Síntoma.** Publicas un sitio y no se sirve. `herd restart` dice que todo bien.
Los vhosts nuevos no aparecen.

**Diagnóstico.**

```bash
cat "$HERD_HOME/bin/nginx.pid"      # PID real
cat "$HERD_HOME/.pid/nginx.pid"     # PID del helper
```

Si difieren, ése es el problema.

**Arreglo.** Como root, recargar con `SIGHUP` al master real. El núcleo de
`herd-site` ya lo hace (además sincroniza el fichero del helper para que su
fallback también funcione). Si el núcleo no puede:

```bash
sudo $PREFIX/libexec/herd-shared-setup --root   # repara el estado
herd-site reapply
```

---

## 2. La caché de `realpath()` del php-fpm (120 s)

**Qué pasa.** PHP cachea la resolución de los symlinks (`realpath_cache_ttl`,
por defecto 120 s). Al republicar un sitio con el mismo nombre pero otra
ruta, los workers del pool siguen sirviendo el directorio anterior — o un 404
si ese directorio ya no existe.

**Síntoma.** El sitio sirve contenido viejo, o da 404 aunque acabas de moverlo.

**Arreglo.** Recargar *gracefully* ese pool con `SIGUSR2` al master:

```bash
kill -USR2 "$(pgrep -f 'php-fpm: master process.*74-fpm.conf' | head -1)"
```

`herd-site link` lo hace automáticamente cuando el destino del symlink cambia.

---

## 3. El socket `127.0.0.1` le gana al `0.0.0.0`

**Qué pasa.** nginx atiende la conexión por el listener más específico. Un
vhost que sólo declare `listen 0.0.0.0:80;` **no** se sirve cuando la
petición entra por loopback: la atiende el `default_server` de Herd.

**Síntoma.** El sitio funciona desde otro equipo de la LAN pero no en el Mac
(local), o al revés.

**Arreglo.** Declarar los dos listeners en cada vhost:

```nginx
listen 0.0.0.0:80;
listen 127.0.0.1:80;
```

(ídem en 443 para HTTPS). `herd-site` los genera siempre así.

---

## 4. `nginx -t` crea `nginx.pid` y `*_temp` en el directorio actual

**Qué pasa.** El binario de nginx de Herd está compilado **sin prefijo**, así
que `nginx -t` crea en el directorio de trabajo el fichero de PID y las carpetas
`client_body_temp`, `fastcgi_temp` y `proxy_temp`.

**Síntoma.** Aparecen `nginx.pid` y carpetas `*_temp` dentro del proyecto del
usuario. En un proyecto git versionado ensucia el repo.

**Arreglo.** Nunca lanzar `nginx -t` desde el directorio de un proyecto. Usar
un prefijo propio:

```bash
nginx-arm64 -t -p "$PREFIX/share/herd-shared/nginx-test" -c "$HERD_HOME/config/nginx/nginx.conf"
```

Y **nunca** el prefijo de Herd: truncaría su `nginx.pid` real y rompería el
arranque del nginx.

---

## 5. Un vhost con error deja nginx CAÍDO para todos

**Qué pasa.** El CLI de Herd recarga nginx y devuelve 0 ("reiniciado") aunque
nginx no levante por un error de configuración en *otro* vhost.

**Síntoma.** Después de un `herd link`, **ningún** sitio del Mac responde.

**Arreglo.** Validar la configuración **antes** de recargar, y revertir el
vhost anterior si no valida:

```bash
nginx-arm64 -t -p <prefijo propio> -c "$HERD_HOME/config/nginx/nginx.conf"
```

`herd-site link` y `herd-site reapply` validan y revierten solos: si la config
no valida, `reapply` **no recarga nada** y deja los vhosts como estaban.

---

## 6. Los directorios ocultos no los resuelve `server.php`

**Qué pasa.** El `server.php` de Valet (que usa Herd) no resuelve rutas cuyo
último componente empieza por punto.

**Síntoma.** El symlink existe, el vhost está bien, y da 404.

**Arreglo.** Sin punto delante: `~/mi-proyecto`, nunca `~/mi.proyecto`.

---

## 7. El CLI de Herd necesita `php` en el PATH

**Qué pasa.** El CLI de Herd es un script bash que llama a
`find-usable-php.php`. Bajo `launchd` el PATH es `/usr/bin:/bin:/usr/sbin:…` →
no encuentra PHP.

**Síntoma.** Los scripts de arranque/parada de Herd fallan cuando los lanza
`launchd` o un agente, pero funcionan en una terminal.

**Arreglo.** Exportar el PATH de Herd en el script:

```bash
export PATH="$HERD_HOME/bin:$PATH"
```

---

## 8. El PHP compilado por Herd ignora `PHP_INI_SCAN_DIR`

**Qué pasa.** El PHP de Herd está compilado sin soporte de `PHP_INI_SCAN_DIR`
(o lo ignora), así que un `php.ini` compartido con `extension=` se cargaría dos
veces.

**Síntoma.** `PHP Warning: Module "xdebug" is already loaded in Unknown on
line 0`.

**Arreglo.** El `php.ini` del runtime compartido **no** lleva líneas
`extension=` ni `auto_prepend_file=` (son features del dashboard y del Xdebug de
Herd). Además, el `php.ini` de Herd se copia con la ruta del CA bundle
apuntando al bundle compartido.

---

## 9. El master de nginx corre como root

**Qué pasa.** Los workers corren como el usuario dueño de Herd, pero el master
lo lanza el helper privilegiado → es root.

**Síntoma.** `kill -0 <pid>` devuelve EPERM desde un usuario normal y parece
que el proceso está muerto.

**Arreglo.** Comprobar con `ps -p <pid>` en lugar de `kill -0`.

---

## Bonus: `herd php` usa la versión por defecto, no la del proyecto

`herd php ...` y `herd composer ...` son PHAR que ejecutan el **PHP por
defecto de Herd**, ignorando la versión aislada del proyecto.

*Síntoma*. En un proyecto con `php: '7.4'` en su `herd.yml`, `herd php
artisan migrate` corre con PHP 8.4 y falla con errores de sintaxis de PHP 7.4
("Array and string offset access syntax with curly braces is no longer
supported"), o al revés: una función que sólo existe en PHP 8 da "undefined
function" porque `herd php` usa la 7.4.

**Arreglo.** En un Mac con el stack compartido, usar `herd-site php` y
`herd-site composer`, que eligen la versión del proyecto. O los wrappers
`php74`, `php83`, `php84`, `php85` directamente.

> Con Herd 1.30.2 los PHAR de Herd responden bien sin TTY (verificado: 0.2 s).
> En versiones anteriores se colgaban al invocarlos desde un shell sin TTY
> (agentes, CI, `launchd`); si alguna vez se cuelgan, `herd-site php` y los
> wrappers siguen funcionando porque invocan el binario directamente.
