# Recursos SQLite para web

`sqlite3.wasm` y `drift_worker.dart.js` provienen de la publicacion oficial
[drift-2.35.4](https://github.com/simolus3/drift/releases/tag/drift-2.35.4),
correspondiente a la version de `drift` en `pubspec.lock`.

El worker publicado se llama `drift_worker.js`; se guarda aqui como
`drift_worker.dart.js` para coincidir con `DriftWebOptions`. No se ha modificado.
SQLite y el worker se sirven desde el mismo sitio, no desde un CDN.

Para obtener de nuevo estos archivos, desde la raiz del proyecto:

```bash
curl --fail --location https://github.com/simolus3/drift/releases/download/drift-2.35.4/sqlite3.wasm --output web/sqlite3.wasm
curl --fail --location https://github.com/simolus3/drift/releases/download/drift-2.35.4/drift_worker.js --output web/drift_worker.dart.js
sha256sum web/sqlite3.wasm web/drift_worker.dart.js
```

Sumas SHA-256 verificadas contra los metadatos de la publicacion:

```text
e7451780e78c56ff864fe9317a0fbcd6aeb2e8de3beba7f5efd963202f7ec3d9  web/sqlite3.wasm
48c950cd8e3bc3cddb34816c860e228be8832bef07a297c27e9907c057ff8162  web/drift_worker.dart.js
```

Al actualizar Drift, revisar su documentacion y obtener ambos recursos compatibles
antes de volver a compilar y probar el navegador. El servidor debe entregar WASM
con `Content-Type: application/wasm`. Algunas implementaciones OPFS necesitan
cabeceras `Cross-Origin-Opener-Policy: same-origin` y
`Cross-Origin-Embedder-Policy: require-corp`; Drift puede usar IndexedDB sin ellas
cuando el navegador lo permite.

La aplicacion rechaza el modo solo en memoria y el modo IndexedDB sin coordinacion
segura entre pestanas. Los datos SQLite se guardan en OPFS o IndexedDB, no en la
cache de archivos de la aplicacion.

## Compilar, servir y probar sin conexion

Requisitos de las herramientas: Flutter en `PATH`, Node.js 22 o superior y, para
las pruebas, Chromium instalado. Las herramientas Node solo se usan para compilar,
servir archivos estaticos y probar; no forman parte de la aplicacion Flutter.

Desde la raiz del proyecto:

```bash
npm ci --ignore-scripts
npm run build:web
npm run serve:web
```

Abrir `http://127.0.0.1:8080/` y esperar el indicador **Disponible sin conexion**
antes de cerrar. Tras esa preparacion se puede detener el servidor, cerrar el
navegador y volver a abrir la misma URL con el mismo perfil, sin red. La carga
inicial tambien puede realizarse desde este servidor local sin acceso a Internet,
si las herramientas y dependencias ya estan instaladas.

El servidor de ejemplo solo entrega archivos: no recibe tareas ni ofrece una API
de datos. En produccion se debe distribuir **todo `build/web/`** mediante HTTPS,
con un origen estable. Service workers requieren un contexto seguro; localhost
es una excepcion permitida para desarrollo y pruebas.

`npm run build:web` ejecuta `flutter build web --release --no-web-resources-cdn`,
habilita el registro del worker offline y genera su lista completa de recursos y
una version SHA-256 basada en sus contenidos. No editar el worker de `build/web/`.
Se cachean el programa, CanvasKit, fuentes locales, SQLite WASM y el worker Drift.
El bundle actual contiene 44 recursos de precache y ocupa aproximadamente 42 MiB.

No se usa el worker antiguo generado por Flutter: el empaquetador lo elimina del
bundle. `flutter run` y `flutter build web` por si solos no habilitan este modo
offline. Para desarrollo usar otro puerto/perfil, evitando que una cache release
del mismo origen oculte cambios del servidor de desarrollo.

### Actualizaciones y limites

- La instalacion solo termina si se pueden cachear todos los recursos. Si falla,
  se elimina la cache incompleta y la version anterior sigue disponible.
- Una nueva version espera a que se cierren las pestanas anteriores; no se fuerza
  `skipWaiting()` ni se mezcla una aplicacion vieja con recursos nuevos.
- Al activar, se eliminan solo las caches antiguas del mismo scope. Nunca se
  elimina SQLite de OPFS o IndexedDB como parte de una actualizacion del programa.
- El borrado de datos del sitio, el modo privado y las politicas de cuota o
  desalojo del navegador pueden eliminar la cache y/o las tareas. No es un backup.
- Roboto se incluye en `assets/fonts/`. El fallback de fuentes apunta al mismo
  origen, no a Google Fonts. Caracteres sin cobertura local pueden verse como
  glifos faltantes, aunque SQLite conserva el texto Unicode completo.

### Pruebas de navegador

```bash
CHROME_EXECUTABLE=/usr/bin/chromium npm run test:web
```

Las pruebas usan perfiles temporales, sin tocar los datos del usuario. Verifican
CRUD, cierre completo, reapertura offline, otro CRUD sin red y una segunda
reapertura, tanto con OPFS (COOP/COEP) como con IndexedDB (sin esas cabeceras).
Cierran realmente el servidor HTTP y el navegador, y comprueban que no haya
solicitudes externas ni llamadas al servidor durante el CRUD. Tambien prueban una
actualizacion entre dos versiones, la limpieza de cache y la conservacion de SQLite.

El ejecutable se puede cambiar mediante `CHROME_EXECUTABLE`. No hace falta
ChromeDriver ni descargar navegadores con Playwright. Se utiliza `playwright-core`
solo como dependencia de desarrollo, fijada en `package-lock.json`.

### Publicacion en una subruta

```bash
npm run build:web -- --base-href=/tasks/
BASE_PATH=/tasks/ npm run serve:web
```

Abrir `http://127.0.0.1:8080/tasks/`. Para ejecutar las pruebas sobre ese bundle:

```bash
BASE_PATH=/tasks/ CHROME_EXECUTABLE=/usr/bin/chromium npm run test:web
```

`PORT` cambia el puerto del servidor de ejemplo. `WEB_ISOLATION=false` desactiva
COOP/COEP para probar IndexedDB. No cambiar el origen entre ejecuciones si se
quiere recuperar la misma base. Para volver a publicar en la raiz, recompilar con
`npm run build:web -- --base-href=/`.

Las licencias MIT de Drift y de los bindings sqlite3 se incluyen en
`THIRD_PARTY_NOTICES.txt`. El motor SQLite es de
[dominio publico](https://sqlite.org/copyright.html).
