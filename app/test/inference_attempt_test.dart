import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_chat/inference_attempt.dart';
import 'package:local_ai_chat/inference_profile.dart';

void main() {
  test(
    'iPhone vision has a smaller CPU retry after context allocation fails',
    () {
      final attempts = inferenceAttempts(
        InferenceProfile.balanced,
        isIos: true,
        isVideo: false,
      );
      expect(attempts, hasLength(2));
      expect(attempts.first.gpuLayers, 8);
      expect(attempts.first.projectorOnGpu, isFalse);
      expect(attempts.last.contextSize, lessThan(attempts.first.contextSize));
      expect(attempts.last.gpuLayers, 0);
      expect(attempts.last.projectorOnGpu, isFalse);
    },
  );

  test('video retry reduces memory while desktop keeps one attempt', () {
    final ios = inferenceAttempts(
      InferenceProfile.balanced,
      isIos: true,
      isVideo: true,
    );
    expect(ios.first.contextSize, 4096);
    expect(ios.last.contextSize, 3072);
    expect(
      inferenceAttempts(
        InferenceProfile.balanced,
        isIos: false,
        isVideo: false,
      ),
      hasLength(1),
    );
  });

  test('only allocation errors trigger a lower-memory retry', () {
    expect(
      isContextMemoryFailure(
        StateError('Failed to create llama.cpp context for: model.gguf'),
      ),
      isTrue,
    );
    expect(isContextMemoryFailure(StateError('Out of memory')), isTrue);
    expect(isContextMemoryFailure(StateError('file does not exist')), isFalse);
  });
}
