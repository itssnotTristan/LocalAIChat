import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'speech_text.dart';
import 'app_issue.dart';

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
    try {
      if (value.isEmpty) {
        await _store.delete(key: _keyName);
      } else {
        await _store.write(key: _keyName, value: value);
        // Verify that the iOS Keychain or Android secure storage retained it.
        if (await _store.read(key: _keyName) != value) {
          throw const AppIssue(
            'FISH-103',
            'The Fish Audio key was not saved.',
            'Secure storage did not retain the value after writing it.',
            'Restart the app and save the key again.',
          );
        }
      }
    } on AppIssue {
      rethrow;
    } catch (_) {
      throw const AppIssue(
        'FISH-103',
        'The Fish Audio key could not be saved.',
        'Device secure storage returned an error.',
        'Restart the app and save the key again.',
      );
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

  static bool hasMp3Header(List<int> firstBytes) =>
      firstBytes.length >= 3 &&
      (firstBytes[0] == 0x49 &&
              firstBytes[1] == 0x44 &&
              firstBytes[2] == 0x33 ||
          firstBytes[0] == 0xff && (firstBytes[1] & 0xe0) == 0xe0);

  static Future<String> synthesize(
    String text,
    String voiceId,
    String outputPath,
  ) async {
    final String? key;
    try {
      key = await _store.read(key: _keyName);
    } catch (_) {
      throw const AppIssue(
        'FISH-103',
        'The Fish Audio key could not be read.',
        'Secure storage on this device returned an error.',
        'Restart the app and save the key again.',
      );
    }
    if (key == null || key.isEmpty)
      throw const AppIssue(
        'FISH-101',
        'No Fish Audio key is saved.',
        'Fish Audio requires your own API key to make speech.',
        'Add a key in Voice settings.',
      );
    final selectedId = voiceIdFromInput(voiceId);
    if (selectedId.isEmpty)
      throw const AppIssue(
        'FISH-102',
        'No Fish voice is selected.',
        'A voice ID is needed for speech.',
        'Choose a Fish voice in Voice settings.',
      );
    final HttpClientResponse response;
    try {
      final request = await _client
          .postUrl(endpoint)
          .timeout(const Duration(seconds: 15));
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
      response = await request.close().timeout(const Duration(seconds: 30));
    } catch (error) {
      throw AppIssue.from(error, area: IssueArea.fish);
    }
    if (response.statusCode != HttpStatus.ok) {
      try {
        await response.drain<void>().timeout(const Duration(seconds: 5));
      } catch (_) {
        // The HTTP status is already sufficient to explain the failure.
      }
      throw AppIssue.fishHttp(response.statusCode);
    }
    final contentType = response.headers.contentType?.mimeType ?? '';
    if (contentType.contains('json') || contentType.contains('text/')) {
      try {
        await response.drain<void>().timeout(const Duration(seconds: 5));
      } catch (_) {
        // Never display the raw response; it may echo private request data.
      }
      throw const AppIssue(
        'FISH-502',
        'Fish Audio returned no playable speech.',
        'Its response was text instead of an audio file.',
        'Check the voice settings and retry.',
      );
    }
    final output = File(outputPath);
    final sink = output.openWrite();
    var bytes = 0;
    final firstBytes = <int>[];
    try {
      await for (final chunk in response.timeout(const Duration(seconds: 90))) {
        bytes += chunk.length;
        for (final byte in chunk) {
          if (firstBytes.length >= 3) break;
          firstBytes.add(byte);
        }
        if (bytes > 20 * 1024 * 1024)
          throw const AppIssue(
            'FISH-413',
            'The voice reply was too large.',
            'Fish Audio sent more audio than this app accepts.',
            'Use a shorter reply and retry.',
          );
        sink.add(chunk);
      }
      await sink.flush();
    } catch (error) {
      await sink.close();
      if (await output.exists()) await output.delete();
      throw AppIssue.from(error, area: IssueArea.fish);
    }
    await sink.close();
    if (bytes < 100) {
      await output.delete();
      throw const AppIssue(
        'FISH-204',
        'Fish Audio returned an empty voice reply.',
        'The response did not contain enough audio to play.',
        'Try again or choose another voice.',
      );
    }
    if (!hasMp3Header(firstBytes)) {
      await output.delete();
      throw const AppIssue(
        'FISH-502',
        'Fish Audio returned no playable speech.',
        'The downloaded file was not an MP3 audio reply.',
        'Check the voice settings and retry.',
      );
    }
    return outputPath;
  }
}
