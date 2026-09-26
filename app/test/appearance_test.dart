import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_chat/app_icon.dart';
import 'package:local_ai_chat/glass_design.dart';

void main() {
  test('bundled icon names map to the iOS choices', () {
    expect(AppIconChoice.fromNativeName(null), AppIconChoice.plasma);
    expect(
      AppIconChoice.fromNativeName('AppIconOrange'),
      AppIconChoice.orange,
    );
    expect(
      AppIconChoice.fromNativeName('AppIconElectric'),
      AppIconChoice.electric,
    );
  });

  testWidgets('My Photo renders the selected local image', (tester) async {
    final photo = File('assets/icons/plasma.png').absolute;
    expect(await tester.runAsync(photo.exists), isTrue);
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
          backgroundStyle: 'My Photo',
          backgroundImagePath: photo.path,
          backgroundPhotoDim: 0.4,
          child: const Scaffold(body: GlassBackground()),
        ),
      ),
    );
    final image = tester.widget<Image>(find.byType(Image));
    final resized = image.image as ResizeImage;
    expect((resized.imageProvider as FileImage).file.path, photo.path);
  });
}
