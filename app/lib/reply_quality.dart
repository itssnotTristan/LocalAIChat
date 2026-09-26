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

/// Catch a weak model's answer that only copies the current user message.
bool isEchoedReply(String answer, String question) {
  String normalize(String value) => RegExp(
    r"[\p{L}\p{N}']+",
    unicode: true,
  ).allMatches(value.toLowerCase()).map((match) => match.group(0)!).join(' ');
  final reply = normalize(answer);
  final asked = normalize(question);
  return asked.isNotEmpty && reply == asked;
}

/// A text-only turn must not invent visual evidence from an older attachment.
bool isDetachedMediaReply(String answer, String question) {
  final visualTerms = RegExp(
    r'\b(image|photo|picture|video|frame|clip|screenshot)\b',
    caseSensitive: false,
  );
  if (visualTerms.hasMatch(question)) return false;
  return RegExp(
    r'\b(?:in|from|of) the (?:image|photo|picture|video|frame|clip|screenshot)\b',
    caseSensitive: false,
  ).hasMatch(answer);
}

bool isRepeatingReply(String text) {
  return repetitivePhraseStart(text) != null;
}

/// Returns the start of the redundant wording so the UI can keep the useful
/// part of a reply. An exact eight-word repeat is enough on its own. Shorter
/// phrases require three separated uses and a distinctive word; this catches
/// changing endings such as "I'm already imagining ..." without cutting a
/// normal answer that refers to the same subject twice.
int? repetitivePhraseStart(String text) {
  final matches = RegExp(
    r"[\p{L}\p{N}’']+",
    unicode: true,
  ).allMatches(text.toLowerCase()).toList();
  if (matches.length < 28) return null;
  final words = matches.map((match) => match.group(0)!).toList();
  final longPhrases = <String, int>{};
  final shortPhrases = <String, List<int>>{};
  for (var i = 0; i < words.length; i++) {
    if (i + 8 <= words.length) {
      final key = words.sublist(i, i + 8).join(' ');
      final previous = longPhrases[key];
      if (previous != null && i - previous >= 8) {
        return matches[i].start;
      }
      longPhrases.putIfAbsent(key, () => i);
    }
    if (i + 3 > words.length ||
        !words.sublist(i, i + 3).any((word) => word.length >= 7)) {
      continue;
    }
    final key = words.sublist(i, i + 3).join(' ');
    final starts = shortPhrases.putIfAbsent(key, () => []);
    if (starts.isNotEmpty && i - starts.last < 7) continue;
    starts.add(i);
    if (starts.length >= 3) return matches[starts[1]].start;
  }
  return null;
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
