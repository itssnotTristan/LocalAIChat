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
