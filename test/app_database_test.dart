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

  test(
    'preserves IDs, titles and state after reopening the same file',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'app_database_test_',
      );
      try {
        final file = File('${directory.path}/tasks.sqlite');
        late List<Task> originalTasks;
        final database = AppDatabase.forTesting(NativeDatabase(file));
        try {
          await database.createTask('  First task  ');
          await database.createTask('\tSecond task\n');
          originalTasks = await database.getTasks();
          expect(originalTasks, hasLength(2));
        } finally {
          await database.close();
        }

        expect(await file.exists(), isTrue);
        final reopenedDatabase = AppDatabase.forTesting(NativeDatabase(file));
        try {
          expect(await reopenedDatabase.getTasks(), originalTasks);
        } finally {
          await reopenedDatabase.close();
        }
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );

  test('watchTasks emits the inserted task after subscribing', () {
    return withDatabase((database) async {
      await expectLater(database.watchTasks(), emits(isEmpty));

      final update = expectLater(
        database.watchTasks(),
        emitsThrough(
          isA<List<Task>>()
              .having((tasks) => tasks.length, 'length', 1)
              .having((tasks) => tasks.single.id, 'ID', greaterThan(0))
              .having((tasks) => tasks.single.title, 'title', 'Stream task')
              .having((tasks) => tasks.single.isCompleted, 'state', isFalse),
        ),
      );

      await database.createTask('  Stream task  ');
      await update;
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
