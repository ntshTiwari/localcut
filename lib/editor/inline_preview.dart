import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/edit_plan.dart';

class InlinePreviewController extends ChangeNotifier {
  String? path;
  List<RenderSegment> segments = [];
  String label = 'Selected section';
  int revision = 0;
  bool _disposed = false;
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void show(String source, List<RenderSegment> plan, {String? label}) {
    if (_disposed) return;
    this.label = label ?? 'Selected section';
    path = source;
    segments = List.unmodifiable(plan);
    revision++;
    notifyListeners();
  }

  void close() {
    if (_disposed) return;
    path = null;
    notifyListeners();
  }
}

/// Embeds an AVPlayer composition beside the editing controls, without a route.
class InlinePreviewPane extends StatefulWidget {
  const InlinePreviewPane({
    super.key,
    required this.controller,
    this.showPlaceholder = false,
  });
  final InlinePreviewController controller;
  final bool showPlaceholder;
  @override
  State<InlinePreviewPane> createState() => _InlinePreviewPaneState();
}

class _InlinePreviewPaneState extends State<InlinePreviewPane>
    with WidgetsBindingObserver {
  MethodChannel? _channel;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_changed);
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    if (widget.controller.path != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Scrollable.ensureVisible(
            context,
            duration: const Duration(milliseconds: 180),
          );
        }
      });
    }
  }

  Future<void> _pause() async {
    try {
      await _channel?.invokeMethod<void>('pause');
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_pause());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_pause());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (controller.path == null) {
      if (!widget.showPlaceholder) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(
            height: 48,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Choose a preview below'),
            ),
          ),
          SizedBox(
            height: math.min(200, MediaQuery.sizeOf(context).height * .23),
            child: const ColoredBox(
              color: Colors.black,
              child: Center(
                child: Icon(
                  Icons.play_circle_outline,
                  color: Colors.white54,
                  size: 48,
                ),
              ),
            ),
          ),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                controller.label,
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              tooltip: 'Close selection preview',
              onPressed: () {
                unawaited(_pause());
                controller.close();
              },
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        SizedBox(
          height: math.min(200, MediaQuery.sizeOf(context).height * .23),
          width: double.infinity,
          child: defaultTargetPlatform == TargetPlatform.iOS && !kIsWeb
              ? UiKitView(
                  key: ValueKey(controller.revision),
                  viewType: 'localcut/inline-preview',
                  creationParamsCodec: const StandardMessageCodec(),
                  creationParams: {
                    'path': controller.path,
                    'segments': controller.segments
                        .map((s) => s.toMap())
                        .toList(),
                  },
                  onPlatformViewCreated: (id) =>
                      _channel = MethodChannel('localcut/inline-preview/$id'),
                )
              : const ColoredBox(
                  color: Colors.black,
                  child: Center(
                    child: Text(
                      'Video preview requires the iPhone app.',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
