import 'package:flutter_test/flutter_test.dart';
import 'package:localcut/core/silence_detection.dart';

void main() {
  const settings = SilenceSettings();
  AudioAnalysis audio(List<AudioWindow> windows) =>
      AudioAnalysis(windows, hasAudio: true);
  test('long pause is trimmed with 150 ms padding on both edges', () {
    final cuts = detectSilence(
      audio(const [
        AudioWindow(0, 1000, -15),
        AudioWindow(1000, 3000, -65),
        AudioWindow(3000, 5000, -20),
      ]),
      5000,
      settings,
    );
    expect(cuts.map((e) => [e.startMs, e.endMs]).toList(), [
      [1150, 2850],
    ]);
  });
  test('short pauses and a small audible interruption are preserved', () {
    final cuts = detectSilence(
      audio(const [
        AudioWindow(0, 1000, -15),
        AudioWindow(1000, 1500, -65),
        AudioWindow(1500, 1520, -20),
        AudioWindow(1520, 2100, -65),
        AudioWindow(2100, 3000, -15),
      ]),
      3000,
      settings,
    );
    expect(cuts, isEmpty);
  });
  test('unknown timeline gaps do not combine into a silence run', () {
    expect(
      detectSilence(
        audio(const [
          AudioWindow(0, 1000, -15),
          AudioWindow(1000, 1500, -65),
          AudioWindow(2000, 2500, -65),
          AudioWindow(2500, 3000, -15),
        ]),
        3000,
        settings,
      ),
      isEmpty,
    );
  });
  test('no track, empty analysis, and all-quiet recordings are untouched', () {
    expect(
      detectSilence(const AudioAnalysis([], hasAudio: false), 3000, settings),
      isEmpty,
    );
    expect(detectSilence(audio([]), 3000, settings), isEmpty);
    expect(
      detectSilence(audio(const [AudioWindow(0, 3000, -120)]), 3000, settings),
      isEmpty,
    );
  });
  test('threshold and padding settings recalculate cached measurements', () {
    final measured = audio(const [
      AudioWindow(0, 1000, -15),
      AudioWindow(1000, 3000, -35),
      AudioWindow(3000, 4000, -15),
    ]);
    expect(detectSilence(measured, 4000, settings), isEmpty);
    final cuts = detectSilence(
      measured,
      4000,
      const SilenceSettings(thresholdDb: -30, paddingMs: 250),
    );
    expect(cuts.single.startMs, 1250);
    expect(cuts.single.endMs, 2750);
  });
  test('leading and trailing quiet sections respect source bounds', () {
    final cuts = detectSilence(
      audio(const [
        AudioWindow(0, 1000, -80),
        AudioWindow(1000, 2000, -10),
        AudioWindow(2000, 3000, -80),
      ]),
      3000,
      settings,
    );
    expect(cuts.map((e) => [e.startMs, e.endMs]).toList(), [
      [150, 850],
      [2150, 2850],
    ]);
  });
  test('padding cannot invert a short quiet interval', () {
    expect(
      detectSilence(
        audio(const [AudioWindow(0, 1000, -10), AudioWindow(1000, 1500, -80)]),
        1500,
        const SilenceSettings(minimumPauseMs: 400, paddingMs: 300),
      ),
      isEmpty,
    );
  });
  test('rejects invalid analysis instead of proposing uncertain cuts', () {
    for (final windows in [
      [const AudioWindow(100, 50, -80)],
      [const AudioWindow(0, 1001, -80)],
      [const AudioWindow(0, 500, -10), const AudioWindow(400, 900, -80)],
      [const AudioWindow(0, 100, double.nan)],
    ]) {
      expect(
        () => detectSilence(audio(windows), 1000, settings),
        throwsArgumentError,
      );
    }
  });
}
