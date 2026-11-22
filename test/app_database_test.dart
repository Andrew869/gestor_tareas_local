import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_tareas_local/data/app_database.dart';

Future<void> withDatabase(
  Future<void> Function(AppDatabase database) run,
) async {
  final directory = await Directory.systemTemp.createTemp('app_database_test_');
  try {
    final database = AppDatabase.forTesting(
      NativeDatabase(File('${directory.path}/tasks.sqlite')),
    );
    try {
      await run(database);
    } finally {
      await database.close();
    }
  } finally {
    await directory.delete(recursive: true);
  }
}

void main() {
  test(
    'creates normalized tasks with distinct ordered IDs and false state',
    () {
      return withDatabase((database) async {
        expect(await database.getTasks(), isEmpty);

        final firstId = await database.createTask('  Zebra task \t\n');
        final secondId = await database.createTask('\t Alpha task  \n');
        final thirdId = await database.createTask('  Keep  inner spaces  ');
        final tasks = await database.getTasks();

        expect({firstId, secondId, thirdId}, hasLength(3));
        expect(firstId, greaterThan(0));
        expect(firstId, lessThan(secondId));
        expect(secondId, lessThan(thirdId));
        expect(tasks.map((task) => task.id), [firstId, secondId, thirdId]);
        expect(tasks.map((task) => task.title), [
          'Zebra task',
          'Alpha task',
          'Keep  inner spaces',
        ]);
        expect(tasks.map((task) => task.isCompleted), everyElement(isFalse));
      });
    },
  );

  for (final title in ['', '   ', '\t\n']) {
    test('rejects ${title.codeUnits} synchronously without inserting', () {
      return withDatabase((database) async {
        expect(() => database.createTask(title), throwsArgumentError);
        expect(await database.getTasks(), isEmpty);
      });
    });
  }

  test('normalizes edits while preserving IDs, state and other tasks', () {
    return withDatabase((database) async {
      final id = await database.createTask('Original title');
      await database.setTaskCompleted(id, true);
      await database.createTask('Other task');
      final originalTasks = await database.getTasks();

      expect(await database.updateTaskTitle(id, '\t Edited  title \n'), 1);
      final tasks = await database.getTasks();
      expect(tasks, [
        originalTasks.first.copyWith(title: 'Edited  title'),
        originalTasks.last,
      ]);

      for (final title in ['', '   ', '\t\n']) {
        expect(() => database.updateTaskTitle(id, title), throwsArgumentError);
        expect(await database.getTasks(), tasks);
      }
    });
  });

  test('toggles completion without changing titles or another task', () {
    return withDatabase((database) async {
      final id = await database.createTask('Task to toggle');
      await database.createTask('Other task');
      final originalTasks = await database.getTasks();

      for (final completed in [true, false]) {
        expect(await database.setTaskCompleted(id, completed), 1);
        expect(await database.getTasks(), [
          originalTasks.first.copyWith(isCompleted: completed),
          originalTasks.last,
        ]);
      }
    });
  });

  test('deletes only the requested ID among duplicate titles', () {
    return withDatabase((database) async {
      await database.createTask('Duplicate title');
      final id = await database.createTask('Duplicate title');
      final originalTasks = await database.getTasks();

      expect(await database.deleteTask(id), 1);
      expect(await database.getTasks(), [originalTasks.first]);
    });
  });

  test('missing IDs return zero without modifying existing tasks', () {
    return withDatabase((database) async {
      final id = await database.createTask('First task');
      final lastId = await database.createTask('Second task');
      await database.setTaskCompleted(id, true);
      final originalTasks = await database.getTasks();
      final missingId = lastId + 1;

      expect(await database.updateTaskTitle(missingId, 'Changed title'), 0);
      expect(await database.getTasks(), originalTasks);
      expect(await database.setTaskCompleted(missingId, true), 0);
      expect(await database.getTasks(), originalTasks);
      expect(await database.deleteTask(missingId), 0);
      expect(await database.getTasks(), originalTasks);
    });
  });

  test(
    'persists edits, completion and deletion without reusing the deleted ID',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'app_database_test_',
      );
      try {
        final file = File('${directory.path}/tasks.sqlite');
        late List<Task> originalTasks;
        late int deletedId;
        final database = AppDatabase.forTesting(NativeDatabase(file));
        try {
          final id = await database.createTask('  First task  ');
          deletedId = await database.createTask('\tSecond task\n');
          expect(await database.updateTaskTitle(id, '  Edited task  '), 1);
          expect(await database.setTaskCompleted(id, true), 1);
          expect(await database.deleteTask(deletedId), 1);
          originalTasks = await database.getTasks();
          expect(originalTasks, [
            Task(id: id, title: 'Edited task', isCompleted: true),
          ]);
        } finally {
          await database.close();
        }

        expect(await file.exists(), isTrue);
        final reopenedDatabase = AppDatabase.forTesting(NativeDatabase(file));
        try {
          expect(await reopenedDatabase.getTasks(), originalTasks);
          final newId = await reopenedDatabase.createTask('New task');
          expect(newId, greaterThan(deletedId));
          expect(await reopenedDatabase.getTasks(), [
            ...originalTasks,
            Task(id: newId, title: 'New task', isCompleted: false),
          ]);
        } finally {
          await reopenedDatabase.close();
        }
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );

  test('watchTasks emits insertion, edits, completion and deletion', () {
    return withDatabase((database) async {
      final subscription = StreamIterator(database.watchTasks());
      try {
        expect(await subscription.moveNext(), isTrue);
        expect(subscription.current, isEmpty);

        final insertion = expectLater(
          subscription.moveNext(),
          completion(isTrue),
        );
        final id = await database.createTask('  Stream task  ');
        await insertion;
        expect(subscription.current, [
          Task(id: id, title: 'Stream task', isCompleted: false),
        ]);

        final edit = expectLater(subscription.moveNext(), completion(isTrue));
        await database.updateTaskTitle(id, '  Edited stream task  ');
        await edit;
        expect(subscription.current, [
          Task(id: id, title: 'Edited stream task', isCompleted: false),
        ]);

        final completionUpdate = expectLater(
          subscription.moveNext(),
          completion(isTrue),
        );
        await database.setTaskCompleted(id, true);
        await completionUpdate;
        expect(subscription.current, [
          Task(id: id, title: 'Edited stream task', isCompleted: true),
        ]);

        final deletion = expectLater(
          subscription.moveNext(),
          completion(isTrue),
        );
        await database.deleteTask(id);
        await deletion;
        expect(subscription.current, isEmpty);
      } finally {
        await subscription.cancel();
      }
    });
  });

  for (final title in ['', '   ']) {
    test('SQLite rejects title ${title.codeUnits} through direct SQL', () {
      return withDatabase((database) async {
        await expectLater(
          database.customStatement('INSERT INTO tasks (title) VALUES (?)', [
            title,
          ]),
          throwsA(
            isA<SqliteException>().having(
              (error) => error.resultCode,
              'SQLITE_CONSTRAINT',
              19,
            ),
          ),
        );
        expect(await database.getTasks(), isEmpty);
      });
    });
  }

  test('SQLite rejects an invalid is_completed value through direct SQL', () {
    return withDatabase((database) async {
      await expectLater(
        database.customStatement(
          'INSERT INTO tasks (title, is_completed) VALUES (?, ?)',
          ['Valid title', 2],
        ),
        throwsA(
          isA<SqliteException>().having(
            (error) => error.resultCode,
            'SQLITE_CONSTRAINT',
            19,
          ),
        ),
      );
      expect(await database.getTasks(), isEmpty);
    });
  });
}
