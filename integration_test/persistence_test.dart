import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_tareas_local/data/app_database.dart';
import 'package:gestor_tareas_local/main.dart';
import 'package:integration_test/integration_test.dart';

// Run write and read in separate processes with the same isolated XDG_DATA_HOME.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const phase = String.fromEnvironment('PERSISTENCE_PHASE');
  const title = 'Stage 2 persistence verification';
  const editedTitle = 'Stage 3 edited task';
  const deletedTitle = 'Stage 3 deleted task';

  testWidgets('Persistent task survives a complete app restart ($phase)', (
    tester,
  ) async {
    expect(phase, anyOf('write', 'read', 'modify', 'verify'));
    final database = AppDatabase();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await database.close();
    });

    await tester.pumpWidget(GestorTareasApp(database: database));
    await tester.pumpAndSettle();

    if (phase == 'write') {
      expect(await database.getTasks(), isEmpty);
      await tester.enterText(find.byType(TextField), title);
      await tester.tap(find.text('Agregar tarea'));
      await tester.pumpAndSettle();
    }

    if (phase == 'modify') {
      expect(find.text(title), findsOneWidget);
      await tester.enterText(find.byType(TextField), deletedTitle);
      await tester.tap(find.text('Agregar tarea'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey(1)),
          matching: find.byTooltip('Editar'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), editedTitle);
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey(1)),
          matching: find.byType(Checkbox),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey(2)),
          matching: find.byTooltip('Eliminar'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
      await tester.pumpAndSettle();
    }

    final modified = phase == 'modify' || phase == 'verify';
    expect(find.text(modified ? editedTitle : title), findsOneWidget);
    expect(
      find.textContaining(modified ? 'Completada' : 'Pendiente'),
      findsOneWidget,
    );
    expect(find.text(deletedTitle), findsNothing);
    final task = (await database.getTasks()).single;
    expect(task.id, 1);
    expect(task.title, modified ? editedTitle : title);
    expect(task.isCompleted, modified);
  });
}
