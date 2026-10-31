import 'package:flutter/material.dart';
import '../design/app_theme.dart';
import '../media/media_engine.dart';
import '../transcript/transcription_engine.dart';
import 'editor_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.media, required this.speech});
  final MediaEngine media;
  final TranscriptionEngine speech;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _importing = false;
  String? _error;
  Future<void> _import() async {
    setState(() {
      _importing = true;
      _error = null;
    });
    try {
      final source = await widget.media.importVideo();
      if (source != null && mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => EditorScreen(
              initialSource: source,
              engine: widget.media,
              transcriptionEngine: widget.speech,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const LocalCutBrand()),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'YOUR VIDEO. YOUR FINAL CUT.',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Less cleanup.\nMore creating.',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 14),
                Text(
                  'Turn the rough recording into the video you meant to make.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 28),
                Container(
                  constraints: const BoxConstraints(minHeight: 150),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xff181818),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.smart_display_outlined,
                        color: Colors.white,
                        size: 40,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (final width in [30.0, 50.0, 22.0, 44.0, 32.0])
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 3,
                              ),
                              child: Container(
                                width: width,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: width == 22
                                      ? AppTheme.red
                                      : Colors.white24,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Keep the words. Lose the dead air.',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _importing ? null : _import,
                  icon: const Icon(Icons.add),
                  label: Text(
                    _importing
                        ? 'Opening your video…'
                        : 'Import video from Files',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.lock_outline,
                      size: 14,
                      color: colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Your footage stays on your device.',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 30),
                const _Step(
                  number: '01',
                  title: 'Bring your recording',
                  detail: 'One video, straight from your files.',
                ),
                const _Step(
                  number: '02',
                  title: 'Edit it like a script',
                  detail: 'Censor a word. Shorten a pause. Keep your flow.',
                ),
                const _Step(
                  number: '03',
                  title: 'Review. Export. Upload.',
                  detail: 'Save a new video with your original untouched.',
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(_error!, style: TextStyle(color: colors.error)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.title,
    required this.detail,
  });
  final String number, title, detail;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          number,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 3),
              Text(
                detail,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
