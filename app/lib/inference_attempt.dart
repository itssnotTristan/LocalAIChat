import 'inference_profile.dart';

/// Keep the first iPhone attempt responsive, then shed GPU and context memory
/// if llama.cpp cannot allocate its context. Each attempt starts a fresh engine.
class InferenceAttempt {
  const InferenceAttempt({
    required this.contextSize,
    required this.gpuLayers,
    required this.projectorOnGpu,
  });

  final int contextSize;
  final int gpuLayers;
  final bool projectorOnGpu;
}

List<InferenceAttempt> inferenceAttempts(
  InferenceProfile profile, {
  required bool isIos,
  required bool isVideo,
}) {
  final contextSize = isVideo ? 4096 : profile.contextSize;
  final primary = InferenceAttempt(
    contextSize: contextSize,
    gpuLayers: isIos ? profile.iosGpuLayers : 0,
    projectorOnGpu: false,
  );
  if (!isIos) return [primary];
  return [
    primary,
    InferenceAttempt(
      contextSize: isVideo ? 3072 : 2048,
      gpuLayers: 0,
      projectorOnGpu: false,
    ),
  ];
}

bool isContextMemoryFailure(Object error) {
  final message = error.toString().toLowerCase();
  return message.contains('failed to create llama.cpp context') ||
      message.contains('out of memory') ||
      message.contains('failed to allocate');
}
