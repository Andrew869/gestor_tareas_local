# Capa de datos

La apertura persistente, la tabla `tasks`, el alta y las consultas estan en
`app_database.dart`. Drift genera `app_database.g.dart`, incluido en Git.

Para regenerar el codigo, ejecuta `dart run build_runner build`.
No coloques consultas SQL dentro de `build()`. Las decisiones y las verificaciones
estan documentadas en `README.md`.
