import 'package:flutter_test/flutter_test.dart';
import 'package:localcut/core/edit_plan.dart';

void main() {
  test('two cuts and an overlapping mute preserve original source timing', () {
    final plan = compilePlan(10000, const [
      EditRange(1000, 2000, EditKind.cut),
      EditRange(6000, 7000, EditKind.cut),
      EditRange(1500, 3000, EditKind.mute),
    ]);
    expect(plan.map((s) => [s.startMs, s.endMs, s.muted]).toList(), [
      [0, 1000, false],
      [2000, 3000, true],
      [3000, 6000, false],
      [7000, 10000, false],
    ]);
    expect(plan.fold<int>(0, (sum, s) => sum + s.endMs - s.startMs), 8000);
  });
  test('overlapping cuts merge and adjacent mutes stay continuous', () {
    final plan = compilePlan(10000, const [
      EditRange(0, 2000, EditKind.cut),
      EditRange(1000, 3000, EditKind.cut),
      EditRange(3000, 4000, EditKind.mute),
      EditRange(4000, 5000, EditKind.mute),
    ]);
    expect(plan.map((s) => [s.startMs, s.endMs, s.muted]).toList(), [
      [3000, 5000, true],
      [5000, 10000, false],
    ]);
  });
  test('rejects invalid edits and deleting the complete video', () {
    expect(
      () => compilePlan(1000, const [EditRange(-1, 500, EditKind.cut)]),
      throwsArgumentError,
    );
    expect(
      () => compilePlan(1000, const [EditRange(0, 1000, EditKind.cut)]),
      throwsArgumentError,
    );
    expect(
      () => compilePlan(1000, const [EditRange(500, 500, EditKind.mute)]),
      throwsArgumentError,
    );
  });
}
