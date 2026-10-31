import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../design/app_theme.dart';
import '../media/media_engine.dart';

String videoClock(Duration duration) {
  final seconds = duration.inSeconds.clamp(0, 359999);
  final hours = seconds ~/ 3600, minutes = (seconds % 3600) ~/ 60;
  final tail = (seconds % 60).toString().padLeft(2, '0');
  return hours > 0
      ? '$hours:${minutes.toString().padLeft(2, '0')}:$tail'
      : '$minutes:$tail';
}

class SourceVideoPlayer extends StatefulWidget {
  const SourceVideoPlayer({
    super.key,
    required this.source,
    required this.enabled,
    required this.onOpenOriginal,
  });
  final SourceVideo source;
  final bool enabled;
  final Future<void> Function() onOpenOriginal;
  @override
  State<SourceVideoPlayer> createState() => SourceVideoPlayerState();
}

class SourceVideoPlayerState extends State<SourceVideoPlayer>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  String? _error;
  bool _loading = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void didUpdateWidget(covariant SourceVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source.path != widget.source.path) {
      _controller?.dispose();
      _controller = null;
      _error = null;
      _loading = true;
      _initialize();
    }
  }

  Future<void> _initialize() async {
    if (!File(widget.source.path).existsSync()) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Open the original to watch this clip.';
        });
      }
      return;
    }
    final controller = VideoPlayerController.file(File(widget.source.path));
    _controller = controller;
    try {
      await controller.initialize().timeout(const Duration(seconds: 20));
      if (mounted && identical(controller, _controller)) {
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted && identical(controller, _controller)) {
        setState(() {
          _loading = false;
          _error = 'Preview unavailable. You can still open the original.';
        });
      }
    }
  }

  Future<void> pause() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      await controller.pause();
    } catch (_) {
      /* The player may be disposing. */
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(pause());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _fullscreen() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: const Text(
              'Original video',
              style: TextStyle(color: Colors.white),
            ),
          ),
          body: SafeArea(
            child: _PlayerSurface(
              controller: controller,
              enabled: widget.enabled,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final height = math.min(
        constraints.maxWidth * 9 / 16 + 48,
        constraints.hasBoundedHeight ? constraints.maxHeight : double.infinity,
      );
      final controller = _controller;
      return SizedBox(
        width: double.infinity,
        height: height,
        child: ColoredBox(
          color: Colors.black,
          child: _error != null || controller == null || _loading
              ? Center(
                  child: _loading
                      ? const CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        )
                      : Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (height > 150) ...[
                                const Icon(
                                  Icons.video_file_outlined,
                                  size: 32,
                                  color: Colors.white54,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _error!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white60,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                              TextButton.icon(
                                onPressed: widget.enabled
                                    ? widget.onOpenOriginal
                                    : null,
                                icon: const Icon(
                                  Icons.play_arrow,
                                  color: Colors.white,
                                ),
                                label: const Text(
                                  'Watch original',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                        ),
                )
              : _PlayerSurface(
                  controller: controller,
                  enabled: widget.enabled,
                  onFullscreen: _fullscreen,
                ),
        ),
      );
    },
  );
}

class _PlayerSurface extends StatelessWidget {
  const _PlayerSurface({
    required this.controller,
    required this.enabled,
    this.onFullscreen,
  });
  final VideoPlayerController controller;
  final bool enabled;
  final VoidCallback? onFullscreen;
  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<VideoPlayerValue>(
    valueListenable: controller,
    builder: (context, value, _) {
      if (!value.isInitialized) return const SizedBox(height: 160);
      final maxMs = value.duration.inMilliseconds.toDouble();
      return Column(
        children: [
          Expanded(
            child: ClipRect(
              child: Stack(
                alignment: Alignment.center,
                fit: StackFit.expand,
                children: [
                  Center(
                    child: AspectRatio(
                      aspectRatio: value.aspectRatio,
                      child: VideoPlayer(controller),
                    ),
                  ),
                  if (!value.isPlaying)
                    Center(
                      child: IconButton.filled(
                        tooltip: 'Play original',
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black54,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.all(12),
                        ),
                        iconSize: 36,
                        onPressed: enabled ? () => controller.play() : null,
                        icon: const Icon(Icons.play_arrow_rounded),
                      ),
                    ),
                  if (value.isBuffering)
                    const Center(
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                IconButton(
                  tooltip: value.isPlaying ? 'Pause original' : 'Play original',
                  color: Colors.white,
                  onPressed: !enabled
                      ? null
                      : () => value.isPlaying
                            ? controller.pause()
                            : controller.play(),
                  icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
                ),
                Text(
                  '${videoClock(value.position)} / ${videoClock(value.duration)}',
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 5,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 10,
                      ),
                    ),
                    child: Slider(
                      min: 0,
                      max: maxMs > 0 ? maxMs : 1,
                      value: value.position.inMilliseconds.toDouble().clamp(
                        0,
                        maxMs > 0 ? maxMs : 1,
                      ),
                      activeColor: AppTheme.red,
                      inactiveColor: Colors.white24,
                      onChanged: enabled && maxMs > 0
                          ? (ms) => controller.seekTo(
                              Duration(milliseconds: ms.round()),
                            )
                          : null,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: value.volume == 0
                      ? 'Unmute preview'
                      : 'Mute preview',
                  color: Colors.white,
                  onPressed: enabled
                      ? () => controller.setVolume(value.volume == 0 ? 1 : 0)
                      : null,
                  icon: Icon(
                    value.volume == 0
                        ? Icons.volume_off_outlined
                        : Icons.volume_up_outlined,
                  ),
                  iconSize: 20,
                ),
                if (onFullscreen != null)
                  IconButton(
                    tooltip: 'Full screen',
                    color: Colors.white,
                    onPressed: enabled ? onFullscreen : null,
                    icon: const Icon(Icons.fullscreen),
                    iconSize: 22,
                  ),
              ],
            ),
          ),
        ],
      );
    },
  );
}
