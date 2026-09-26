import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_chat/inference_profile.dart';
import 'package:local_ai_chat/voice_turn_detector.dart';

void main() {
  test('response modes change vision workload and output budget', () {
    expect(
      InferenceProfile.quick.imageSide,
      lessThan(InferenceProfile.detailed.imageSide),
    );
    expect(
      InferenceProfile.quick.iosGpuLayers,
      lessThan(InferenceProfile.detailed.iosGpuLayers),
    );
    expect(
      InferenceProfile.quick.outputTokens(400, hasMedia: true, video: false),
      lessThan(
        InferenceProfile.detailed.outputTokens(
          400,
          hasMedia: true,
          video: false,
        ),
      ),
    );
    expect(InferenceProfile.fromName('missing'), InferenceProfile.balanced);
  });

  test('voice turn sends after speech followed by the selected pause', () {
    final detector = VoiceTurnDetector(pauseMilliseconds: 1000);
    expect(detector.add(-68, 0), false);
    expect(detector.add(-35, 120), false);
    expect(detector.add(-32, 240), false);
    expect(detector.hasSpeech, true);
    expect(detector.add(-67, 900), false);
    expect(detector.add(-67, 1250), true);
  });

  test('voice turn does not send before speech or during a brief pause', () {
    final detector = VoiceTurnDetector(pauseMilliseconds: 700);
    expect(detector.add(-80, 0), false);
    expect(detector.add(-76, 1000), false);
    detector.add(-30, 1200);
    detector.add(-28, 1320);
    expect(detector.add(-75, 1800), false);
    detector.add(-31, 1850);
    expect(detector.add(-75, 2500), false);
    expect(detector.add(-75, 2600), true);
  });

  test('steady background noise does not start a voice turn', () {
    final detector = VoiceTurnDetector(pauseMilliseconds: 700);
    for (var step = 0; step < 30; step++) {
      expect(detector.add(-40, step * 120), false);
    }
    expect(detector.hasSpeech, false);
  });
}
