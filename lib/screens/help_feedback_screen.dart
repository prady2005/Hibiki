import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../services/feedback_service.dart';
import '../services/theme_state.dart';
import '../widgets/app_feedback.dart';

class HelpFeedbackScreen extends StatefulWidget {
  const HelpFeedbackScreen({super.key});

  @override
  State<HelpFeedbackScreen> createState() => _HelpFeedbackScreenState();
}

class _HelpFeedbackScreenState extends State<HelpFeedbackScreen> {
  static const List<String> _categories = <String>[
    'Bug report',
    'Feature request',
    'Design suggestion',
    'General feedback',
    'Other',
  ];

  final TextEditingController _messageController = TextEditingController();
  int _rating = 0;
  String _category = 'General feedback';
  bool _isSubmitting = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final String message = _messageController.text.trim();
    if (message.isEmpty) {
      showAppFeedback(context, 'Share your feedback before submitting');
      return;
    }

    setState(() => _isSubmitting = true);
    final now = DateTime.now();
    final bool sentToReceiver = await submitFeedback(
      FeedbackSubmission(
        id: now.microsecondsSinceEpoch.toString(),
        rating: _rating,
        category: _category,
        message: message,
        createdAt: now,
      ),
    );
    if (!mounted) return;

    setState(() {
      _isSubmitting = false;
      _rating = 0;
      _category = 'General feedback';
      _messageController.clear();
    });
    showAppFeedback(
      context,
      sentToReceiver ? 'Feedback submitted successfully' : 'Failed to submit feedback',
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppThemePalette palette = activeAppPalette(context);

    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            _PageHeader(title: 'Help and feedback', palette: palette),
            const SizedBox(height: 18),
            _FeedbackSection(
              title: 'How do you rate your experience',
              palette: palette,
              child: Row(
                children: List<Widget>.generate(5, (index) {
                  final int value = index + 1;
                  return IconButton(
                    tooltip: '$value star${value == 1 ? '' : 's'}',
                    onPressed: () => setState(() => _rating = value),
                    icon: Icon(
                      value <= _rating ? CupertinoIcons.star_fill : CupertinoIcons.star,
                      color: value <= _rating ? palette.accent : palette.mutedText,
                      size: 31,
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 14),
            _FeedbackSection(
              title: 'Category',
              palette: palette,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _categories.map((category) {
                  final selected = category == _category;
                  return ChoiceChip(
                    label: Text(category),
                    selected: selected,
                    onSelected: (_) => setState(() => _category = category),
                    backgroundColor: palette.surfaceAlt,
                    selectedColor: palette.accent,
                    side: BorderSide(color: selected ? palette.accent : palette.border),
                    labelStyle: TextStyle(
                      color: selected ? readableTextOn(palette.accent) : palette.text,
                      fontWeight: FontWeight.w600,
                    ),
                    showCheckmark: false,
                    elevation: 0,
                    pressElevation: 0,
                    visualDensity: VisualDensity.compact,
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 14),
            _FeedbackSection(
              title: 'Message',
              palette: palette,
              child: TextField(
                controller: _messageController,
                minLines: 6,
                maxLines: 10,
                textCapitalization: TextCapitalization.sentences,
                style: TextStyle(color: palette.text),
                cursorColor: palette.accent,
                decoration: InputDecoration(
                  hintText: 'Share your feedback & thoughts',
                  hintStyle: TextStyle(color: palette.mutedText),
                  filled: true,
                  fillColor: palette.surfaceAlt,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: palette.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: palette.accent),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _isSubmitting ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: palette.accent,
                foregroundColor: readableTextOn(palette.accent),
                disabledBackgroundColor: palette.surfaceAlt,
                disabledForegroundColor: palette.mutedText,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              icon: _isSubmitting
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: readableTextOn(palette.accent),
                      ),
                    )
                  : const Icon(CupertinoIcons.paperplane_fill, size: 18),
              label: Text(_isSubmitting ? 'Submitting...' : 'Submit feedback'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.title, required this.palette});

  final String title;
  final AppThemePalette palette;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(CupertinoIcons.back, color: palette.text),
        ),
        Expanded(
          child: Text(
            title,
            style: TextStyle(color: palette.text, fontSize: 28, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _FeedbackSection extends StatelessWidget {
  const _FeedbackSection({
    required this.title,
    required this.palette,
    required this.child,
  });

  final String title;
  final AppThemePalette palette;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(color: palette.text, fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}
