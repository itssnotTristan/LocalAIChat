import 'dart:async';
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
  Completer<void>? _playStopped;

  static const voices = <({String name, String gender, int id})>[
    (name: 'Adam', gender: 'Male', id: 5),
    (name: 'Michael', gender: 'Male', id: 6),
    (name: 'George', gender: 'Male', id: 9),
    (name: 'Bella', gender: 'Female', id: 1),
    (name: 'Emma', gender: 'Female', id: 7),
  ];

  String get asrDir => '$root/sherpa-onnx-moonshine-tiny-en-int8';
  String get ttsDir => '$root/kokoro-en-v0_19';

  Future<bool> get modelsReady => hasModels(root);

  static Future<bool> hasModels(String root) async {
    final asrDir = '$root/sherpa-onnx-moonshine-tiny-en-int8';
    final ttsDir = '$root/kokoro-en-v0_19';
    final files = [
      '$asrDir/preprocess.onnx',
      '$asrDir/encode.int8.onnx',
      '$asrDir/uncached_decode.int8.onnx',
      '$asrDir/cached_decode.int8.onnx',
      '$asrDir/tokens.txt',
      '$ttsDir/model.onnx',
      '$ttsDir/voices.bin',
      '$ttsDir/tokens.txt',
    ];
    for (final path in files) {
      if (!await File(path).exists()) return false;
    }
    return Directory('$ttsDir/espeak-ng-data').exists();
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
    try {
      return await Isolate.run(() => _transcribe(rootPath, path));
    } finally {
      final recording = File(path);
      if (await recording.exists()) await recording.delete();
    }
  }

  Future<double> microphoneLevel() async =>
      (await recorder.getAmplitude()).current;

  Future<void> stopRecording() async {
    final path = await recorder.stop();
    recording = false;
    if (path != null) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
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

  Future<String> synthesize(String text, String outputPath, {int voiceId = 5}) {
    final rootPath = root;
    return Isolate.run(() => _synthesize(rootPath, text, outputPath, voiceId));
  }

  static String _synthesize(
    String root,
    String text,
    String outputPath,
    int voiceId,
  ) {
    sherpa.initBindings();
    final folder = '$root/kokoro-en-v0_19';
    final tts = sherpa.OfflineTts(
      sherpa.OfflineTtsConfig(
        model: sherpa.OfflineTtsModelConfig(
          kokoro: sherpa.OfflineTtsKokoroModelConfig(
            model: '$folder/model.onnx',
            voices: '$folder/voices.bin',
            tokens: '$folder/tokens.txt',
            dataDir: '$folder/espeak-ng-data',
          ),
          numThreads: 2,
          debug: false,
        ),
      ),
    );
    try {
      final audio = tts.generate(text: text, sid: voiceId, speed: 1.0);
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
    _playStopped = Completer<void>();
    speaking = true;
    try {
      await player.play(DeviceFileSource(path));
      await Future.any([player.onPlayerComplete.first, _playStopped!.future]);
    } finally {
      speaking = false;
      _playStopped = null;
      await player.stop();
      final file = File(path);
      if (await file.exists()) {
        try {
          await file.delete();
        } on FileSystemException {
          // A platform decoder may release the file handle shortly afterward.
        }
      }
    }
  }

  Future<void> stopSpeaking() async {
    if (_playStopped != null && !_playStopped!.isCompleted)
      _playStopped!.complete();
    await player.stop();
    speaking = false;
  }

  Future<void> dispose() async {
    await recorder.dispose();
    await player.dispose();
  }
}
