import 'package:flutter_test/flutter_test.dart';

import 'package:local_ai_chat/user_profile.dart';

void main() {
  test('missing or underage profile never grants adult access', () {
    expect(const UserProfile().isAdult, isFalse);
    expect(const UserProfile(setupComplete: true, age: 17).isAdult, isFalse);
    expect(const UserProfile(setupComplete: true, age: 18).isAdult, isTrue);
    expect(
      UserProfile.fromJson({'age': 250, 'setupComplete': true}).isAdult,
      isFalse,
    );
  });

  test(
    'profile round trips and supplies only disclosed facts to the model',
    () {
      const profile = UserProfile(
        setupComplete: true,
        age: 29,
        gender: 'Woman',
        pronouns: 'she/her',
      );
      final restored = UserProfile.fromJson(profile.toJson());
      expect(restored.setupComplete, isTrue);
      expect(restored.age, 29);
      expect(restored.modelInstructions, contains('she/her'));
      expect(restored.modelInstructions, contains('29 years old'));
      expect(const UserProfile(setupComplete: true).modelInstructions, isEmpty);
    },
  );
}
