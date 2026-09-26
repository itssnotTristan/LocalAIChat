import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'speech_text.dart';

/// Optional cloud speech. Local chat and transcription never use this service.
class FishVoice {
  static const _store = FlutterSecureStorage();
  static const _keyName = 'fish_audio_api_key';
  static final endpoint = Uri.parse('https://api.fish.audio/v1/tts');
  static final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..idleTimeout = const Duration(seconds: 30);

  /// Fish S2.1 supports inline direction tags. Keep them in the audio request
  /// only, so they never appear in the visible chat reply or local TTS.
  static String performanceText(
    String text,
    String personality, {
    String? directionHint,
  }) {
    final cleaned = SpeechText.prepare(text);
    if (cleaned.isEmpty) return cleaned;
    final actionDirection = directionHint ?? SpeechText.direction(text);
    final direction = switch (actionDirection ?? personality) {
      'whisper' => '[whisper] ',
      'chuckle' => '[chuckle] ',
      'Horny' => '[whisper] ',
      'Jerk' => '[angry] ',
      'Playful' => '[chuckle] ',
      _ => '',
    };
    return '$direction$cleaned';
  }

  static String voiceIdFromInput(String input) {
    final value = input.trim();
    final uri = Uri.tryParse(value);
    if (uri != null &&
        uri.scheme == 'https' &&
        (uri.host == 'fish.audio' || uri.host.endsWith('.fish.audio'))) {
      final queryId = uri.queryParameters['modelId'];
      if (queryId != null && queryId.isNotEmpty) return queryId;
      final parts = uri.pathSegments.where((part) => part.isNotEmpty).toList();
      final marker = parts.indexOf('m');
      if (marker >= 0 && marker + 1 < parts.length) return parts[marker + 1];
    }
    return value;
  }

  static Future<bool> get hasKey async =>
      (await _store.read(key: _keyName))?.isNotEmpty ?? false;

  static Future<void> saveKey(String key) async {
    final value = key.trim();
    if (value.isEmpty) {
      await _store.delete(key: _keyName);
    } else {
      await _store.write(key: _keyName, value: value);
      // Some iOS signing and Keychain configurations report a successful
      // write without making the value available to a subsequent read.
      if (await _store.read(key: _keyName) != value) {
        throw StateError(
          'The key was not retained by iPhone secure storage. Check the app signing and Keychain capability.',
        );
      }
    }
  }

  /// Shorter requests let the first part of a reply play while later parts
  /// are synthesized. Keep a whole sentence when it fits the target length.
  static List<String> playbackChunks(String text, {int targetLength = 140}) {
    final words = SpeechText.prepare(text).split(RegExp(r'\s+'));
    final chunks = <String>[];
    var current = '';
    for (final word in words) {
      if (word.isEmpty) continue;
      final wouldOverflow =
          current.isNotEmpty && current.length + word.length + 1 > targetLength;
      if (wouldOverflow) {
        chunks.add(current);
        current = '';
      }
      current = current.isEmpty ? word : '$current $word';
      if (current.length >= 80 && RegExp(r'[.!?]$').hasMatch(word)) {
        chunks.add(current);
        current = '';
      }
    }
    if (current.isNotEmpty) chunks.add(current);
    return chunks;
  }

  static Future<String> synthesize(
    String text,
    String voiceId,
    String outputPath,
  ) async {
    final key = await _store.read(key: _keyName);
    if (key == null || key.isEmpty)
      throw StateError('Add a Fish Audio API key in Voice settings.');
    final selectedId = voiceIdFromInput(voiceId);
    if (selectedId.isEmpty)
      throw StateError('Add the Fish Audio voice ID in Voice settings.');
    final request = await _client.postUrl(endpoint);
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $key');
    request.headers.contentType = ContentType.json;
    request.headers.set('model', 's2.1-pro-free');
    request.write(
      jsonEncode({
        'text': text,
        'reference_id': selectedId,
        'format': 'mp3',
        'latency': 'low',
        'chunk_length': 100,
      }),
    );
    final response = await request.close().timeout(const Duration(seconds: 30));
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      if (response.statusCode == HttpStatus.unauthorized) {
        throw const HttpException(
          'Fish Audio rejected the saved API key (401). Replace it in Voice settings.',
        );
      }
      throw HttpException(
        'Fish Audio returned HTTP ${response.statusCode}. Check the voice ID and Fish Audio account.',
      );
    }
    final contentType = response.headers.contentType?.mimeType ?? '';
    if (contentType.contains('json') || contentType.contains('text/')) {
      final message = await utf8.decoder.bind(response).join();
      throw StateError('Fish Audio did not return audio: $message');
    }
    final output = File(outputPath);
    final sink = output.openWrite();
    var bytes = 0;
    try {
      await for (final chunk in response.timeout(const Duration(seconds: 90))) {
        bytes += chunk.length;
        if (bytes > 20 * 1024 * 1024)
          throw StateError('Fish Audio response was too large.');
        sink.add(chunk);
      }
      await sink.flush();
    } catch (_) {
      await sink.close();
      if (await output.exists()) await output.delete();
      rethrow;
    }
    await sink.close();
    if (bytes < 100) {
      await output.delete();
      throw StateError('Fish Audio returned no playable audio.');
    }
    return outputPath;
  }
}
