/// Removes model thinking markers and stops clear generation loops.
String visibleReply(String raw) {
  var text = raw.replaceAll(
    RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false),
    '',
  );
  text = text.replaceAll(RegExp(r'<think>[\s\S]*$', caseSensitive: false), '');
  text = text.replaceAll(RegExp(r'<\|(?:im_start|im_end|endoftext)\|>'), '');
  return text.trimLeft();
}

bool isRepeatingReply(String text) {
  final words = RegExp(
    r"[\p{L}\p{N}']+",
    unicode: true,
  ).allMatches(text.toLowerCase()).map((match) => match.group(0)!).toList();
  if (words.length < 28) return false;
  final tail = words.sublist(words.length - 8).join(' ');
  var matches = 0;
  for (var i = 0; i <= words.length - 8; i++) {
    if (words.sublist(i, i + 8).join(' ') == tail) matches++;
  }
  return matches >= 2;
}

/// Returns the beginning of a run of near-identical sentences, even when the
/// model changes the final word each time ("She has a small ..."). The UI can
/// keep the useful description before the run rather than displaying the loop.
int? repetitiveSentenceRunStart(String text) {
  final sentences = RegExp(r'[^.!?]+[.!?]').allMatches(text).toList();
  String? previousStem;
  var runLength = 0;
  var runStart = 0;
  for (final sentence in sentences) {
    final words = RegExp(r"[\p{L}\p{N}']+", unicode: true)
        .allMatches(sentence.group(0)!.toLowerCase())
        .map((match) => match.group(0)!)
        .toList();
    // Requiring at least five words means the repeated four-word stem cannot
    // be an entire short sentence such as "I can see it."
    if (words.length < 5) {
      previousStem = null;
      runLength = 0;
      continue;
    }
    final stem = words.take(4).join(' ');
    if (stem == previousStem) {
      runLength++;
    } else {
      previousStem = stem;
      runLength = 1;
      runStart = sentence.start;
    }
    if (runLength >= 4) return runStart;
  }
  return null;
}
