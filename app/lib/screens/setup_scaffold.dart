import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// The frame every mode-select screen shares: a title, a how-to card, the
/// options, and one big start button pinned at the bottom.
///
/// Each game still owns its own screen — the options genuinely differ — but
/// four more copies of the same header, scroll view and button would have been
/// four more places for a 320pt overflow to hide.
class SetupScaffold extends StatelessWidget {
  const SetupScaffold({
    required this.title,
    required this.howTo,
    required this.children,
    required this.startLabel,
    required this.accent,
    required this.onStart,
    super.key,
  });

  final String title;
  final List<(IconData, String)> howTo;
  final List<Widget> children;
  final String startLabel;
  final Color accent;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: ElevarColors.white,
                  ),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(title, style: ElevarType.display(24)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _HowTo(steps: howTo, accent: accent),
                      ...children,
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ChunkyButton(label: startLabel, color: accent, onPressed: onStart),
            ],
          ),
        ),
      ),
    );
  }
}

/// A labelled group of options.
class SetupSection extends StatelessWidget {
  const SetupSection({
    required this.label,
    required this.child,
    this.caption,
    super.key,
  });

  final String label;
  final Widget child;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(label, style: ElevarType.label(11)),
          const SizedBox(height: 10),
          child,
          if (caption != null) ...<Widget>[
            const SizedBox(height: 10),
            Text(caption!, style: ElevarType.body(14, color: ElevarColors.muted)),
          ],
        ],
      ),
    );
  }
}

class _HowTo extends StatelessWidget {
  const _HowTo({required this.steps, required this.accent});

  final List<(IconData, String)> steps;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ElevarColors.surfaceRaised,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ElevarColors.ink, width: 3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('HOW IT WORKS', style: ElevarType.label(10)),
          const SizedBox(height: 10),
          for (final (icon, text) in steps)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: <Widget>[
                  Icon(icon, color: accent, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(text, style: ElevarType.body(14, color: ElevarColors.white)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
