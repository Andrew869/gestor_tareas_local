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

  testWidgets('Persistent task survives a complete app restart ($phase)', (
    tester,
  ) async {
    expect(phase, anyOf('write', 'read'));
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

    expect(find.text(title), findsOneWidget);
    expect(find.textContaining('Pendiente'), findsOneWidget);
    final task = (await database.getTasks()).single;
    expect(task.id, 1);
    expect(task.title, title);
    expect(task.isCompleted, isFalse);
  });
}
