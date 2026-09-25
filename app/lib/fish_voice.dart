import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Optional cloud speech. Local chat and transcription never use this service.
class FishVoice {
  static const _store = FlutterSecureStorage();
  static const _keyName = 'fish_audio_api_key';
  static final endpoint = Uri.parse('https://api.fish.audio/v1/tts');

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
    if (key.trim().isEmpty) {
      await _store.delete(key: _keyName);
    } else {
      await _store.write(key: _keyName, value: key.trim());
    }
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
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.postUrl(endpoint);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $key');
      request.headers.contentType = ContentType.json;
      request.headers.set('model', 's2.1-pro-free');
      request.write(
        jsonEncode({'text': text, 'reference_id': selectedId, 'format': 'mp3'}),
      );
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Fish Audio returned HTTP ${response.statusCode}. Check the key and voice ID.',
        );
      }
      final output = File(outputPath);
      final sink = output.openWrite();
      var bytes = 0;
      try {
        await for (final chunk in response.timeout(
          const Duration(seconds: 90),
        )) {
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
    } finally {
      client.close(force: true);
    }
  }
}
