import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_tareas_local/data/app_database.dart';
import 'package:gestor_tareas_local/main.dart';

void main() {
  late AppDatabase database;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    await database.createTask('Original task');
    await database.createTask('Other task');
  });

  tearDown(() => database.close());

  Finder taskAction(int id, Finder action) {
    return find.descendant(of: find.byKey(ValueKey(id)), matching: action);
  }

  Future<void> withApp(
    WidgetTester tester,
    Future<void> Function() action,
  ) async {
    await tester.pumpWidget(GestorTareasApp(database: database));
    await tester.pumpAndSettle();
    try {
      await action();
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  }

  testWidgets('Editing updates only the title and preserves ID and state', (
    tester,
  ) async {
    await database.setTaskCompleted(1, true);
    await withApp(tester, () async {
      await tester.tap(taskAction(1, find.byTooltip('Editar')));
      await tester.pumpAndSettle();
      expect(find.text('Editar tarea'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), '  Updated title  ');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Updated title'), findsOneWidget);
      expect(find.text('Original task'), findsNothing);
      final tasks = await database.getTasks();
      expect(tasks.first.id, 1);
      expect(tasks.first.title, 'Updated title');
      expect(tasks.first.isCompleted, isTrue);
      expect(tasks.last.title, 'Other task');
    });
  });

  testWidgets('Invalid edited titles keep the dialog open and preserve data', (
    tester,
  ) async {
    await withApp(tester, () async {
      await tester.tap(taskAction(1, find.byTooltip('Editar')));
      await tester.pumpAndSettle();
      for (final title in ['', '   ', '\t\n']) {
        await tester.enterText(find.byType(TextFormField), title);
        await tester.tap(find.text('Guardar'));
        await tester.pumpAndSettle();
        expect(
          find.text('Escribe un título que no esté vacío.'),
          findsOneWidget,
        );
        expect(find.byType(AlertDialog), findsOneWidget);
        expect((await database.getTasks()).first.title, 'Original task');
      }
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
    });
  });

  testWidgets('Cancelling an edit does not write to SQLite', (tester) async {
    await withApp(tester, () async {
      await tester.tap(taskAction(1, find.byTooltip('Editar')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Discarded title');
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Original task'), findsOneWidget);
      expect((await database.getTasks()).first.title, 'Original task');
    });
  });

  testWidgets('Checkbox persists both completed and pending states', (
    tester,
  ) async {
    await withApp(tester, () async {
      final checkbox = taskAction(1, find.byType(Checkbox));
      for (final completed in [true, false]) {
        await tester.tap(checkbox);
        await tester.pumpAndSettle();
        expect(tester.widget<Checkbox>(checkbox).value, completed);
        final tasks = await database.getTasks();
        expect(tasks.first.isCompleted, completed);
        expect(tasks.first.title, 'Original task');
        expect(tasks.last.isCompleted, isFalse);
      }
    });
  });

  testWidgets('Delete confirmation removes only the chosen ID', (tester) async {
    await database.updateTaskTitle(2, 'Original task');
    await withApp(tester, () async {
      await tester.tap(taskAction(1, find.byTooltip('Eliminar')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(await database.getTasks(), hasLength(2));

      await tester.tap(taskAction(1, find.byTooltip('Eliminar')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey(1)), findsNothing);
      expect(find.byKey(const ValueKey(2)), findsOneWidget);
      expect((await database.getTasks()).single.id, 2);
    });
  });

  testWidgets('Edit failures preserve entered text and allow cancellation', (
    tester,
  ) async {
    await withApp(tester, () async {
      await tester.tap(taskAction(1, find.byTooltip('Editar')));
      await tester.pumpAndSettle();
      await database.customStatement('DROP TABLE tasks');
      await tester.enterText(find.byType(TextFormField), 'Keep this edit');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text('No se pudo editar la tarea. Inténtalo de nuevo.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        'Keep this edit',
      );
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  testWidgets('Failed status changes do not change the displayed state', (
    tester,
  ) async {
    await withApp(tester, () async {
      await database.customStatement('DROP TABLE tasks');
      final checkbox = taskAction(1, find.byType(Checkbox));
      await tester.tap(checkbox);
      await tester.pumpAndSettle();

      expect(tester.widget<Checkbox>(checkbox).value, isFalse);
      expect(tester.widget<Checkbox>(checkbox).onChanged, isNotNull);
      expect(
        find.text('No se pudo cambiar el estado. Inténtalo de nuevo.'),
        findsOneWidget,
      );
    });
  });

  testWidgets('Failed deletion keeps the task visible and reports the error', (
    tester,
  ) async {
    await withApp(tester, () async {
      await database.customStatement('DROP TABLE tasks');
      await tester.tap(taskAction(1, find.byTooltip('Eliminar')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey(1)), findsOneWidget);
      expect(
        find.text('No se pudo eliminar la tarea. Inténtalo de nuevo.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<IconButton>(
              taskAction(
                1,
                find.byWidgetPredicate(
                  (widget) =>
                      widget is IconButton && widget.tooltip == 'Eliminar',
                ),
              ),
            )
            .onPressed,
        isNotNull,
      );
    });
  });

  testWidgets('An absent task is reported instead of claiming edit success', (
    tester,
  ) async {
    await withApp(tester, () async {
      await tester.tap(taskAction(1, find.byTooltip('Editar')));
      await tester.pumpAndSettle();
      await database.customStatement('DELETE FROM tasks WHERE id = 1');
      await tester.enterText(find.byType(TextFormField), 'No longer present');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Esta tarea ya no existe.'), findsOneWidget);
      expect((await database.getTasks()).single.id, 2);
    });
  });
}
