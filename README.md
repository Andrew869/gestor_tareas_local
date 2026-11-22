# Gestor de tareas local

Proyecto Flutter para administrar tareas mediante SQLite local, sin servidor de
datos, MySQL ni API HTTP. El objetivo es compartir el mismo proyecto entre Android,
iOS, Windows, Linux, macOS y web, conservando las tareas entre ejecuciones.

## Estado de la primera etapa

Esta etapa verifica el proyecto inicial y define el almacenamiento. La pantalla
actual incluye controles para agregar, editar, completar y eliminar, pero sus
acciones solo muestran mensajes de operaciones pendientes. La lista esta en
memoria: todavia no hay persistencia ni dependencias SQLite instaladas.

El esquema y la arquitectura siguientes son decisiones de diseno, no funciones
ya implementadas.

## Tecnologia elegida

Se utilizara **Drift sobre SQLite**, con **drift_flutter** para abrir la base en
cada plataforma. Drift no es un servidor: las consultas se ejecutan localmente.

| Paquete previsto | Responsabilidad |
| --- | --- |
| `drift` | Tablas, consultas tipadas, migraciones y consultas reactivas. |
| `drift_flutter` | Apertura de la conexion apropiada para Flutter nativo y web. |
| `drift_dev` | Generacion de codigo a partir del esquema. |
| `build_runner` | Ejecucion del generador durante el desarrollo. |

La eleccion permite reutilizar esquema y operaciones en las seis plataformas,
observar cambios mediante streams y probar la base independientemente de la
interfaz. Ademas, cumple la indicacion existente en
`lib/data/AQUI_IRA_LA_BASE_DE_DATOS.md`.

Las versiones se resolveran al implementar la persistencia y quedaran registradas
en `pubspec.lock`. El codigo generado no se editara manualmente.

### Almacenamiento por plataforma

| Plataformas | Implementacion prevista |
| --- | --- |
| Android, iOS, Windows, Linux y macOS | SQLite nativo en un archivo `tasks.sqlite`, dentro de un directorio persistente de la aplicacion. |
| Web | SQLite WebAssembly, persistido en OPFS o IndexedDB segun las capacidades del navegador. |

En nativo se configurara un directorio de soporte mediante `path_provider`, no
una carpeta temporal ni una ruta relativa al ejecutable. Se respetara el sandbox
de Android, iOS y macOS cuando corresponda.

En web se incluiran `web/sqlite3.wasm` y `web/drift_worker.dart.js`, obtenidos de
una publicacion compatible con la version de Drift resuelta, sin depender de CDN.
La base pertenece al origen del sitio (protocolo, dominio y puerto). Borrar los
datos del sitio o cerrar una sesion privada puede eliminarla. Una conexion solo
en memoria no se considerara persistencia valida.

La carga inicial web requiere servir los archivos de la aplicacion; esto no
equivale a utilizar un servidor de datos. La etapa de compatibilidad configurara
y verificara una cache offline para Flutter, WASM y worker, de modo que se pueda
reabrir sin red. Las operaciones CRUD no utilizaran solicitudes HTTP.

## Esquema de tareas

Nombre de base: `tasks`. Version inicial del esquema: `1`.

| Columna | Tipo SQLite | Restricciones y significado |
| --- | --- | --- |
| `id` | `INTEGER` | Clave primaria autoincremental; identificador unico y estable. |
| `title` | `TEXT` | Obligatorio y no vacio despues de quitar espacios exteriores. |
| `is_completed` | `INTEGER` | Obligatorio; `0` pendiente y `1` completada; inicialmente `0`. |

SQL equivalente al esquema previsto:

```sql
CREATE TABLE tasks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL CHECK (length(trim(title)) > 0),
  is_completed INTEGER NOT NULL DEFAULT 0
    CHECK (is_completed IN (0, 1))
);
```

SQLite asignara el ID al insertar; no se calculara usando el indice de una lista,
el titulo ni la cantidad de registros. `AUTOINCREMENT` evita reutilizar IDs de
registros eliminados, pero no garantiza una secuencia sin huecos. Se permitiran
titulos repetidos: representan tareas distintas por su ID.

Antes de insertar o editar se aplicara `String.trim()` en Dart y se rechazara un
resultado vacio. Esta validacion tambien cubrira espacios que el `trim()` de
SQLite no elimina por defecto. El titulo se guardara normalizado.

Las consultas tendran orden explicito por `id` ascendente. La edicion, el cambio
de estado y la eliminacion filtraran por ID. Los cambios futuros de esquema
requeriran incrementar la version y definir una migracion sin borrar tareas.

## Integracion prevista

- `lib/data/`: esquema, apertura persistente y operaciones asincronas de Drift.
- `lib/main.dart`: composicion de la aplicacion y propiedad de la conexion.
- `lib/screens/tareas_page.dart`: presentacion, entradas y mensajes de error.
- Consulta reactiva creada fuera de `build()` y presentada con `StreamBuilder`.
- Escrituras esperadas con `await`, validacion y errores comprensibles; una
  operacion fallida no se mostrara como exitosa.
- Cierre de la conexion cuando su propietario deje de necesitarla y liberacion
  de controladores y suscripciones.

No se ejecutaran consultas a la base dentro de `build()`. Una lista en memoria
podra representar resultados, pero no sera la fuente persistente de las tareas.

## Ejecucion inicial

Se requiere Flutter compatible con Dart `^3.13.1`, segun `pubspec.yaml`. Para Linux
tambien hacen falta las herramientas de compilacion de escritorio y GTK 3.

```bash
flutter pub get
flutter run -d linux
```

Para ejecutar la base inicial en un navegador con Chrome disponible:

```bash
flutter run -d chrome
```

Si solo esta instalado Chromium puede ser necesario establecer
`CHROME_EXECUTABLE` con su ruta. El comando web no implica que la persistencia ni
el arranque offline esten configurados en esta etapa.

Comprobaciones del proyecto:

```bash
flutter analyze --no-pub
flutter test --no-pub
```

## Resultados de la primera etapa

Entorno: Linux con sesion Wayland, Flutter `3.47.1` (stable), Dart `3.13.1` y
GTK `3.24.52`.

| Comprobacion ejecutada | Resultado |
| --- | --- |
| `flutter analyze --no-pub` | Sin problemas de analisis. |
| `flutter test --no-pub` | Una prueba de widgets aprobada: titulo, boton de alta y campo de texto iniciales. |
| `timeout --signal=INT --kill-after=10s 60s flutter run -d linux --no-pub` | Compilacion debug y arranque correctos, sincronizacion con el dispositivo y servicio de depuracion disponibles. Ejecucion limitada a 60 segundos para la comprobacion. |

El arranque emitio una advertencia de GDK sobre el tema del cursor, sin impedir
la ejecucion. Estas comprobaciones no verifican CRUD ni persistencia porque aun
no estan implementados. Tampoco se han ejecutado web, Android, iOS, Windows o
macOS en esta etapa.

## Etapas siguientes

1. Persistencia real: implementar apertura, alta y consulta; comprobar cierre y
   reapertura sobre la misma base SQLite, no una base en memoria.
2. Operaciones restantes: editar titulo, alternar estado y eliminar por ID, con
   validaciones y mensajes de error.
3. Compatibilidad y pruebas: configurar recursos web y arranque offline, comprobar
   Linux y navegador, agregar pruebas automatizadas y registrar resultados reales.

Para comprobar persistencia se esperara la escritura, se terminara completamente
la aplicacion y se abrira de nuevo. Hot reload no basta: conserva estado en
memoria. Desinstalar o borrar los datos tampoco equivale a un reinicio normal y
puede eliminar la base.

## Referencias

- [Plataformas de Drift](https://drift.simonbinder.eu/platforms/)
- [drift_flutter](https://pub.dev/packages/drift_flutter)
- [Configuracion web de Drift](https://drift.simonbinder.eu/platforms/web/)
- [Publicaciones y recursos de Drift](https://github.com/simolus3/drift/releases)
