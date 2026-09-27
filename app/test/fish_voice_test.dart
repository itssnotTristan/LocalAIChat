import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_chat/fish_voice.dart';
import 'package:local_ai_chat/app_issue.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Fish API key survives a settings-style save and later read', () async {
    const channel = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    String? saved;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'write':
              saved = (call.arguments as Map)['value'] as String;
              return null;
            case 'read':
              return saved;
            case 'delete':
              saved = null;
              return null;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    await FishVoice.saveKey('  test-secret  ');
    expect(saved, 'test-secret');
    expect(await FishVoice.hasKey, isTrue);
    await FishVoice.saveKey('');
    expect(await FishVoice.hasKey, isFalse);
  });

  test('Fish key save reports a write that Keychain did not retain', () async {
    const channel = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'read') return null;
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    expect(
      FishVoice.saveKey('test-secret'),
      throwsA(
        isA<AppIssue>().having((issue) => issue.code, 'code', 'FISH-103'),
      ),
    );
  });

  test('Fish replies split into shorter complete speech segments', () {
    expect(FishVoice.playbackChunks(''), isEmpty);
    expect(
      FishVoice.playbackChunks(
        'I can hear you clearly now. Tell me what happened next, and I will listen carefully. Then we can decide what to do.',
      ),
      [
        'I can hear you clearly now. Tell me what happened next, and I will listen carefully.',
        'Then we can decide what to do.',
      ],
    );
    expect(
      FishVoice.playbackChunks('one two three four five', targetLength: 13),
      ['one two three', 'four five'],
    );
  });

  test('Fish voice page links can be pasted instead of IDs', () {
    expect(
      FishVoice.voiceIdFromInput(
        'https://fish.audio/app/m/05b451c6e0074aa2bac4a476b0c61ffe/',
      ),
      '05b451c6e0074aa2bac4a476b0c61ffe',
    );
    expect(
      FishVoice.voiceIdFromInput(
        'https://fish.audio/text-to-speech/?modelId=abc123',
      ),
      'abc123',
    );
  });

  test('Fish speech direction follows the saved chat personality', () {
    expect(
      FishVoice.performanceText('Come closer.', 'Horny'),
      '[whisper] Come closer.',
    );
    expect(
      FishVoice.performanceText('Seriously?', 'Jerk'),
      '[angry] Seriously?',
    );
    expect(FishVoice.performanceText('Hello!', 'Default'), 'Hello!');
  });

  test('Fish failures identify account, voice, and service problems', () {
    expect(AppIssue.fishHttp(401).code, 'FISH-401');
    expect(AppIssue.fishHttp(404).display, contains('voice ID'));
    expect(AppIssue.fishHttp(429).display, contains('request limit'));
    expect(AppIssue.fishHttp(503).code, 'FISH-503');
  });

  test('Fish voice playback accepts MP3 and rejects text responses', () {
    expect(FishVoice.hasMp3Header([0x49, 0x44, 0x33]), isTrue);
    expect(FishVoice.hasMp3Header([0xff, 0xfb, 0x90]), isTrue);
    expect(FishVoice.hasMp3Header('{"e'.codeUnits), isFalse);
  });

  test(
    'audio-session errors explain playback without exposing raw details',
    () {
      final issue = AppIssue.from(
        PlatformException(
          code: 'DarwinAudioError',
          message: 'Error configuring audio session: secret-device-path',
        ),
        area: IssueArea.voice,
      );
      expect(issue.code, 'VOICE-201');
      expect(issue.display, contains('playback did not start'));
      expect(issue.display, isNot(contains('secret-device-path')));
    },
  );
}
