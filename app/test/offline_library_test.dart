import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:local_ai_chat/glass_design.dart';
import 'package:local_ai_chat/offline_library.dart';
import 'package:local_ai_chat/offline_library_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'bundled packs install locally, persist checks, and feed grounded chat',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'offline_library_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final library = OfflineLibraryRepository(directory, rootBundle);
      await library.load();

      expect(library.catalog.length, 6);
      expect(library.installed, isEmpty);
      expect(library.search('power outage'), isEmpty);

      await library.install('survival');
      expect(library.installed, contains('survival'));
      expect(library.search('power outage'), isNotEmpty);
      final reference = library.contextFor(
        'What should I do in a power outage?',
      );
      expect(reference, contains('Source:'));
      expect(reference, contains('FoodSafety.gov'));
      expect(reference, isNot(contains('Git official tutorial')));

      await library.setCompleted('survival-power', 0, true);
      await library.setFavorite('survival-power', true);
      await library.setNote(
        'survival-power',
        'Battery pack is in the front drawer.',
      );
      final reloaded = OfflineLibraryRepository(directory, rootBundle);
      await reloaded.load();
      expect(reloaded.installed, contains('survival'));
      expect(reloaded.completed, contains('survival-power:0'));
      expect(
        reloaded.notes['survival-power'],
        'Battery pack is in the front drawer.',
      );
      expect(
        reloaded.search('', favoritesOnly: true).single.card.id,
        'survival-power',
      );

      await reloaded.remove('survival');
      expect(reloaded.search('power outage'), isEmpty);
      expect(reloaded.contextFor('power outage'), isEmpty);
    },
  );

  testWidgets('installed cards render on a phone-sized view', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('library_view_'),
    ))!;
    addTearDown(() => directory.delete(recursive: true));
    final library = OfflineLibraryRepository(directory, rootBundle);
    await tester.runAsync(library.load);
    await tester.runAsync(() => library.install('survival'));
    await tester.pumpWidget(
      MaterialApp(
        home: GlassDesign(
          themeName: 'Chat Dark',
          customColor: const Color(0xFF55C8FF),
          starColor: const Color(0xFFB6DCFF),
          starBackgroundColor: const Color(0xFF091326),
          auroraColor: const Color(0xFF58F6BA),
          motion: false,
          speed: 1,
          backgroundStyle: 'Waves',
          child: OfflineLibraryPage(library: library, onAsk: (_) {}),
        ),
      ),
    );
    expect(find.text('Offline Library'), findsOneWidget);
    expect(
      find.text('1 of 6 packs installed · available without internet'),
      findsOneWidget,
    );
    expect(library.installed, contains('survival'));
    await tester.scrollUntilVisible(
      find.text('Build a three-day kit'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Build a three-day kit'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
