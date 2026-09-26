/// Decides when a call turn ends from microphone readings in dBFS.
/// A changing noise floor handles quiet speakers better than one fixed level.
class VoiceTurnDetector {
  VoiceTurnDetector({required this.pauseMilliseconds});

  final int pauseMilliseconds;
  double noiseFloor = -65;
  int speechSamples = 0;
  int? lastSpeechAt;
  bool hasSpeech = false;

  bool add(double level, int elapsedMilliseconds) {
    if (!level.isFinite) return false;
    final threshold = (noiseFloor + 9).clamp(-55.0, -30.0);
    final speaking = level > threshold;
    if (speaking) {
      speechSamples++;
      if (speechSamples >= 2 || hasSpeech) {
        hasSpeech = true;
        lastSpeechAt = elapsedMilliseconds;
      }
    } else {
      speechSamples = 0;
      // Follow a persistent room noise level, but do not let one loud sample
      // redefine silence during a sentence.
      noiseFloor = noiseFloor * 0.85 + level.clamp(-95.0, -25.0) * 0.15;
    }
    return hasSpeech &&
        lastSpeechAt != null &&
        elapsedMilliseconds - lastSpeechAt! >= pauseMilliseconds;
  }
}
