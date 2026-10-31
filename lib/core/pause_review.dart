import 'package:flutter/foundation.dart';
import 'edit_plan.dart';
import 'silence_detection.dart';

enum PauseDecision { keep, trim }

enum PauseFilter { all, unreviewed, trim, keep }

enum PauseOrder { timeline, longest }

String pauseId(EditRange range) => '${range.startMs}:${range.endMs}';

/// Review decisions are separate from edits. Only the explicit Add action
/// submits the chosen cuts to the editor's existing plan validation.
class PauseReviewSession extends ChangeNotifier {
  List<EditRange> _pauses = [];
  SilenceSettings settings = const SilenceSettings();
  final Map<String, PauseDecision> _decisions = {};
  final List<Map<String, PauseDecision>> _history = [];
  List<EditRange> get pauses => List.unmodifiable(_pauses);
  PauseDecision? decision(EditRange pause) => _decisions[pauseId(pause)];
  List<EditRange> get trims =>
      _pauses.where((p) => decision(p) == PauseDecision.trim).toList();
  int get reviewed => _pauses.where((p) => decision(p) != null).length;
  bool get canUndo => _history.isNotEmpty;
  String? _lastVisitedId;
  String? get lastVisitedId => _lastVisitedId;
  set lastVisitedId(String? value) {
    if (_lastVisitedId == value) return;
    _lastVisitedId = value;
    notifyListeners();
  }

  Map<String, dynamic> toMap() => {
    'settings': {
      'thresholdDb': settings.thresholdDb,
      'minimumPauseMs': settings.minimumPauseMs,
      'paddingMs': settings.paddingMs,
    },
    'pauses': [
      for (final p in _pauses) {'startMs': p.startMs, 'endMs': p.endMs},
    ],
    'decisions': {for (final e in _decisions.entries) e.key: e.value.name},
    'lastVisitedId': _lastVisitedId,
  };
  static PauseReviewSession fromMap(Map<String, dynamic> map, int durationMs) {
    final session = PauseReviewSession();
    if (map.isEmpty) return session;
    final config = map['settings'] as Map;
    final threshold = (config['thresholdDb'] as num).toDouble(),
        minimum = (config['minimumPauseMs'] as num).toInt(),
        padding = (config['paddingMs'] as num).toInt();
    if (!threshold.isFinite ||
        threshold > -20 ||
        threshold < -60 ||
        minimum < 400 ||
        minimum > 2000 ||
        padding < 50 ||
        padding > 300) {
      throw const FormatException('Invalid pause settings.');
    }
    session.settings = SilenceSettings(
      thresholdDb: threshold,
      minimumPauseMs: minimum,
      paddingMs: padding,
    );
    for (final raw in map['pauses'] as List) {
      final start = (raw['startMs'] as num).toInt(),
          end = (raw['endMs'] as num).toInt();
      if (start < 0 || end <= start || end > durationMs) {
        throw const FormatException('Invalid saved pause.');
      }
      session._pauses.add(EditRange(start, end, EditKind.cut));
    }
    final valid = session._pauses.map(pauseId).toSet();
    for (final entry in (map['decisions'] as Map).entries) {
      if (!valid.contains(entry.key)) {
        throw const FormatException('Invalid saved pause decision.');
      }
      session._decisions[entry.key as String] = PauseDecision.values.byName(
        entry.value as String,
      );
    }
    final visited = map['lastVisitedId'] as String?;
    session._lastVisitedId = valid.contains(visited) ? visited : null;
    return session;
  }

  void sync(List<EditRange> pauses) {
    if (listEquals(
      _pauses.map(pauseId).toList(),
      pauses.map(pauseId).toList(),
    )) {
      return;
    }
    _pauses = List.of(pauses);
    final valid = _pauses.map(pauseId).toSet();
    _decisions.removeWhere((key, _) => !valid.contains(key));
    // History cannot restore decisions against changed detection boundaries.
    _history.clear();
    if (!valid.contains(_lastVisitedId)) _lastVisitedId = null;
    notifyListeners();
  }

  void reset() {
    _decisions.clear();
    _history.clear();
    _lastVisitedId = null;
    notifyListeners();
  }

  void decide(EditRange pause, PauseDecision? value) {
    if (!_pauses.any((p) => pauseId(p) == pauseId(pause))) return;
    _history.add(Map.of(_decisions));
    if (value == null) {
      _decisions.remove(pauseId(pause));
    } else {
      _decisions[pauseId(pause)] = value;
    }
    notifyListeners();
  }

  void markAllForTrim() {
    _history.add(Map.of(_decisions));
    for (final p in _pauses) {
      _decisions[pauseId(p)] = PauseDecision.trim;
    }
    notifyListeners();
  }

  void applied(List<EditRange> cuts) {
    for (final cut in cuts) {
      _decisions.remove(pauseId(cut));
    }
    _history.clear();
    notifyListeners();
  }

  void undo() {
    if (_history.isEmpty) return;
    _decisions
      ..clear()
      ..addAll(_history.removeLast());
    notifyListeners();
  }

  List<EditRange> ordered(PauseOrder order) {
    final result = List<EditRange>.of(_pauses);
    result.sort(
      (a, b) => order == PauseOrder.longest
          ? (b.endMs - b.startMs).compareTo(a.endMs - a.startMs) != 0
                ? (b.endMs - b.startMs).compareTo(a.endMs - a.startMs)
                : a.startMs.compareTo(b.startMs)
          : a.startMs.compareTo(b.startMs),
    );
    return result;
  }

  List<EditRange> visible(PauseFilter filter, PauseOrder order) =>
      ordered(order)
          .where(
            (p) => switch (filter) {
              PauseFilter.all => true,
              PauseFilter.unreviewed => decision(p) == null,
              PauseFilter.trim => decision(p) == PauseDecision.trim,
              PauseFilter.keep => decision(p) == PauseDecision.keep,
            },
          )
          .toList();
}
