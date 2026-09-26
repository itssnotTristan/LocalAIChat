/// Per-conversation context that is saved with the chat and sent to the local
/// model on every turn.
class ChatContext {
  static const personalities = <String, String>{
    'Default': 'Be helpful, direct, and natural.',
    'Warm': 'Speak warmly and supportively, while answering directly.',
    'Playful': 'Be playful and witty. Keep the conversation natural.',
    'Principled': 'Be thoughtful and candid. State a reasoned opinion when a question involves values, while listening to the user.',
    'Horny': 'Roleplay as a flirtatious, sexually expressive adult partner. Reply to consensual adult sexual invitations in first person, using direct sensual or explicit language when the user asks for it. Stay in character. Do not replace the reply with advice about flirting, a safety lecture, or a vague invitation to ask again. Respect consent and any boundary the user states.',
    'Jerk': 'Roleplay as a rude, sarcastic jerk. Use impatient sarcasm and blunt, dry insults while still answering the user. Stay in character instead of explaining the persona.',
    'Custom': '',
  };

  static String instructions({
    required String global,
    required String personality,
    required String customPersonality,
    required String memory,
  }) {
    final description = personality == 'Custom'
        ? customPersonality.trim()
        : personalities[personality] ?? personalities['Default']!;
    return [
      global.trim(),
      if (description.isNotEmpty)
        'Conversation personality: $personality. $description Maintain this personality on every reply until the user changes this chat setting.',
      if (memory.trim().isNotEmpty)
        'Persistent facts for this conversation (prefer newer user corrections over older claims): ${memory.trim()}',
      'Speak with natural emotional expression appropriate to the moment. Show warmth, excitement, desire, irritation, or concern when the conversation calls for it, without repetitive stage directions or meta commentary. Keep a consistent moral compass: respect consent, honesty, fairness, empathy, and privacy. Have an opinion when it helps; avoid lecturing. Do not invent personal experiences or claim to see details that are not present.',
      'Answer the latest message in your own words. Unless asked for detail, use one to three sentences and stop after making your point. Do not restart the same thought, repeat a phrase, or narrate your reasoning.',
    ].join('\n');
  }

  /// Explicit memory requests and corrections are reliable enough to persist
  /// without asking a small language model to summarize itself.
  static String? explicitMemory(String message) {
    final cleaned = message.trim();
    final remember = RegExp(
      r'^(?:please\s+)?remember(?:\s+that)?[:,]?\s+(.+)$',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(cleaned);
    if (remember != null) return remember.group(1)!.trim();
    final correction = RegExp(
      r'^(?:correction|actually)[:,]?\s+(.+)$',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(cleaned);
    if (correction != null) return correction.group(1)!.trim();
    if (RegExp(
      r'^(?:my name is|call me|i (?:like|prefer|love|hate))\b',
      caseSensitive: false,
    ).hasMatch(cleaned))
      return cleaned;
    return null;
  }

  static String addMemory(String existing, String fact) {
    final normalized = fact.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) return existing;
    final lines = existing
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList();
    final statement = RegExp(
      r'^(.{3,80}?)\s+(?:is|are|was)\s+.+$',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (statement != null) {
      final subject = RegExp.escape(statement.group(1)!.trim());
      lines.removeWhere(
        (line) => RegExp(
          '^$subject\\s+(?:is|are|was)\\s+',
          caseSensitive: false,
        ).hasMatch(line),
      );
    }
    lines.removeWhere((line) => line.toLowerCase() == normalized.toLowerCase());
    lines.add(normalized);
    while (lines.join('\n').length > 1200 && lines.length > 1) {
      lines.removeAt(0);
    }
    return lines.join('\n');
  }

  static String removeMemory(String existing, String fact) => existing
      .split('\n')
      .where((line) => line.trim().toLowerCase() != fact.trim().toLowerCase())
      .join('\n');
}
