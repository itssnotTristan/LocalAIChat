import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_chat/uncensored_access.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a saved preview from an older build does not unlock this version',
    () async {
      const channel = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      final readKeys = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'read') {
              final key = (call.arguments as Map)['key'] as String;
              readKeys.add(key);
              return key == 'uncensored_owner_preview_v1'
                  ? 'legacy-unlock'
                  : null;
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      expect(await UncensoredAccess.isUnlocked, isFalse);
      expect(readKeys, ['uncensored_owner_preview_v2']);
      expect(await UncensoredAccess.unlock('not-the-owner-code'), isFalse);
    },
  );

  test('identifies bundled uncensored model names', () {
    expect(isUncensoredModelName('Nymphaea 4B · adult roleplay'), isTrue);
    expect(isUncensoredModelName('Qwen3 VL 4B Abliterated'), isTrue);
    expect(isUncensoredModelName('Ministral 3B · everyday chat'), isFalse);
  });

  test('direct adult requests require the owner preview', () {
    expect(isExplicitAdultTopic('I want erotic roleplay'), isTrue);
    expect(isExplicitAdultTopic('Can I send a nude photo?'), isTrue);
    expect(isExplicitAdultTopic('How do I cook pasta?'), isFalse);
    expect(isExplicitAdultTopic('What is today’s date?'), isFalse);
  });
}
