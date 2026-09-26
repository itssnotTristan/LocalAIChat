import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A local gate for the sideloaded preview. Payment products are not offered
/// by this build, so the UI must never describe this as a paid subscription.
class UncensoredAccess {
  static const _storage = FlutterSecureStorage();
  static const _key = 'uncensored_owner_preview_v1';
  static const _ownerHash =
      'B6FB0EA46AB26EC801B53174472F22ABC5BFA269E56483E485906F186091236C';

  static Future<bool> get isUnlocked async =>
      await _storage.read(key: _key) == _ownerHash;

  static Future<bool> unlock(String code) async {
    final normalized = code.toUpperCase().replaceAll(RegExp(r'[^A-F0-9]'), '');
    final actual = sha256
        .convert(utf8.encode(normalized))
        .toString()
        .toUpperCase();
    if (actual != _ownerHash) return false;
    await _storage.write(key: _key, value: _ownerHash);
    return true;
  }

  static Future<void> lock() => _storage.delete(key: _key);
}

bool isUncensoredModelName(String name) {
  final value = name.toLowerCase();
  return value.contains('abliterated') ||
      value.contains('uncensored') ||
      value.contains('nymphaea') ||
      value.contains('adult roleplay');
}

/// Catches direct requests for adult erotic chat without sending the prompt to
/// a model. This is a helpful gate, not a complete semantic classifier.
bool isExplicitAdultTopic(String text) {
  final value = text.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  if (value.isEmpty) return false;
  return RegExp(
    r'\b(porn|pornography|erotica|erotic|horny|sext|sexting|masturbat\w*|'
    r'orgasm\w*|arous\w*|nude|naked|topless|genitals?|penis|vagina|vulva|'
    r'clitoris|nipples?|fuck(?:ing|ed)?|cock|pussy|cum|blowjob|handjob)\b|'
    r'\b(sex|sexual)\s+(scene|roleplay|fantasy|talk|chat|act|story)\b',
  ).hasMatch(value);
}
