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
segura entre pestanas. Incluir estos archivos no configura automaticamente una
cache offline: la reapertura web sin red se completara y verificara en la etapa 4.

Las licencias MIT de Drift y de los bindings sqlite3 se incluyen en
`THIRD_PARTY_NOTICES.txt`. El motor SQLite es de
[dominio publico](https://sqlite.org/copyright.html).
