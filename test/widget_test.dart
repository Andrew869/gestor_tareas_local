import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_tareas_local/data/app_database.dart';
import 'package:gestor_tareas_local/main.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  testWidgets('Initial screen reads an empty database', (tester) async {
    await tester.pumpWidget(GestorTareasApp(database: database));
    await tester.pumpAndSettle();
    expect(find.text('Gestor de tareas'), findsOneWidget);
    expect(find.text('Agregar tarea'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Todavía no hay tareas guardadas'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('Saving a task updates the reactive list and database', (
    tester,
  ) async {
    await tester.pumpWidget(GestorTareasApp(database: database));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '  Read a book  ');
    await tester.tap(find.text('Agregar tarea'));
    await tester.pumpAndSettle();

    expect(find.text('Read a book'), findsOneWidget);
    expect(find.textContaining('Pendiente'), findsOneWidget);
    expect((await database.getTasks()).single.title, 'Read a book');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('Whitespace-only titles are rejected', (tester) async {
    await tester.pumpWidget(GestorTareasApp(database: database));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('Agregar tarea'));
    await tester.pumpAndSettle();

    expect(find.text('Escribe un título que no esté vacío.'), findsOneWidget);
    expect(await database.getTasks(), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('Read errors suggest reopening the application', (tester) async {
    await database.getTasks();
    await database.customStatement('DROP TABLE tasks');
    await tester.pumpWidget(GestorTareasApp(database: database));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('No se pudieron leer las tareas.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('vuelve a abrir la aplicación.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('Write failures keep the entered title and show an error', (
    tester,
  ) async {
    await tester.pumpWidget(GestorTareasApp(database: database));
    await tester.pumpAndSettle();
    await database.customStatement('DROP TABLE tasks');
    await tester.enterText(find.byType(TextField), 'Keep this title');
    await tester.tap(find.text('Agregar tarea'));
    await tester.pumpAndSettle();

    expect(
      find.text('No se pudo guardar la tarea. Inténtalo de nuevo.'),
      findsOneWidget,
    );
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Keep this title',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('Replacing an injected database switches the task subscription', (
    tester,
  ) async {
    // These instances use independent in-memory SQLite executors.
    final previousWarningSetting =
        driftRuntimeOptions.dontWarnAboutMultipleDatabases;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    addTearDown(() {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases =
          previousWarningSetting;
    });
    final replacement = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(replacement.close);
    await database.createTask('Original task');
    await replacement.createTask('Replacement task');
    await tester.pumpWidget(GestorTareasApp(database: database));
    await tester.pumpAndSettle();
    expect(find.text('Original task'), findsOneWidget);

    await tester.pumpWidget(GestorTareasApp(database: replacement));
    await tester.pumpAndSettle();
    expect(find.text('Replacement task'), findsOneWidget);
    expect(find.text('Original task'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect((await database.getTasks()).single.title, 'Original task');
    expect((await replacement.getTasks()).single.title, 'Replacement task');
  });
}
