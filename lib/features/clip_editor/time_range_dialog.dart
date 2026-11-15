import 'package:flutter/material.dart';

import '../../core/utilities/formatters.dart';

/// Asks for a start and end time. Pops with `(startMs, endMs)`.
///
/// [validate] may return a message to keep the dialog open, for ranges that
/// must not be saved at all.
class TimeRangeDialog extends StatefulWidget {
  const TimeRangeDialog({
    super.key,
    required this.title,
    required this.startMs,
    required this.endMs,
    this.validate,
  });

  final String title;
  final int startMs;
  final int endMs;
  final String? Function(int startMs, int endMs)? validate;

  @override
  State<TimeRangeDialog> createState() => _TimeRangeDialogState();
}

class _TimeRangeDialogState extends State<TimeRangeDialog> {
  late final _start = TextEditingController(
    text: formatTimestamp(widget.startMs),
  );
  late final _end = TextEditingController(text: formatTimestamp(widget.endMs));
  String? _error;

  @override
  void dispose() {
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  void _submit() {
    final start = parseTimestamp(_start.text);
    final end = parseTimestamp(_end.text);
    final error = start == null || end == null
        ? 'Enter times like 1:23.5 or 1:02:03'
        : widget.validate?.call(start, end);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context, (start!, end!));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _start,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Start'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _end,
            decoration: InputDecoration(labelText: 'End', errorText: _error),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
