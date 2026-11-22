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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo guardar la tarea. Inténtalo de nuevo.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
                      return Card(
                        key: ValueKey(task.id),
                        child: ListTile(
                          leading: Checkbox(
                            value: task.isCompleted,
                            onChanged: null,
                          ),
                          title: Text(task.title),
                          subtitle: Text(
                            'ID: ${task.id} · '
                            '${task.isCompleted ? 'Completada' : 'Pendiente'}',
                          ),
                          trailing: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Editar (próxima etapa)',
                                icon: Icon(Icons.edit),
                                onPressed: null,
                              ),
                              IconButton(
                                tooltip: 'Eliminar (próxima etapa)',
                                icon: Icon(Icons.delete_outline),
                                onPressed: null,
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
