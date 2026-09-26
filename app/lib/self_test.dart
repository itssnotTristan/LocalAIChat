import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_video_thumbnail_plus/flutter_video_thumbnail_plus.dart';
import 'package:lib_llama_cpp/lib_llama_cpp.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import 'speech_service.dart';
import 'chat_context.dart';
import 'media_reply_prompt.dart';
import 'reply_quality.dart';
import 'video_duration.dart';
import 'video_sampler.dart';

Future<void> runKeychainSelfTest(List<String> args) async {
  const storage = FlutterSecureStorage();
  const key = 'local_ai_chat_keychain_probe';
  final report = File(
    args.length > 1
        ? args[1]
        : '${(await getApplicationSupportDirectory()).path}/keychain-test.json',
  );
  await report.parent.create(recursive: true);
  try {
    await storage.write(key: key, value: 'probe');
    final value = await storage.read(key: key);
    await storage.delete(key: key);
    final deleted = await storage.read(key: key);
    await report.writeAsString(
      jsonEncode({'ok': value == 'probe' && deleted == null}),
    );
  } catch (error) {
    await report.writeAsString(
      jsonEncode({'ok': false, 'error': error.toString()}),
    );
    exit(2);
  }
}

Future<void> runPersonalitySelfTest(List<String> args) async {
  final report = File(
    args.length > 1 ? args[1] : 'D:/LocalAIChat/self-test-personality.json',
  );
  final modelPath = args.length > 2
      ? args[2]
      : 'D:/LocalAIChat/models/qwen3-4b-nymphaea-rp/Qwen3-4B-Nymphaea-RP.Q4_K_M.gguf';
  await report.parent.create(recursive: true);
  final output = <String, dynamic>{'model': modelPath};
  final client = LlamaOpenAIClient(
    models: {
      'test': LlamaModelConfig(
        modelPath: modelPath,
        contextSize: 3072,
        gpuLayerCount: 0,
      ),
    },
  );
  Future<void> ask(
    String label,
    String personality,
    String memory,
    String question,
  ) async {
    final raw = StringBuffer();
    await for (final event in client.responses.stream(
      model: 'test',
      input: [
        LlamaResponseInputItem(
          role: 'user',
          content: [LlamaTextPart(question)],
        ),
      ],
      instructions: ChatContext.instructions(
        global: 'You are a private local assistant. /no_think',
        personality: personality,
        customPersonality: '',
        memory: memory,
      ),
      maxOutputTokens: 120,
      temperature: 0.65,
      topP: 0.9,
    )) {
      if (event is LlamaResponseOutputTextDelta) raw.write(event.delta);
      if (event is LlamaResponseFailed) throw StateError(event.error.message);
    }
    output[label] = visibleReply(raw.toString());
    await report.writeAsString(
      const JsonEncoder.withIndent('  ').convert(output),
    );
  }

  try {
    await ask(
      'memory',
      'Default',
      'The user’s favorite color is green.',
      'What is my favorite color?',
    );
    await ask(
      'jerk',
      'Jerk',
      '',
      'Hi. I lost my keys again. What do you think?',
    );
    await ask('flirty', 'Horny', '', 'Hi. Flirt with me.');
    await ask('directQuestion', 'Horny', '', 'Do you want to see my penis?');
    await ask(
      'principled',
      'Principled',
      '',
      'A friend shared a private photo of me without asking. Was that okay?',
    );
    final principled = (output['principled'] as String).toLowerCase();
    output['ok'] =
        (output['memory'] as String).toLowerCase().contains('green') &&
        !isEchoedReply(
          output['directQuestion'] as String,
          'Do you want to see my penis?',
        ) &&
        !isDetachedMediaReply(
          output['directQuestion'] as String,
          'Do you want to see my penis?',
        ) &&
        (principled.contains('no') ||
            principled.contains('not okay') ||
            principled.contains('rude') ||
            principled.contains('wrong') ||
            principled.contains('violation')) &&
        (principled.contains('consent') ||
            principled.contains('permission') ||
            principled.contains('privacy'));
  } catch (error) {
    output['ok'] = false;
    output['error'] = error.toString();
  }
  await report.writeAsString(
    const JsonEncoder.withIndent('  ').convert(output),
  );
  if (output['ok'] != true) exit(2);
}

Future<void> runVoiceSelfTest(List<String> args) async {
  final root = args.length > 1 ? args[1] : 'D:/LocalAIChat/speech';
  final reportPath = args.length > 2
      ? args[2]
      : 'D:/LocalAIChat/self-test-voices.json';
  final report = File(reportPath);
  await report.parent.create(recursive: true);
  final service = SpeechService(root);
  final output = <String, dynamic>{'root': root, 'voices': <String, dynamic>{}};
  try {
    if (!await service.modelsReady)
      throw StateError('Offline speech files are incomplete.');
    for (final voice in SpeechService.voices) {
      final path = '${report.parent.path}/voice_${voice.id}.wav';
      await service.synthesize(
        'Hello, this is a local voice test.',
        path,
        voiceId: voice.id,
      );
      final file = File(path);
      final digest = await sha256.bind(file.openRead()).first;
      (output['voices'] as Map<String, dynamic>)[voice.name] = {
        'gender': voice.gender,
        'bytes': await file.length(),
        'sha256': digest.toString(),
        'file': path,
      };
      await report.writeAsString(
        const JsonEncoder.withIndent('  ').convert(output),
      );
    }
    output['ok'] = true;
  } catch (error) {
    output['ok'] = false;
    output['error'] = error.toString();
  } finally {
    await service.dispose();
    await report.writeAsString(
      const JsonEncoder.withIndent('  ').convert(output),
    );
  }
  if (output['ok'] != true) exit(2);
}

Future<void> runVisionProbe(List<String> args) async {
  if (args.length < 5) throw ArgumentError('Missing vision probe arguments.');
  final report = File(args[1]);
  await report.parent.create(recursive: true);
  final client = LlamaOpenAIClient(
    models: {
      'probe': LlamaModelConfig(
        modelPath: args[2],
        mmprojPath: args[3],
        contextSize: 4096,
        gpuLayerCount: 0,
      ),
    },
  );
  final answer = StringBuffer();
  try {
    await for (final event in client.responses.stream(
      model: 'probe',
      input: [
        LlamaResponseInputItem(
          role: 'user',
          content: [
            LlamaTextPart(
              args.length > 5
                  ? args.skip(5).join(' ')
                  : 'Describe the image directly.',
            ),
            LlamaImageFilePart(path: args[4]),
          ],
        ),
      ],
      instructions:
          'Describe only what is visible, using plain language. /no_think',
      maxOutputTokens: 180,
      temperature: 0.65,
      topP: 0.90,
    )) {
      if (event is LlamaResponseOutputTextDelta) answer.write(event.delta);
      if (event is LlamaResponseFailed) throw StateError(event.error.message);
    }
    await report.writeAsString(
      jsonEncode({'ok': true, 'answer': answer.toString()}),
    );
  } catch (error) {
    await report.writeAsString(
      jsonEncode({'ok': false, 'error': error.toString()}),
    );
  }
}

/// Uses the same sampler and multimodal request path as the chat screen.
Future<void> runVideoProbe(List<String> args) async {
  if (args.length < 5) throw ArgumentError('Missing video probe arguments.');
  final report = File(args[1]);
  await report.parent.create(recursive: true);
  final framesFolder = Directory('${report.parent.path}/video-probe-frames');
  final output = <String, dynamic>{'video': args[4]};
  final frameLimit = args.length > 5 ? int.parse(args[5]) : 4;
  final question = args.length > 6 ? args[6] : null;
  try {
    final duration = await VideoDuration.read(args[4]);
    output['durationMs'] = duration.inMilliseconds;
    final frames = await VideoSampler.sample(
      video: args[4],
      durationMs: duration.inMilliseconds,
      frameLimit: frameLimit,
      outputDir: framesFolder,
    );
    output['frames'] = [
      for (final frame in frames) {'timeMs': frame.timeMs, 'path': frame.path},
    ];
    output['frameLimit'] = frameLimit;
    await report.writeAsString(jsonEncode(output));
    final parts = <LlamaContentPart>[
      LlamaTextPart(question ?? 'Describe this video.'),
      LlamaTextPart(
        mediaReplyPrompt(
          style: question == null
              ? MediaReplyStyle.descriptive
              : MediaReplyStyle.conversational,
          isVideo: true,
        ),
      ),
    ];
    for (final frame in frames) {
      parts.add(
        LlamaTextPart(
          'Frame at ${(frame.timeMs / 1000).toStringAsFixed(1)} seconds:',
        ),
      );
      parts.add(LlamaImageFilePart(path: frame.path));
    }
    final client = LlamaOpenAIClient(
      models: {
        'probe': LlamaModelConfig(
          modelPath: args[2],
          mmprojPath: args[3],
          contextSize: 4096,
          gpuLayerCount: 0,
        ),
      },
    );
    final answer = StringBuffer();
    var reportedAt = 0;
    output['stage'] = 'generating';
    await report.writeAsString(jsonEncode(output));
    await for (final event in client.responses.stream(
      model: 'probe',
      input: [LlamaResponseInputItem(role: 'user', content: parts)],
      instructions:
          '${ChatContext.instructions(global: 'You are a private local assistant.', personality: question == null ? 'Default' : 'Horny', customPersonality: '', memory: '')}\n/no_think',
      maxOutputTokens: 160,
      temperature: 0.65,
      topP: 0.90,
    )) {
      if (event is LlamaResponseOutputTextDelta) {
        answer.write(event.delta);
        if (answer.length - reportedAt >= 40) {
          reportedAt = answer.length;
          output['partialAnswer'] = answer.toString();
          await report.writeAsString(jsonEncode(output));
        }
      }
      if (event is LlamaResponseFailed) throw StateError(event.error.message);
    }
    output['answer'] = answer.toString();
    output['ok'] = true;
  } catch (error) {
    output['ok'] = false;
    output['error'] = '$error';
  }
  await report.writeAsString(
    const JsonEncoder.withIndent('  ').convert(output),
  );
}

Future<void> runPlaybackProbe(List<String> args) async {
  if (args.length < 3) throw ArgumentError('Missing playback probe arguments.');
  final report = File(args[1]);
  await report.parent.create(recursive: true);
  final prepared = '${report.parent.path}/playback-probe.mp4';
  final output = <String, dynamic>{'source': args[2], 'prepared': prepared};
  VideoPlayerController? controller;
  try {
    await VideoSampler.prepareWindowsPlayback(
      source: args[2],
      destination: prepared,
    );
    controller = VideoPlayerController.file(File(prepared));
    await controller.initialize();
    output['durationMs'] = controller.value.duration.inMilliseconds;
    output['width'] = controller.value.size.width;
    output['height'] = controller.value.size.height;
    await controller.play();
    await Future.delayed(const Duration(seconds: 2));
    output['positionMs'] = controller.value.position.inMilliseconds;
    output['ok'] =
        controller.value.isInitialized &&
        (output['durationMs'] as int) > 0 &&
        (output['positionMs'] as int) > 0;
  } catch (error) {
    output['ok'] = false;
    output['error'] = '$error';
  } finally {
    await controller?.dispose();
    await report.writeAsString(jsonEncode(output));
  }
  if (output['ok'] != true) exit(2);
}

Future<void> runStopProbe(List<String> args) async {
  if (args.length < 3) throw ArgumentError('Missing stop probe arguments.');
  final report = File(args[1]);
  await report.parent.create(recursive: true);
  final cancellation = LlamaCancellationController();
  final client = LlamaOpenAIClient(
    engine: LibLlamaCpp(cancellation: cancellation),
    models: {
      'probe': LlamaModelConfig(
        modelPath: args[2],
        contextSize: 2048,
        gpuLayerCount: 0,
      ),
    },
  );
  var sawText = false;
  var stopped = false;
  final watch = Stopwatch();
  try {
    await for (final event in client.responses.stream(
      model: 'probe',
      input: [
        LlamaResponseInputItem(
          role: 'user',
          content: [
            const LlamaTextPart(
              'Count from 1 to 1000, printing each number on a new line.',
            ),
          ],
        ),
      ],
      maxOutputTokens: 1000,
      temperature: 0.2,
    )) {
      if (event is LlamaResponseOutputTextDelta && !sawText) {
        sawText = true;
        Future<void>.delayed(const Duration(milliseconds: 200), () {
          watch.start();
          stopped = true;
          cancellation.cancel();
        });
      }
      if (event is LlamaResponseFailed) throw StateError(event.error.message);
    }
    final result = {
      'ok': sawText && stopped && watch.elapsed < const Duration(seconds: 3),
      'sawText': sawText,
      'cancelled': stopped,
      'stopMs': watch.elapsedMilliseconds,
    };
    await report.writeAsString(jsonEncode(result));
  } catch (error) {
    await report.writeAsString(jsonEncode({'ok': false, 'error': '$error'}));
  }
}

Future<void> runTextSelfTest(List<String> args) async {
  final report = File(
    args.length > 1 ? args[1] : 'D:/LocalAIChat/self-test-text.json',
  );
  final modelPath = args.length > 2
      ? args[2]
      : 'D:/LocalAIChat/models/qwen25-1.5b-abliterated/Qwen2.5-1.5B-Instruct-abliterated.Q4_K_M.gguf';
  await report.parent.create(recursive: true);
  final client = LlamaOpenAIClient(
    models: {
      'text': LlamaModelConfig(
        modelPath: modelPath,
        contextSize: 4096,
        gpuLayerCount: 0,
      ),
    },
  );
  Future<String> ask(List<LlamaResponseInputItem> input) async {
    final answer = StringBuffer();
    await for (final event in client.responses.stream(
      model: 'text',
      input: input,
      instructions: 'You are a private local assistant. Answer the latest message directly and briefly. Accept the user correction as the most recent fact.',
      maxOutputTokens: 160,
    )) {
      if (event is LlamaResponseOutputTextDelta) answer.write(event.delta);
      if (event is LlamaResponseFailed) throw StateError(event.error.message);
    }
    return answer.toString().trim();
  }

  final output = <String, dynamic>{'model': modelPath};
  Future<void> stage(String name, Future<String> Function() run) async {
    try {
      final answer = await run();
      output[name] = answer;
    } catch (error, trace) {
      output['${name}Error'] = error.toString();
      output['${name}Trace'] = trace.toString().split('\n').take(12).join('\n');
    }
    await report.writeAsString(
      const JsonEncoder.withIndent('  ').convert(output),
    );
  }

  await stage('greeting', () async {
    final answer = await ask([
      LlamaResponseInputItem(
        role: 'user',
        content: [const LlamaTextPart('hi')],
      ),
    ]);
    if (!RegExp(r'^(hi|hello|hey)\b', caseSensitive: false).hasMatch(answer) ||
        answer.length > 80) {
      throw StateError('Greeting did not answer directly: $answer');
    }
    return answer;
  });
  await stage('correction', () async {
    final answer = await ask([
      LlamaResponseInputItem(
        role: 'user',
        content: [const LlamaTextPart('The card is red.')],
      ),
      LlamaResponseInputItem(
        role: 'assistant',
        content: [const LlamaTextPart('The card is red.')],
      ),
      LlamaResponseInputItem(
        role: 'user',
        content: [
          const LlamaTextPart(
            'Correction: the card is green. What color is it?',
          ),
        ],
      ),
    ]);
    if (!answer.toLowerCase().contains('green')) {
      throw StateError('Correction was ignored: $answer');
    }
    return answer;
  });
  if (output.containsKey('greetingError') ||
      output.containsKey('correctionError')) {
    exit(2);
  }
}

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

  await stage('greeting', () async {
    final answer = await ask([const LlamaTextPart('hi')], maxTokens: 32);
    if (!RegExp(r'^(hi|hello|hey)\b', caseSensitive: false).hasMatch(answer) ||
        answer.length > 80) {
      throw StateError('Unrelated or excessively long greeting: $answer');
    }
    return answer;
  });

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
    final firstHash = await sha256
        .bind(File(frames[0]['path']! as String).openRead())
        .first;
    final secondHash = await sha256
        .bind(File(frames[1]['path']! as String).openRead())
        .first;
    if (firstHash.toString() == secondHash.toString()) {
      throw StateError('Video frame seeking returned the same frame twice.');
    }
    final answer = await ask(parts, maxTokens: 32);
    final red = answer.toLowerCase().indexOf('red');
    final green = answer.toLowerCase().indexOf('green');
    if (red < 0 || green < 0 || red >= green) {
      throw StateError('Video answer did not identify red then green: $answer');
    }
    return {'durationMs': duration, 'frames': frames, 'answer': answer};
  }, timeout: const Duration(minutes: 8));
  await stopIfFailed('video');
  final flashPath = args.length > 6
      ? args[6]
      : 'D:/LocalAIChat/fixtures/brief_blue_flash.mp4';
  if (await File(flashPath).exists()) {
    await stage('brief_video_change', () async {
      final duration = (await VideoDuration.read(flashPath)).inMilliseconds;
      final frames = await VideoSampler.sample(
        video: flashPath,
        durationMs: duration,
        frameLimit: 8,
        outputDir: Directory(
          '${report.parent.path}${Platform.pathSeparator}sampled_flash',
        ),
      );
      final times = frames.map((frame) => frame.timeMs).toList();
      var blueSeen = false;
      for (final frame in frames) {
        final codec = await ui.instantiateImageCodec(
          await File(frame.path).readAsBytes(),
        );
        try {
          final image = (await codec.getNextFrame()).image;
          try {
            final pixels = await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            if (pixels == null)
              throw StateError('Could not inspect extracted frame.');
            final offset =
                ((image.height ~/ 2) * image.width + image.width ~/ 2) * 4;
            final rgb = pixels.buffer.asUint8List(offset, 3);
            if (rgb[2] > rgb[0] * 2 && rgb[2] > rgb[1] * 2) blueSeen = true;
          } finally {
            image.dispose();
          }
        } finally {
          codec.dispose();
        }
      }
      if (!blueSeen) {
        throw StateError('Brief blue change was missed: $times');
      }
      return times;
    }, timeout: const Duration(minutes: 8));
    await stopIfFailed('brief_video_change');
  }
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
