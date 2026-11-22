import 'dart:async';

import 'package:flutter/material.dart';

import 'data/app_database.dart';
import 'screens/tareas_page.dart';

void main() {
  runApp(const GestorTareasApp());
}

class GestorTareasApp extends StatefulWidget {
  const GestorTareasApp({super.key, this.database});

  // Injected databases remain owned by the caller.
  final AppDatabase? database;

  @override
  State<GestorTareasApp> createState() => _GestorTareasAppState();
}

class _GestorTareasAppState extends State<GestorTareasApp> {
  late AppDatabase _database;
  late bool _ownsDatabase;

  @override
  void initState() {
    super.initState();
    _database = widget.database ?? AppDatabase();
    _ownsDatabase = widget.database == null;
  }

  @override
  void didUpdateWidget(covariant GestorTareasApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.database != widget.database) {
      _closeOwnedDatabase();
      _database = widget.database ?? AppDatabase();
      _ownsDatabase = widget.database == null;
    }
  }

  void _closeOwnedDatabase() {
    if (_ownsDatabase) {
      unawaited(
        _database.close().catchError((Object error, StackTrace stack) {
          FlutterError.reportError(
            FlutterErrorDetails(exception: error, stack: stack),
          );
        }),
      );
    }
  }

  @override
  void dispose() {
    _closeOwnedDatabase();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gestor de tareas',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: TareasPage(key: ObjectKey(_database), database: _database),
    );
  }
}
