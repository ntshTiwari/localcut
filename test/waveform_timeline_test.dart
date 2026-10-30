import 'package:flutter_test/flutter_test.dart';
import 'package:localcut/core/silence_detection.dart';
import 'package:localcut/core/waveform_timeline.dart';

void main() {
  test('positions map to source time after zooming and panning', () {
    final view = WaveformViewport(10000, 4000, 6000);
    expect(view.timeAt(.25), 4500);
    expect(view.timeAt(-1), 4000);
    expect(view.timeAt(2), 6000);
    expect(view.fractionAt(4500), .25);
    expect(view.moveTo(20000).startMs, 8000);
    expect(view.moveTo(-100).startMs, 0);
  });
  test(
    'zoom anchors the focused source position and respects source limits',
    () {
      final zoomed = WaveformViewport.full(10000).zoomBy(2, 5000);
      expect([zoomed.startMs, zoomed.endMs], [2500, 7500]);
      final expanded = zoomed.zoomBy(.5, 5000);
      expect([expanded.startMs, expanded.endMs], [0, 10000]);
      final minimum = zoomed.zoomBy(1000, 5000);
      expect(minimum.spanMs, 250);
      expect(() => zoomed.zoomBy(0, 0), throwsArgumentError);
      expect(WaveformViewport.full(10).zoomBy(2, 5).spanMs, 10);
    },
  );
  test('dragging either direction creates ordered source-time selections', () {
    final selection = WaveformSelection.between(8000, 2000, 10000);
    expect([selection.startMs, selection.endMs], [2000, 8000]);
    final end = WaveformSelection.between(12000, 13000, 10000);
    expect([end.startMs, end.endMs], [9980, 10000]);
    final start = WaveformSelection.between(-10, -20, 10000);
    expect([start.startMs, start.endMs], [0, 20]);
  });
  test('handles cannot cross or leave source bounds', () {
    const selected = WaveformSelection(1000, 2000);
    expect(selected.resizeStart(2500, 5000).startMs, 1980);
    expect(selected.resizeEnd(0, 5000).endMs, 1020);
    expect(selected.resizeStart(-20, 5000).startMs, 0);
    expect(selected.resizeEnd(6000, 5000).endMs, 5000);
  });
  test('display bins keep loudest windows and leave unknown audio empty', () {
    final bins = waveformBins(
      const [
        AudioWindow(0, 50, -60),
        AudioWindow(50, 100, -10),
        AudioWindow(300, 400, -20),
      ],
      WaveformViewport.full(400),
      4,
    );
    expect(bins, [-10, null, null, -20]);
  });
  test(
    'binning intersects the viewport and does not include adjacent windows',
    () {
      final bins = waveformBins(
        const [
          AudioWindow(0, 100, -5),
          AudioWindow(100, 150, -30),
          AudioWindow(150, 200, -20),
          AudioWindow(200, 300, -5),
        ],
        WaveformViewport(300, 100, 200),
        2,
      );
      expect(bins, [-30, -20]);
    },
  );
}
