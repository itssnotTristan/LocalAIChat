/// A creative roleplay fine-tune is useful for character dialogue, but an
/// instruction model is a better default for questions asking for facts,
/// explanations, advice, or a description.
bool asksForGroundedAnswer(String prompt) => RegExp(
  r'\b(?:why\b|what\s+(?:is|are|was|were|does|did|happened|should|do\s+you\s+think)\b|what\s+[a-z][a-z0-9-]*\s*\?|which\b|how\s+(?:does|do|did|can|should)\b|when\b|where\b|explain\b|describe\b)',
  caseSensitive: false,
).hasMatch(prompt);
