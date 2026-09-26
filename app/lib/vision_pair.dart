/// Recognized GGUF families that require a matching vision projector.
/// Unknown imported families are left to llama.cpp's runtime validation.
String? visionFamily(String path) {
  final name = path.split(RegExp(r'[/\\]')).last.toLowerCase();
  if (name.contains('ministral-3-3b')) return 'Ministral 3 3B';
  if (name.contains('smolvlm2-500m')) return 'SmolVLM2 500M';
  if (name.contains('qwen3-vl-4b')) return 'Qwen3 VL 4B';
  if (name.contains('qwen3.5-4b')) return 'Qwen3.5 4B';
  return null;
}

bool knownVisionPairMismatch(String modelPath, String projectorPath) {
  final modelFamily = visionFamily(modelPath);
  final projectorFamily = visionFamily(projectorPath);
  return modelFamily != null &&
      projectorFamily != null &&
      modelFamily != projectorFamily;
}

bool isProjectorInitFailure(Object error) {
  final value = error.toString().toLowerCase();
  return value.contains('did not return an mtmd context') ||
      value.contains('failed to load multimodal projector') ||
      value.contains('multimodal projector loading');
}
