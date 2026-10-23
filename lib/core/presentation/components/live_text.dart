import 'package:flutter/material.dart';

/// A text that appears while the user is looking at something else: an error,
/// a notice that the data is a saved copy. It is a live region for the screen
/// reader, announced when it shows up or changes. The one place that does so,
/// so that a message that matters is never silent for some users.
class LiveText extends StatelessWidget {
  /// Creates the text; [message] is the translated text.
  const new({required this.message, this.style, this.textAlign, super.key});

  /// The translated text.
  final String message;

  /// How it is drawn.
  final TextStyle? style;

  /// How it is aligned.
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    container: true,
    child: Text(message, style: style, textAlign: textAlign),
  );
}
