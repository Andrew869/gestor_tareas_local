import 'package:flutter/material.dart';

import '../data/app_database.dart';

class TareasPage extends StatefulWidget {
  const TareasPage({super.key, required this.database});

  final AppDatabase database;

  @override
  State<TareasPage> createState() => _TareasPageState();
}

class _TareasPageState extends State<TareasPage> {
  final TextEditingController _titleController = TextEditingController();
  final Set<int> _busyTaskIds = {};
  late final Stream<List<Task>> _tasks;
  bool _saving = false;
  String? _titleError;

  @override
  void initState() {
    super.initState();
    _tasks = widget.database.watchTasks();
  }

  Future<void> _addTask() async {
    if (_saving) return;
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = 'Escribe un título que no esté vacío.');
      return;
    }

    setState(() {
      _saving = true;
      _titleError = null;
    });
    try {
      await widget.database.createTask(title);
      if (!mounted) return;
      _titleController.clear();
    } catch (_) {
      if (!mounted) return;
      _showMessage('No se pudo guardar la tarea. Inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _runTaskAction(
    int id,
    Future<int?> Function() action,
    String errorMessage,
  ) async {
    if (_busyTaskIds.contains(id)) return;
    setState(() => _busyTaskIds.add(id));
    try {
      final affectedRows = await action();
      if (!mounted) return;
      if (affectedRows == 0) {
        _showMessage('Esta tarea ya no existe.');
      }
    } catch (_) {
      if (mounted) _showMessage(errorMessage);
    } finally {
      if (mounted) setState(() => _busyTaskIds.remove(id));
    }
  }

  Future<void> _editTask(Task task) {
    return _runTaskAction(
      task.id,
      () => showDialog<int>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _EditTaskDialog(database: widget.database, task: task),
      ),
      'No se pudo editar la tarea. Inténtalo de nuevo.',
    );
  }

  Future<void> _deleteTask(Task task) {
    return _runTaskAction(task.id, () async {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          scrollable: true,
          title: const Text('Eliminar tarea'),
          content: Text('¿Quieres eliminar "${task.title}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Eliminar'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return null;
      return widget.database.deleteTask(task.id);
    }, 'No se pudo eliminar la tarea. Inténtalo de nuevo.');
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gestor de tareas')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _titleController,
              enabled: !_saving,
              onSubmitted: (_) => _addTask(),
              decoration: InputDecoration(
                labelText: 'Nueva tarea',
                border: const OutlineInputBorder(),
                errorText: _titleError,
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _saving ? null : _addTask,
              icon: const Icon(Icons.add),
              label: Text(_saving ? 'Guardando...' : 'Agregar tarea'),
            ),
            const SizedBox(height: 12),
            const Text('Mis tareas', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 8),
            Expanded(
              child: StreamBuilder<List<Task>>(
                stream: _tasks,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Center(
                      child: Text(
                        'No se pudieron leer las tareas. Comprueba que el '
                        'almacenamiento esté disponible y vuelve a abrir '
                        'la aplicación.',
                        textAlign: TextAlign.center,
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final tasks = snapshot.requireData;
                  if (tasks.isEmpty) {
                    return const Center(
                      child: Text('Todavía no hay tareas guardadas'),
                    );
                  }
                  return ListView.builder(
                    itemCount: tasks.length,
                    itemBuilder: (context, index) {
                      final task = tasks[index];
                      final busy = _busyTaskIds.contains(task.id);
                      return Card(
                        key: ValueKey(task.id),
                        child: ListTile(
                          leading: Checkbox(
                            value: task.isCompleted,
                            semanticLabel: task.isCompleted
                                ? 'Marcar como pendiente'
                                : 'Marcar como completada',
                            onChanged: busy
                                ? null
                                : (value) {
                                    if (value == null) return;
                                    _runTaskAction(
                                      task.id,
                                      () => widget.database.setTaskCompleted(
                                        task.id,
                                        value,
                                      ),
                                      'No se pudo cambiar el estado. '
                                      'Inténtalo de nuevo.',
                                    );
                                  },
                          ),
                          title: Text(task.title),
                          subtitle: Text(
                            'ID: ${task.id} · '
                            '${task.isCompleted ? 'Completada' : 'Pendiente'}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Editar',
                                icon: const Icon(Icons.edit),
                                onPressed: busy ? null : () => _editTask(task),
                              ),
                              IconButton(
                                tooltip: 'Eliminar',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: busy
                                    ? null
                                    : () => _deleteTask(task),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditTaskDialog extends StatefulWidget {
  const _EditTaskDialog({required this.database, required this.task});

  final AppDatabase database;
  final Task task;

  @override
  State<_EditTaskDialog> createState() => _EditTaskDialogState();
}

class _EditTaskDialogState extends State<_EditTaskDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;
  bool _saving = false;
  String? _storageError;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.task.title);
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _storageError = null;
    });
    try {
      final affectedRows = await widget.database.updateTaskTitle(
        widget.task.id,
        _controller.text,
      );
      if (mounted) Navigator.pop(context, affectedRows);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _storageError = 'No se pudo editar la tarea. Inténtalo de nuevo.';
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: const Text('Editar tarea'),
        content: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _controller,
                autofocus: true,
                enabled: !_saving,
                decoration: const InputDecoration(labelText: 'Título'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Escribe un título que no esté vacío.'
                    : null,
                onFieldSubmitted: (_) => _save(),
              ),
              if (_storageError != null) ...[
                const SizedBox(height: 12),
                Text(_storageError!),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Guardando...' : 'Guardar'),
          ),
        ],
      ),
    );
  }
}
