import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'project.dart';
import 'project_repository.dart';

enum SaveState { saved, pending, saving, failed }

class ProjectAutosave extends ChangeNotifier {
  ProjectAutosave({
    required this.repository,
    required this.capture,
    this.delay = const Duration(milliseconds: 700),
    this.onSaved,
  });
  final ProjectRepository repository;
  final LocalProject Function() capture;
  final Duration delay;
  final ValueChanged<LocalProject>? onSaved;
  SaveState state = SaveState.saved;
  String? error;
  Timer? _timer;
  int _revision = 0, _saved = 0;
  bool _disposed = false;
  Future<void> _tail = Future.value();
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void schedule() {
    if (_disposed) return;
    _revision++;
    state = SaveState.pending;
    _timer?.cancel();
    _timer = Timer(delay, () {
      flush().catchError((Object _) {});
    });
    _notify();
  }

  Future<void> flush() {
    _timer?.cancel();
    if (_saved == _revision) return _tail;
    final revision = _revision, snapshot = capture();
    final task = _tail.catchError((Object _) {}).then((_) async {
      state = SaveState.saving;
      error = null;
      _notify();
      try {
        await repository.save(snapshot);
        _saved = revision;
        if (!_disposed) onSaved?.call(snapshot);
        state = _saved == _revision ? SaveState.saved : SaveState.pending;
      } catch (e) {
        state = SaveState.failed;
        error = e is FileSystemException
            ? 'Could not save. Free storage and retry.'
            : e is StateError
            ? e.message.toString()
            : e is FormatException
            ? e.message
            : 'Could not save this project. Retry before leaving.';
        rethrow;
      } finally {
        _notify();
      }
    });
    _tail = task;
    return task;
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
