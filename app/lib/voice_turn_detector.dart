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

  /// A barge-in recording already contains the start of the user's sentence.
  void seedSpeech(int elapsedMilliseconds) {
    hasSpeech = true;
    speechSamples = 2;
    lastSpeechAt = elapsedMilliseconds;
  }

  bool add(double level, int elapsedMilliseconds) {
    if (!level.isFinite) return false;
    final threshold = (noiseFloor + 10).clamp(-46.0, -27.0);
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
      noiseFloor = noiseFloor * 0.9 + level.clamp(-95.0, -25.0) * 0.1;
    }
    return hasSpeech &&
        lastSpeechAt != null &&
        elapsedMilliseconds - lastSpeechAt! >= pauseMilliseconds;
  }
}

/// A separate detector for a user's voice while synthesized speech plays.
/// It learns the playback bleed level and requires several elevated samples,
/// rather than interrupting on a single click or speaker peak.
class VoiceBargeInDetector {
  double baseline = -48;
  int elevatedSamples = 0;

  bool add(double level, int elapsedMilliseconds) {
    if (!level.isFinite) return false;
    if (elapsedMilliseconds < 300) {
      baseline = baseline * 0.65 + level.clamp(-90.0, -12.0) * 0.35;
      return false;
    }
    final threshold = (baseline + 9).clamp(-38.0, -16.0);
    if (level > threshold) {
      elevatedSamples++;
    } else {
      elevatedSamples = 0;
      baseline = baseline * 0.94 + level.clamp(-90.0, -12.0) * 0.06;
    }
    return elevatedSamples >= 3;
  }
}
