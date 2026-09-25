import 'dart:io';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

void main(List<String> args) {
  final root = args.isEmpty ? 'D:/LocalAIChat/speech' : args.first;
  sherpa.initBindings();
  final asr = '$root/sherpa-onnx-moonshine-tiny-en-int8';
  final recognizer = sherpa.OfflineRecognizer(
    sherpa.OfflineRecognizerConfig(
      model: sherpa.OfflineModelConfig(
        moonshine: sherpa.OfflineMoonshineModelConfig(
          preprocessor: '$asr/preprocess.onnx',
          encoder: '$asr/encode.int8.onnx',
          uncachedDecoder: '$asr/uncached_decode.int8.onnx',
          cachedDecoder: '$asr/cached_decode.int8.onnx',
        ),
        tokens: '$asr/tokens.txt',
        modelType: 'moonshine',
        numThreads: 2,
        debug: false,
      ),
    ),
  );
  final stream = recognizer.createStream();
  try {
    final audio = sherpa.readWave('$asr/test_wavs/0.wav');
    stream.acceptWaveform(samples: audio.samples, sampleRate: audio.sampleRate);
    recognizer.decode(stream);
    stdout.writeln('ASR: ${recognizer.getResult(stream).text}');
  } finally {
    stream.free();
    recognizer.free();
  }
  final tts = '$root/vits-ljs';
  final synthesizer = sherpa.OfflineTts(
    sherpa.OfflineTtsConfig(
      model: sherpa.OfflineTtsModelConfig(
        vits: sherpa.OfflineTtsVitsModelConfig(
          model: '$tts/vits-ljs.onnx',
          tokens: '$tts/tokens.txt',
          lexicon: '$tts/lexicon.txt',
        ),
        numThreads: 2,
        debug: false,
      ),
    ),
  );
  try {
    final audio = synthesizer.generate(text: 'The local voice is working.');
    final output = '$root/speech_test.wav';
    if (!sherpa.writeWave(
      filename: output,
      samples: audio.samples,
      sampleRate: audio.sampleRate,
    )) {
      throw StateError('Could not write TTS WAV.');
    }
    stdout.writeln('TTS: $output (${File(output).lengthSync()} bytes)');
  } finally {
    synthesizer.free();
  }
}
