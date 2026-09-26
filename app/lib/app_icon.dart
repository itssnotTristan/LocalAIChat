import 'dart:io';

import 'package:flutter/services.dart';

enum AppIconChoice {
  plasma('Plasma', 'assets/icons/plasma.png', null),
  orange('Orange Glass', 'assets/icons/orange.png', 'AppIconOrange'),
  electric('Electric Glass', 'assets/icons/electric.png', 'AppIconElectric');

  const AppIconChoice(this.label, this.previewAsset, this.nativeName);

  final String label;
  final String previewAsset;
  final String? nativeName;

  static AppIconChoice fromNativeName(String? name) {
    for (final choice in values) {
      if (choice.nativeName == name) return choice;
    }
    return plasma;
  }
}

class AppIconService {
  static const _channel = MethodChannel('local_ai_chat/app_icon');

  static Future<bool> get supported async {
    if (!Platform.isIOS) return false;
    return await _channel.invokeMethod<bool>('supports') ?? false;
  }

  static Future<AppIconChoice> current() async {
    if (!Platform.isIOS) return AppIconChoice.plasma;
    final name = await _channel.invokeMethod<String>('current');
    return AppIconChoice.fromNativeName(name);
  }

  static Future<void> set(AppIconChoice choice) async {
    if (!Platform.isIOS) return;
    await _channel.invokeMethod<void>('set', choice.nativeName);
  }
}
