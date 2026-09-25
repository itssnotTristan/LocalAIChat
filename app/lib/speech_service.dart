import 'dart:io';
import 'dart:isolate';

import 'package:audioplayers/audioplayers.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

class SpeechService {
  SpeechService(this.root);
  final String root;
  final AudioRecorder recorder = AudioRecorder();
  final AudioPlayer player = AudioPlayer();
  bool recording = false;
  bool speaking = false;

  String get asrDir => '$root/sherpa-onnx-moonshine-tiny-en-int8';
  String get ttsDir => '$root/vits-ljs';

  Future<bool> get modelsReady => hasModels(root);

  static Future<bool> hasModels(String root) async {
    final asrDir = '$root/sherpa-onnx-moonshine-tiny-en-int8';
    final ttsDir = '$root/vits-ljs';
    final files = [
      '$asrDir/preprocess.onnx',
      '$asrDir/encode.int8.onnx',
      '$asrDir/uncached_decode.int8.onnx',
      '$asrDir/cached_decode.int8.onnx',
      '$asrDir/tokens.txt',
      '$ttsDir/vits-ljs.onnx',
      '$ttsDir/tokens.txt',
      '$ttsDir/lexicon.txt',
    ];
    for (final path in files) {
      if (!await File(path).exists()) return false;
    }
    return true;
  }

  Future<void> startRecording(String outputPath) async {
    if (!await recorder.hasPermission())
      throw StateError('Microphone permission denied.');
    if (speaking) await stopSpeaking();
    await recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
        echoCancel: true,
        noiseSuppress: true,
      ),
      path: outputPath,
    );
    recording = true;
  }

  Future<String> stopAndTranscribe() async {
    final path = await recorder.stop();
    recording = false;
    if (path == null || !await File(path).exists()) {
      throw StateError('No microphone recording was saved.');
    }
    final rootPath = root;
    return Isolate.run(() => _transcribe(rootPath, path));
  }

  Future<String> transcribeFile(String wavPath) {
    final rootPath = root;
    return Isolate.run(() => _transcribe(rootPath, wavPath));
  }

  static String _transcribe(String root, String wavPath) {
    sherpa.initBindings();
    final folder = '$root/sherpa-onnx-moonshine-tiny-en-int8';
    final recognizer = sherpa.OfflineRecognizer(
      sherpa.OfflineRecognizerConfig(
        model: sherpa.OfflineModelConfig(
          moonshine: sherpa.OfflineMoonshineModelConfig(
            preprocessor: '$folder/preprocess.onnx',
            encoder: '$folder/encode.int8.onnx',
            uncachedDecoder: '$folder/uncached_decode.int8.onnx',
            cachedDecoder: '$folder/cached_decode.int8.onnx',
          ),
          tokens: '$folder/tokens.txt',
          modelType: 'moonshine',
          numThreads: 2,
          debug: false,
        ),
      ),
    );
    final stream = recognizer.createStream();
    try {
      final audio = sherpa.readWave(wavPath);
      stream.acceptWaveform(
        samples: audio.samples,
        sampleRate: audio.sampleRate,
      );
      recognizer.decode(stream);
      return recognizer.getResult(stream).text.trim();
    } finally {
      stream.free();
      recognizer.free();
    }
  }

  Future<String> synthesize(String text, String outputPath) {
    final rootPath = root;
    return Isolate.run(() => _synthesize(rootPath, text, outputPath));
  }

  static String _synthesize(String root, String text, String outputPath) {
    sherpa.initBindings();
    final folder = '$root/vits-ljs';
    final tts = sherpa.OfflineTts(
      sherpa.OfflineTtsConfig(
        model: sherpa.OfflineTtsModelConfig(
          vits: sherpa.OfflineTtsVitsModelConfig(
            model: '$folder/vits-ljs.onnx',
            tokens: '$folder/tokens.txt',
            lexicon: '$folder/lexicon.txt',
          ),
          numThreads: 2,
          debug: false,
        ),
      ),
    );
    try {
      final audio = tts.generate(text: text, sid: 0, speed: 1.0);
      if (audio.samples.isEmpty || audio.sampleRate <= 0) {
        throw StateError('Local speech synthesis produced no audio.');
      }
      final wrote = sherpa.writeWave(
        filename: outputPath,
        samples: audio.samples,
        sampleRate: audio.sampleRate,
      );
      if (!wrote) throw StateError('Could not save synthesized speech.');
      return outputPath;
    } finally {
      tts.free();
    }
  }

  Future<void> playFile(String path) async {
    await player.stop();
    speaking = true;
    try {
      await player.play(DeviceFileSource(path));
      await player.onPlayerComplete.first;
    } finally {
      speaking = false;
    }
  }

  Future<void> stopSpeaking() async {
    await player.stop();
    speaking = false;
  }

  Future<void> dispose() async {
    await recorder.dispose();
    await player.dispose();
  }
}
