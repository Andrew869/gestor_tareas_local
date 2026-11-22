import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

class Tasks extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get title =>
      text().customConstraint('NOT NULL CHECK (length(trim(title)) > 0)')();

  BoolColumn get isCompleted => boolean().withDefault(const Constant(false))();
}

@DriftDatabase(tables: [Tasks])
class AppDatabase extends _$AppDatabase {
  AppDatabase()
    : super(
        driftDatabase(
          name: 'tasks',
          native: DriftNativeOptions(
            databaseDirectory: () async {
              final directory = await getApplicationSupportDirectory();
              await directory.create(recursive: true);
              return directory;
            },
          ),
          web: DriftWebOptions(
            sqlite3Wasm: Uri.parse('sqlite3.wasm'),
            driftWorker: Uri.parse('drift_worker.dart.js'),
            onResult: (result) {
              if (result.chosenImplementation ==
                      WasmStorageImplementation.inMemory ||
                  result.chosenImplementation ==
                      WasmStorageImplementation.unsafeIndexedDb) {
                unawaited(result.resolvedExecutor.close());
                throw StateError('Reliable browser storage is unavailable.');
              }
            },
          ),
        ),
      );

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  Future<int> createTask(String input) {
    final title = input.trim();
    if (title.isEmpty) {
      throw ArgumentError('Task title must not be empty.');
    }

    return into(tasks).insert(TasksCompanion.insert(title: title));
  }

  Future<List<Task>> getTasks() => _orderedTasks().get();

  Stream<List<Task>> watchTasks() => _orderedTasks().watch();

  SimpleSelectStatement<Tasks, Task> _orderedTasks() {
    return select(tasks)..orderBy([(task) => OrderingTerm.asc(task.id)]);
  }
}
