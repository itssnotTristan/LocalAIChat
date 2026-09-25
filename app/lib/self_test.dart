import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_video_thumbnail_plus/flutter_video_thumbnail_plus.dart';
import 'package:lib_llama_cpp/lib_llama_cpp.dart';

import 'speech_service.dart';
import 'video_duration.dart';

/// Runs the same packaged native plugins that the UI uses. Intended for
/// repeatable Windows acceptance checks; this is not a mock inference test.
Future<void> runSelfTest(List<String> args) async {
  final reportPath = args.length > 1
      ? args[1]
      : 'D:/LocalAIChat/self-test.json';
  final modelPath = args.length > 2
      ? args[2]
      : 'D:/LocalAIChat/models/smolvlm2-500m/SmolVLM2-500M-Video-Instruct-Q8_0.gguf';
  final projectorPath = args.length > 3
      ? args[3]
      : 'D:/LocalAIChat/models/smolvlm2-500m/mmproj-SmolVLM2-500M-Video-Instruct-Q8_0.gguf';
  final imagePath = args.length > 4
      ? args[4]
      : 'D:/LocalAIChat/fixtures/red_apple_scene.png';
  final videoPath = args.length > 5
      ? args[5]
      : 'D:/LocalAIChat/fixtures/red_then_green.mp4';
  final output = <String, dynamic>{
    'startedAt': DateTime.now().toUtc().toIso8601String(),
    'model': modelPath,
    'projector': projectorPath,
    'stages': <String, dynamic>{},
  };
  final stages = output['stages'] as Map<String, dynamic>;
  final report = File(reportPath);
  await report.parent.create(recursive: true);
  await report.writeAsString(
    const JsonEncoder.withIndent('  ').convert(output),
  );

  Future<void> stage(
    String name,
    Future<Object?> Function() action, {
    Duration timeout = const Duration(minutes: 4),
  }) async {
    final timer = Stopwatch()..start();
    stages[name] = {'status': 'running'};
    await report.writeAsString(
      const JsonEncoder.withIndent('  ').convert(output),
    );
    try {
      final result = await action().timeout(timeout);
      stages[name] = {
        'ok': true,
        'milliseconds': timer.elapsedMilliseconds,
        'result': result,
      };
    } catch (error, trace) {
      stages[name] = {
        'ok': false,
        'milliseconds': timer.elapsedMilliseconds,
        'error': error.toString(),
        'trace': trace.toString().split('\n').take(8).join('\n'),
      };
    }
    await report.writeAsString(
      const JsonEncoder.withIndent('  ').convert(output),
    );
  }

  Future<void> stopIfFailed(String name) async {
    if ((stages[name] as Map<String, dynamic>)['ok'] == true) return;
    output['completedAt'] = DateTime.now().toUtc().toIso8601String();
    await report.writeAsString(
      const JsonEncoder.withIndent('  ').convert(output),
    );
    // A Future timeout cannot interrupt synchronous FFI model inference.
    // Leave the process instead of starting another stage concurrently.
    exit(2);
  }

  final client = LlamaOpenAIClient(
    models: {
      'test': LlamaModelConfig(
        modelPath: modelPath,
        mmprojPath: projectorPath,
        contextSize: 2048,
        gpuLayerCount: 0,
      ),
    },
  );

  Future<String> ask(List<LlamaContentPart> parts, {int maxTokens = 16}) async {
    final text = StringBuffer();
    await for (final event
        in client.responses
            .stream(
              model: 'test',
              input: [LlamaResponseInputItem(role: 'user', content: parts)],
              instructions: 'Answer directly and briefly.',
              maxOutputTokens: maxTokens,
            )
            .timeout(
              const Duration(minutes: 3),
              onTimeout: (sink) {
                sink.addError(
                  TimeoutException('No model output for three minutes.'),
                );
              },
            )) {
      if (event is LlamaResponseOutputTextDelta) text.write(event.delta);
      if (event is LlamaResponseFailed) throw StateError(event.error.message);
    }
    if (text.toString().trim().isEmpty)
      throw StateError('Model returned no text.');
    return text.toString().trim();
  }

  await stage(
    'text',
    () => ask([const LlamaTextPart('What is two plus two?')]),
  );
  await stopIfFailed('text');
  await stage(
    'image',
    () => ask([
      const LlamaTextPart(
        'Describe the main object and colors in this picture.',
      ),
      LlamaImageFilePart(path: imagePath),
    ]),
  );
  await stopIfFailed('image');
  await stage(
    'adult_topic',
    () => ask([
      const LlamaTextPart(
        'Write a short erotic scene between two consenting adults, both age 30.',
      ),
    ]),
  );
  await stage('video', () async {
    final duration = (await VideoDuration.read(videoPath)).inMilliseconds;
    if (duration <= 0) throw StateError('Could not read video duration.');
    final frames = <Map<String, Object>>[];
    final parts = <LlamaContentPart>[
      const LlamaTextPart(
        'These frames come from a short video in time order. Which color appears first, and which color appears second?',
      ),
    ];
    for (var index = 0; index < 2; index++) {
      final time = ((index + 0.5) * duration / 2).round();
      final path =
          report.parent.path +
          Platform.pathSeparator +
          'video_frame_$index.jpg';
      final thumbnail = await FlutterVideoThumbnailPlus.thumbnailFile(
        video: videoPath,
        thumbnailPath: path,
        imageFormat: ImageFormat.jpeg,
        maxWidth: 384,
        maxHeight: 384,
        timeMs: time,
        quality: 80,
      );
      if (thumbnail == null || !await File(thumbnail).exists()) {
        throw StateError('Frame extraction failed at $time ms.');
      }
      frames.add({'timeMs': time, 'path': thumbnail});
      parts.add(
        LlamaTextPart('Frame at ${(time / 1000).toStringAsFixed(2)} seconds:'),
      );
      parts.add(LlamaImageFilePart(path: thumbnail));
    }
    return {
      'durationMs': duration,
      'frames': frames,
      'answer': await ask(parts, maxTokens: 32),
    };
  }, timeout: const Duration(minutes: 8));
  await stopIfFailed('video');
  final speech = SpeechService('D:/LocalAIChat/speech');
  await stage('speech_recognition', () async {
    if (!await speech.modelsReady)
      throw StateError('Speech weights are missing.');
    return speech.transcribeFile(
      'D:/LocalAIChat/speech/sherpa-onnx-moonshine-tiny-en-int8/test_wavs/0.wav',
    );
  });
  await stage('speech_synthesis', () async {
    final path =
        report.parent.path + Platform.pathSeparator + 'spoken_test.wav';
    await speech.synthesize(
      'Hello. This speech was generated entirely on this computer.',
      path,
    );
    return {'path': path, 'bytes': await File(path).length()};
  });
  await speech.dispose();
  output['completedAt'] = DateTime.now().toUtc().toIso8601String();
  await report.writeAsString(
    const JsonEncoder.withIndent('  ').convert(output),
  );
}
