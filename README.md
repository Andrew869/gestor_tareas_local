# Gestor de tareas local

Proyecto Flutter para administrar tareas mediante SQLite local, sin servidor de
datos, MySQL ni API HTTP. El objetivo es compartir el mismo proyecto entre Android,
iOS, Windows, Linux, macOS y web, conservando las tareas entre ejecuciones.

## Estado actual: cuarta etapa

La aplicacion abre una base SQLite persistente, valida y guarda tareas nuevas,
y muestra su titulo, ID y estado mediante una consulta reactiva. La lista se
recupera de SQLite al volver a abrir la aplicacion; no depende de una lista local.
Tambien permite editar titulos, alternar entre pendiente y completada y eliminar
por ID con confirmacion. Estas operaciones se guardan en SQLite y sobreviven al
reinicio. La primera etapa verifico el proyecto inicial y definio el diseno; la
segunda incorporo la apertura persistente, el alta y la consulta.
La cuarta etapa verifica Linux y Chromium y agrega el empaquetado web para
reapertura y operaciones sin red. Las demas plataformas estan contempladas por
la conexion multiplataforma, pero no se declaran probadas en este equipo.

## Tecnologia elegida

Se utiliza **Drift sobre SQLite**, con **drift_flutter** para abrir la base en
cada plataforma. Drift no es un servidor: las consultas se ejecutan localmente.

| Paquete | Responsabilidad |
| --- | --- |
| `drift` | Tablas, consultas tipadas, migraciones y consultas reactivas. |
| `drift_flutter` | Apertura de la conexion apropiada para Flutter nativo y web. |
| `drift_dev` | Generacion de codigo a partir del esquema. |
| `build_runner` | Ejecucion del generador durante el desarrollo. |

La eleccion permite reutilizar esquema y operaciones en las seis plataformas,
observar cambios mediante streams y probar la base independientemente de la
interfaz. Ademas, cumple la indicacion existente en
`lib/data/AQUI_IRA_LA_BASE_DE_DATOS.md`.

Las versiones resueltas estan registradas en `pubspec.lock`: Drift `2.35.4`,
drift_flutter `0.3.1`, drift_dev `2.35.3` y build_runner `2.17.1`.
`app_database.g.dart` se incluye en Git y no se edita manualmente. Despues de
cambiar las tablas, se regenera con:

```bash
dart run build_runner build
```

### Almacenamiento por plataforma

| Plataformas | Implementacion configurada |
| --- | --- |
| Android, iOS, Windows, Linux y macOS | SQLite nativo en un archivo `tasks.sqlite`, dentro de un directorio persistente de la aplicacion. |
| Web | SQLite WebAssembly, persistido en OPFS o IndexedDB segun las capacidades del navegador. |

En nativo se usa `getApplicationSupportDirectory()` de `path_provider`, creando
el directorio si hace falta. No es una carpeta temporal ni una ruta relativa al
ejecutable. Drift ejecuta SQLite en un isolate de segundo plano. Se respeta el
sandbox de Android, iOS y macOS cuando corresponda.

En web se incluyen `web/sqlite3.wasm` y `web/drift_worker.dart.js`, obtenidos de
la publicacion Drift `2.35.4`, sin depender de CDN para SQLite. Las fuentes,
instrucciones de actualizacion y sumas SHA-256 estan en `web/README.md`.
La base pertenece al origen del sitio (protocolo, dominio y puerto). Borrar los
datos del sitio o cerrar una sesion privada puede eliminarla. Una conexion solo
en memoria o una implementacion sin coordinacion segura entre pestanas se
rechazan con un error de almacenamiento.

La carga inicial web requiere servir los archivos de la aplicacion; esto no
equivale a utilizar un servidor de datos. El empaquetado web incluye una cache
offline para Flutter, fuentes, WASM y worker, verificada para reabrir sin red.
Las operaciones CRUD no utilizan solicitudes HTTP.

## Esquema de tareas

Nombre de base: `tasks`. Version inicial del esquema: `1`.

| Columna | Tipo SQLite | Restricciones y significado |
| --- | --- | --- |
| `id` | `INTEGER` | Clave primaria autoincremental; identificador unico y estable. |
| `title` | `TEXT` | Obligatorio y no vacio despues de quitar espacios exteriores. |
| `is_completed` | `INTEGER` | Obligatorio; `0` pendiente y `1` completada; inicialmente `0`. |

SQL equivalente al esquema implementado:

```sql
CREATE TABLE tasks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL CHECK (length(trim(title)) > 0),
  is_completed INTEGER NOT NULL DEFAULT 0
    CHECK (is_completed IN (0, 1))
);
```

SQLite asigna el ID al insertar; no se calcula usando el indice de una lista,
el titulo ni la cantidad de registros. `AUTOINCREMENT` evita reutilizar IDs de
registros eliminados, pero no garantiza una secuencia sin huecos. Se permiten
titulos repetidos: representan tareas distintas por su ID.

Antes de insertar o editar se aplica `String.trim()` en Dart y se rechaza un resultado
vacio, tanto en la pantalla como en la capa de datos. Esto tambien cubre espacios
que el `trim()` de SQLite no elimina por defecto. El titulo se guarda normalizado.

Las consultas tienen orden explicito por `id` ascendente. La edicion, el cambio
de estado y la eliminacion filtran por ID. Los cambios futuros de esquema
requeriran incrementar la version y definir una migracion sin borrar tareas.

## Integracion

- `lib/data/`: esquema, apertura persistente y operaciones asincronas de Drift.
- `lib/main.dart`: composicion de la aplicacion y propiedad de la conexion.
- `lib/screens/tareas_page.dart`: presentacion, entradas y mensajes de error.
- El modelo `Task` generado por Drift reemplaza al modelo inicial `Tarea`, evitando
  duplicar la representacion de cada registro.
- Consulta reactiva creada fuera de `build()` y presentada con `StreamBuilder`.
- Escrituras esperadas con `await`, validacion y errores comprensibles; una
  operacion fallida no se mostrara como exitosa.
- Cierre de la conexion cuando su propietario deje de necesitarla y liberacion
  de controladores y suscripciones.

No se ejecutan consultas a la base dentro de `build()`. El stream se crea en
`initState()`; `StreamBuilder` gestiona su suscripcion. La pantalla distingue
carga, lista vacia y error de lectura. La escritura evita envios duplicados y
conserva el texto introducido si falla. La aplicacion cierra la conexion propia
en `dispose()`; las conexiones inyectadas para pruebas las cierra su propietario.

### Operaciones por ID

- `updateTaskTitle(id, input)`: normaliza y valida el titulo; solo actualiza ese
  campo, conservando el ID y el estado.
- `setTaskCompleted(id, completed)`: guarda el estado solicitado sin modificar
  el titulo ni otros registros.
- `deleteTask(id)`: borra exclusivamente la tarea con ese identificador.

Estas operaciones devuelven la cantidad de filas afectadas. Si es `0`, la interfaz
informa que la tarea ya no existe, en lugar de afirmar que se modifico o elimino.
No se cambia la lista de forma optimista: el stream refleja los resultados de
SQLite. Los titulos duplicados no afectan la seleccion del registro.

El dialogo de edicion permite cancelar sin guardar y mantiene el texto si falla
la escritura. Mientras guarda, bloquea nuevos envios y la salida del dialogo.
La eliminacion requiere confirmacion. Las acciones de una tarea se deshabilitan
mientras haya una operacion o un dialogo pendiente para ese ID, sin bloquear
innecesariamente las demas tareas. Se muestran errores especificos de edicion,
estado y eliminacion; una operacion fallida no se presenta como exitosa.

## Ejecucion

Se requiere Flutter compatible con Dart `^3.13.1`, segun `pubspec.yaml`. Para Linux
tambien hacen falta las herramientas de compilacion de escritorio y GTK 3.

```bash
flutter pub get
flutter run -d linux
```

Para desarrollo web con Chrome disponible, en un puerto distinto al bundle release:

```bash
flutter run -d chrome --web-port=8081
```

Si solo esta instalado Chromium puede ser necesario establecer
`CHROME_EXECUTABLE` con su ruta. Este comando de desarrollo no habilita la cache
offline. Para generar y ejecutar la distribucion web sin dependencias de CDN:

```bash
npm ci --ignore-scripts
npm run build:web
npm run serve:web
```

Requiere Node.js 22 o superior para estas herramientas. Abrir
`http://127.0.0.1:8080/` y esperar **Disponible sin conexion**. Despues se puede
cerrar el navegador y detener el servidor: la misma URL se reabre con el mismo
perfil sin red. El servidor solo entrega archivos estaticos, nunca tareas.
Los detalles de despliegue HTTPS, cabeceras, actualizaciones y subrutas estan en
[`web/README.md`](web/README.md).

El servidor debe servir `.wasm` como `application/wasm`. Al comprobar persistencia
web se debe conservar el mismo origen, incluido el puerto. Borrar los datos del
sitio o cerrar una sesion privada puede eliminar la base y la cache. La persistencia
local no es una copia de seguridad.

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
la ejecucion. En esa primera etapa aun no habia CRUD ni persistencia. Tampoco se
ejecutaron web, Android, iOS, Windows o macOS.

## Resultados de la segunda etapa

Se utilizo el mismo entorno Linux de la primera etapa.

| Comprobacion | Resultado |
| --- | --- |
| `flutter analyze --no-pub` | Sin problemas. |
| `flutter test --no-pub` | 15 pruebas aprobadas: 9 de SQLite sobre archivos reales y 6 de widgets. |
| Integracion Linux, fase `write` | La interfaz guarda una tarea con ID `1` y estado pendiente; termina el proceso. |
| Integracion Linux, fase `read` | Un proceso nuevo recupera la tarea desde la misma base y la muestra con el mismo ID, titulo y estado. |
| Consulta con `sqlite3 -readonly` | Confirma el registro, las restricciones de la tabla y `user_version = 1`. |
| `flutter build web --no-pub --no-web-resources-cdn` | Compilacion correcta, incluidos WASM y worker locales. No demuestra ejecucion ni persistencia en navegador. |

Las pruebas de datos cubren titulos normalizados, IDs distintos y ordenados,
estado inicial, rechazo de entradas vacias, restricciones SQLite, emisiones del
stream y cierre/reapertura del mismo archivo. Las pruebas de widgets cubren
consulta inicial, alta, validacion, mensajes ante fallos de lectura y escritura,
y sustitucion de una conexion inyectada sin cerrar conexiones ajenas.
Solo las pruebas aisladas de widgets usan SQLite en memoria; no se utilizan como
evidencia de persistencia.

### Reproducir el reinicio real en Linux

Ejecutar desde la raiz del proyecto, en la misma terminal y en este orden:

```bash
export TASKS_TEST_DATA="$(mktemp -d)"
XDG_DATA_HOME="$TASKS_TEST_DATA" flutter test integration_test/persistence_test.dart -d linux --no-pub --dart-define=PERSISTENCE_PHASE=write
XDG_DATA_HOME="$TASKS_TEST_DATA" flutter test integration_test/persistence_test.dart -d linux --no-pub --dart-define=PERSISTENCE_PHASE=read
sqlite3 -readonly "$TASKS_TEST_DATA/com.example.gestor_tareas_local/tasks.sqlite" 'SELECT id, title, is_completed FROM tasks;'
```

Cada comando de integracion inicia y termina un proceso nativo independiente con
la conexion de produccion. `XDG_DATA_HOME` aisla el almacenamiento de prueba para
no modificar las tareas del usuario. La fase `write` exige una base vacia y la
fase `read` no inserta nada. Para repetir ambas fases, crear otro directorio con
`mktemp -d`. Los archivos de prueba quedan en ese directorio temporal, fuera de Git.

En la comprobacion realizada, ambas fases pasaron y la consulta devolvio
`1|Stage 2 persistence verification|0`. No se utilizaron hot reload ni hot restart.
La ejecucion y persistencia en navegador, Android, iOS, Windows y macOS siguen
sin verificar en esta etapa.

## Resultados de la tercera etapa

Se conserva `schemaVersion = 1`: no cambiaron las tablas ni sus restricciones,
por lo que no se necesita una migracion y las tareas de la etapa 2 se mantienen.

| Comprobacion | Resultado |
| --- | --- |
| `flutter analyze --no-pub` | Sin problemas. |
| `flutter test --no-pub` | 28 pruebas aprobadas: 13 de SQLite en archivos reales y 15 de widgets. |
| Integracion Linux, fase `modify` | Abre la base creada en la etapa 2, edita la tarea ID `1`, la marca completada y crea y elimina otra tarea ID `2`, usando la interfaz. |
| Integracion Linux, fase `verify` | Otro proceso recupera solo la tarea ID `1`, con titulo editado y estado completado; la tarea ID `2` no reaparece. |
| Consulta con `sqlite3 -readonly` | Devuelve `1\|Stage 3 edited task\|1`, confirma cero filas para ID `2` y `user_version = 1`. |
| `flutter build web --no-pub --no-web-resources-cdn` | Compilacion correcta. La ejecucion real en navegador sigue pendiente de la etapa 4. |

Las pruebas de datos verifican edicion normalizada, rechazo de titulos vacios,
cambio de estado en ambos sentidos, borrado por ID entre titulos duplicados,
IDs inexistentes, proteccion de las otras tareas y notificaciones reactivas de
las tres operaciones. Tras cerrar y reabrir el archivo se comprueba que persisten
el titulo, el estado y el borrado, y que no se reutiliza el ID eliminado.

Las pruebas de interfaz agregadas cubren edicion y cancelacion, validacion,
checkbox, confirmacion y cancelacion del borrado, tarea inexistente y fallos de
almacenamiento en las tres operaciones. Ante un fallo de edicion se conserva el
texto; ante un fallo de estado o borrado se mantiene la representacion anterior.

### Reproducir las operaciones y el reinicio en Linux

Despues de las fases `write` y `read` descritas arriba, ejecutar en la misma
terminal y con el mismo `TASKS_TEST_DATA`:

```bash
XDG_DATA_HOME="$TASKS_TEST_DATA" flutter test integration_test/persistence_test.dart -d linux --no-pub --dart-define=PERSISTENCE_PHASE=modify
XDG_DATA_HOME="$TASKS_TEST_DATA" flutter test integration_test/persistence_test.dart -d linux --no-pub --dart-define=PERSISTENCE_PHASE=verify
sqlite3 -readonly "$TASKS_TEST_DATA/com.example.gestor_tareas_local/tasks.sqlite" 'SELECT id, title, is_completed FROM tasks; SELECT count(*) FROM tasks WHERE id = 2; PRAGMA user_version;'
```

Las fases `modify` y `verify` tambien se ejecutan en procesos independientes. La
segunda solo consulta, sin insertar ni editar registros. Para repetir el ciclo
completo se debe crear un directorio de prueba nuevo y ejecutar las cuatro fases
en orden: `write`, `read`, `modify`, `verify`.

## Resultados de la cuarta etapa

Entorno nativo: Arch Linux, Flutter `3.47.1`, Dart `3.13.1` y sesion Wayland.
Entorno web: Chromium `156.0.8078.79`, Node.js `26.13.0` y Playwright Core `1.65.1`.

| Comprobacion | Resultado |
| --- | --- |
| `flutter analyze --no-pub` | Sin problemas. |
| `flutter test --no-pub` | 29 pruebas aprobadas: 13 de SQLite en archivos reales y 16 de widgets. |
| Integracion Linux | Pasan `write`, `read`, `modify` y `verify` en cuatro procesos independientes y almacenamiento aislado. |
| `flutter build linux --release --no-pub` | Compilacion release correcta; se ejecuta el bundle nativo sobre la misma base de prueba. |
| `npm run build:web` | Bundle release con recursos locales y precache versionada, sin CDN. |
| Pruebas de navegador | Pasan CRUD y dos reaperturas completas, incluyendo cambios offline con el servidor detenido, en OPFS e IndexedDB. |
| Pruebas de actualizacion web | La version nueva espera al cierre de las pestanas, elimina la cache vieja y conserva la tarea; luego reabre offline. |
| Pruebas del service worker | Cuatro pruebas de instalacion fallida, limpieza por scope, lectura desde cache y exclusion de peticiones ajenas. |
| Publicacion en subruta | Tambien se verifica el bundle en `/tasks/`, con rutas relativas y cache del scope correctas. |
| Pantalla movil simulada | A 320x640, con titulos largos y teclado visible: sin overflow, con edicion, cambio de estado y eliminacion accesibles. No equivale a ejecutar Android o iOS. |

El ciclo web usa perfiles temporales de Chromium, sin datos previos. La primera
sesion guarda, edita, completa y elimina tareas. Despues se cierran navegador y
servidor, se reabre con la red deshabilitada y se comprueban los registros. En esa
sesion se crea, edita, pasa a pendiente y elimina sin red; otra reapertura offline
verifica el resultado. Se confirma la base `tasks` en OPFS o IndexedDB, se detectan
errores JavaScript y se exige que no haya solicitudes externas ni peticiones al
servidor durante el CRUD. Las mismas pruebas se ejecutan con y sin COOP/COEP.

Para repetir las siete pruebas web (cuatro unitarias y tres de navegador):

```bash
npm ci --ignore-scripts
npm run build:web
CHROME_EXECUTABLE=/usr/bin/chromium npm run test:web
```

Para repetir el ciclo nativo completo, crear otro `TASKS_TEST_DATA` y ejecutar
las cuatro fases descritas arriba en orden. El arranque release se comprobo con
un limite de 12 segundos; persiste la advertencia no bloqueante del cursor de GDK
ya observada en la primera etapa.

### Matriz de compatibilidad

| Plataforma | Diseno de persistencia | Verificacion realizada |
| --- | --- | --- |
| Android | SQLite nativo en soporte privado de la aplicacion. | No ejecutado; no hay dispositivo conectado y el SDK local tiene licencias pendientes de verificar. |
| iOS | SQLite nativo en el sandbox. | No ejecutado; requiere macOS y Xcode. |
| Windows | SQLite nativo en soporte de la aplicacion. | No ejecutado; requiere entorno Windows. |
| Linux | SQLite nativo en soporte de la aplicacion. | CRUD, reinicios independientes y build/arranque release verificados. |
| macOS | SQLite nativo en soporte de la aplicacion. | No ejecutado; requiere macOS y Xcode. |
| Web | SQLite WASM en OPFS o IndexedDB. | Chromium: CRUD, persistencia y reapertura offline, raiz y subruta; con y sin aislamiento. |

Firefox, Safari, navegadores moviles y el modo privado no se han ejecutado. La
compatibilidad de Drift no sustituye pruebas en esos entornos. El navegador puede
restringir o desalojar almacenamiento; si Drift solo ofrece memoria o IndexedDB
sin coordinacion segura, la aplicacion informa un error en vez de prometer
persistencia. Los glifos no incluidos en las fuentes locales pueden no mostrarse,
aunque SQLite conserva el titulo Unicode completo.

Para comprobar persistencia se esperara la escritura, se terminara completamente
la aplicacion y se abrira de nuevo. Hot reload no basta: conserva estado en
memoria. Desinstalar o borrar los datos tampoco equivale a un reinicio normal y
puede eliminar la base.

## Referencias

- [Plataformas de Drift](https://drift.simonbinder.eu/platforms/)
- [drift_flutter](https://pub.dev/packages/drift_flutter)
- [Configuracion web de Drift](https://drift.simonbinder.eu/platforms/web/)
- [Publicaciones y recursos de Drift](https://github.com/simolus3/drift/releases)
