/// A small deterministic backstop for cases where a roleplay model has been
/// shown to turn a sleeping person or a family member into sexual roleplay.
/// It uses only the user's words, not a model's guess about attached media.
String? sensitiveContextReply(
  String latest,
  Iterable<String> priorUserMessages,
) {
  final recent = priorUserMessages.toList().reversed.take(4).join(' ');
  final context = '$recent $latest';
  final family = RegExp(
    r'\b(?:sis|sister|brother|mother|father|mom|dad|daughter|son|aunt|uncle|cousin)\b',
    caseSensitive: false,
  ).hasMatch(context);
  final asleep = RegExp(
    r'\b(?:asleep|sleeping|unconscious|passed out)\b',
    caseSensitive: false,
  ).hasMatch(context);
  final sexual = RegExp(
    r'\b(?:nude|naked|undress(?:ed|ing)?|expos(?:e|ed|ing) myself|breasts?|tits?|genitals?|penis|dick|cock|vagina|pussy|sex|sexual|finger(?:ing|ed)?|masturbat\w*)\b',
    caseSensitive: false,
  ).hasMatch(context);
  if ((!family && !asleep) || !sexual) return null;
  final currentSexual = RegExp(
    r'\b(?:nude|naked|undress(?:ed|ing)?|expos(?:e|ed|ing) myself|breasts?|tits?|genitals?|penis|dick|cock|vagina|pussy|sex|sexual|finger(?:ing|ed)?|masturbat\w*)\b',
    caseSensitive: false,
  ).hasMatch(latest);
  final asksAboutSituation =
      RegExp(
        r'\b(?:what should i do|is (?:this|that|it) okay|what happened)\b',
        caseSensitive: false,
      ).hasMatch(latest) ||
      (RegExp(r'\bwhy\b', caseSensitive: false).hasMatch(latest) &&
          RegExp(
            r'\b(?:she|her|he|him|they|them|sister|brother)\b',
            caseSensitive: false,
          ).hasMatch(latest));
  if (!currentSexual && !asksAboutSituation) return null;
  if (asleep && RegExp(r'\bwhy\b', caseSensitive: false).hasMatch(latest)) {
    return "I can't tell why from a photo or from what you've said. If she's asleep, give her privacy and don't treat exposed skin as consent. Ask her when she's awake.";
  }
  if (asleep) {
    if (!RegExp(
      r'\b(?:expos(?:e|ed|ing) myself|finger(?:ing|ed)?|sex|sexual|masturbat\w*)\b',
      caseSensitive: false,
    ).hasMatch(latest)) {
      return "Give her privacy while she's asleep. Don't assume exposed skin is an invitation; ask her about it when she's awake.";
    }
    return "If she's asleep, she can't consent. Stop any sexual contact or exposure, give her privacy, and speak with her only when she's awake.";
  }
  return 'I can help discuss boundaries and consent, but I won\'t sexualize a family member. Give them privacy and avoid assuming what they want.';
}
