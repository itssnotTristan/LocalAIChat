import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_chat/user_profile.dart';
import 'package:local_ai_chat/user_profile_page.dart';

void main() {
  testWidgets('first launch saves a reported minor without adult access', (
    tester,
  ) async {
    UserProfile? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: UserProfilePage(
          initial: const UserProfile(),
          firstRun: true,
          onSave: (profile) async => saved = profile,
        ),
      ),
    );
    expect(find.text('Welcome to FluxLira'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '17');
    await tester.scrollUntilVisible(
      find.text('Start using FluxLira'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Start using FluxLira'));
    await tester.pump();
    expect(saved?.setupComplete, isTrue);
    expect(saved?.age, 17);
    expect(saved?.isAdult, isFalse);
  });

  testWidgets('settings can clear profile facts after an upgrade', (
    tester,
  ) async {
    UserProfile? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: UserProfilePage(
          initial: const UserProfile(
            setupComplete: true,
            age: 29,
            gender: 'Woman',
            pronouns: 'she/her',
          ),
          onSave: (profile) async => saved = profile,
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.text('Delete profile details'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Delete profile details'));
    await tester.pump();
    expect(saved?.age, isNull);
    expect(saved?.gender, 'Prefer not to say');
    expect(saved?.pronouns, 'Prefer not to say');
    expect(saved?.setupComplete, isTrue);
  });
}
