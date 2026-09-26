/// Turns a visible chat reply into words suitable for text to speech.
/// This never changes the saved or displayed message.
class SpeechText {
  static final _action = RegExp(r'\*([^*\n]{1,80})\*');
  static final _stageDirection = RegExp(
    r'^(?:laughs?|chuckles?|giggles?|sighs?|smiles?|smirks?|whispers?|moans?|gasps?|pauses?|nods?|shakes?|leans?|grins?|breathes?|winks?|voice (?:dropping|softening|lowering))\b',
    caseSensitive: false,
  );

  static String? direction(String text) {
    final lower = text.toLowerCase();
    if (RegExp(r'[\*\[](?:laughs?|chuckles?|giggles?)\b').hasMatch(lower)) {
      return 'chuckle';
    }
    if (RegExp(r'[\*\[](?:whispers?|leans? closer)\b').hasMatch(lower)) {
      return 'whisper';
    }
    return null;
  }

  static String prepare(String text) {
    var spoken = text;
    spoken = spoken.replaceAll(
      RegExp(r'```[\s\S]*?```'),
      ' I included code in the message. ',
    );
    spoken = spoken.replaceAllMapped(
      RegExp(r'!?\[([^\]]+)\]\([^)]+\)'),
      (match) => match.group(1)!,
    );
    spoken = spoken.replaceAllMapped(_action, (match) {
      final phrase = match.group(1)!;
      final action = phrase.trim().replaceAll(RegExp(r'^\(|\)$'), '');
      return _stageDirection.hasMatch(action) ? ' ' : phrase;
    });
    spoken = spoken.replaceAllMapped(
      RegExp(
        r'\((?:laughs?|chuckles?|giggles?|sighs?|whispers?|winks?|voice (?:dropping|softening|lowering))[^)]*\)',
        caseSensitive: false,
      ),
      (_) => ' ',
    );
    spoken = spoken.replaceAll(
      RegExp(
        r'\[(?:whisper|angry|chuckle|laugh|warm|emphasis)\]',
        caseSensitive: false,
      ),
      ' ',
    );
    spoken = spoken.replaceAll(
      RegExp(r'^\s{0,3}(?:#{1,6}|>|[-•])\s+', multiLine: true),
      '',
    );
    spoken = spoken.replaceAll(RegExp(r'\[\d+\]'), '');
    spoken = spoken.replaceAll(RegExp(r'https?://\S+'), 'a link');
    spoken = spoken.replaceAll(RegExp(r'[`*_~|]'), ' ');
    spoken = spoken.replaceAll(
      RegExp(r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}]', unicode: true),
      '',
    );
    spoken = spoken.replaceAllMapped(
      RegExp(r'\s+([,.!?;:])'),
      (match) => match.group(1)!,
    );
    spoken = spoken.replaceAll(RegExp(r'\s+'), ' ').trim();
    return spoken;
  }
}
