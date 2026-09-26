import 'package:flutter_test/flutter_test.dart';

import 'package:local_ai_chat/vision_pair.dart';

void main() {
  test('a projector from another known family is rejected', () {
    expect(
      knownVisionPairMismatch(
        '/models/mistralai_Ministral-3-3B-Instruct-2512-Q4_K_M.gguf',
        '/models/Qwen3-VL-4B-Instruct-abliterated-v1.mmproj-Q8_0.gguf',
      ),
      isTrue,
    );
    expect(
      knownVisionPairMismatch(
        '/models/Qwen3.5-4B-Uncensored.Q4_K_M.gguf',
        '/models/Qwen3.5-4B-Uncensored.mmproj-Q8_0.gguf',
      ),
      isFalse,
    );
  });

  test('projector load failures can trigger a vision fallback', () {
    expect(
      isProjectorInitFailure(
        StateError('llama.cpp did not return an mtmd context'),
      ),
      isTrue,
    );
    expect(
      isProjectorInitFailure(StateError('Failed to create llama.cpp context')),
      isFalse,
    );
  });
}
