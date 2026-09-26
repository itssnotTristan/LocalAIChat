enum InferenceProfile {
  quick('Quick', 'Short replies and smaller images', 640, 2048, 4, 100),
  balanced('Balanced', 'Clear answers at a moderate pace', 768, 3072, 8, 160),
  detailed(
    'Detailed',
    'More visual detail and longer answers',
    1024,
    4096,
    12,
    320,
  );

  const InferenceProfile(
    this.label,
    this.description,
    this.imageSide,
    this.contextSize,
    this.iosGpuLayers,
    this.visionOutputCap,
  );

  final String label;
  final String description;
  final int imageSide;
  final int contextSize;
  final int iosGpuLayers;
  final int visionOutputCap;

  static InferenceProfile fromName(String? name) =>
      InferenceProfile.values
          .where((profile) => profile.name == name)
          .firstOrNull ??
      InferenceProfile.balanced;

  int outputTokens(
    int userLimit, {
    required bool hasMedia,
    required bool video,
  }) {
    if (!hasMedia) {
      return switch (this) {
        InferenceProfile.quick => userLimit.clamp(80, 160),
        InferenceProfile.balanced => userLimit.clamp(100, 260),
        InferenceProfile.detailed => userLimit.clamp(150, 700),
      };
    }
    return userLimit.clamp(60, video ? visionOutputCap ~/ 2 : visionOutputCap);
  }
}
