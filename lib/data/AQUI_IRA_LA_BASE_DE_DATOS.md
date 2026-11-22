# Capa de datos

La apertura persistente, la tabla `tasks` y las operaciones CRUD estan en
`app_database.dart`. La edicion, el estado y el borrado filtran por ID y devuelven
la cantidad de filas afectadas. Drift genera `app_database.g.dart`, incluido en Git.

Para regenerar el codigo, ejecuta `dart run build_runner build`.
No coloques consultas SQL dentro de `build()`. Las decisiones y las verificaciones
estan documentadas en `README.md`.
