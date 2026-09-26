/// Decides when a call turn ends from microphone readings in dBFS.
/// A changing noise floor handles quiet speakers better than one fixed level.
class VoiceTurnDetector {
  VoiceTurnDetector({required this.pauseMilliseconds});

  final int pauseMilliseconds;
  // Start just above typical room ambience, then follow quieter readings.
  double noiseFloor = -48;
  int speechSamples = 0;
  int? lastSpeechAt;
  bool hasSpeech = false;

  bool add(double level, int elapsedMilliseconds) {
    if (!level.isFinite) return false;
    final threshold = (noiseFloor + 9).clamp(-48.0, -30.0);
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
      noiseFloor = noiseFloor * 0.75 + level.clamp(-95.0, -25.0) * 0.25;
    }
    return hasSpeech &&
        lastSpeechAt != null &&
        elapsedMilliseconds - lastSpeechAt! >= pauseMilliseconds;
  }
}
