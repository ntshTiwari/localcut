import 'package:flutter/material.dart';
import '../transcript/transcript_actions.dart';
import 'inline_preview.dart';

/// One selection, a stable video area, and its decisions on one page.
class SelectionScreen extends StatefulWidget {
  const SelectionScreen({
    super.key,
    required this.actions,
    required this.busy,
    required this.error,
    required this.preview,
  });
  final ValueNotifier<TranscriptActions?> actions;
  final ValueNotifier<bool> busy;
  final ValueNotifier<String?> error;
  final InlinePreviewController preview;
  @override
  State<SelectionScreen> createState() => _SelectionScreenState();
}

class _SelectionScreenState extends State<SelectionScreen> {
  @override
  void initState() {
    super.initState();
    widget.actions.addListener(_selectionChanged);
  }

  bool _closing = false;
  void _selectionChanged() {
    final action = widget.actions.value;
    if (!_closing && (action == null || action.choosingPhrase)) {
      _closing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ModalRoute.of(context)?.isCurrent == true) {
          Navigator.pop(context);
        }
      });
    }
  }

  @override
  void dispose() {
    widget.actions.removeListener(_selectionChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([widget.actions, widget.busy, widget.error]),
    builder: (context, _) => PopScope(
      canPop: !widget.busy.value,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Edit selection'),
          leading: IconButton(
            tooltip: 'Back to transcript',
            onPressed: widget.busy.value ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back),
          ),
        ),
        body: SafeArea(
          child: Scrollbar(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                InlinePreviewPane(
                  controller: widget.preview,
                  showPlaceholder: true,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Compare the video, then choose a change. Your original stays untouched.',
                ),
                const SizedBox(height: 12),
                if (widget.actions.value case final actions?)
                  TranscriptActionBar(
                    actions: actions,
                    enabled: !widget.busy.value,
                  ),
                if (widget.busy.value) const LinearProgressIndicator(),
                if (widget.error.value case final error?)
                  Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
