import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Stable, user-facing error codes. Never show raw exceptions: they can contain
/// file paths, request bodies, or credentials.
enum IssueArea {
  app('APP'),
  fish('FISH'),
  voice('VOICE'),
  microphone('MIC'),
  model('MODEL'),
  download('DOWNLOAD'),
  media('MEDIA'),
  imageEdit('EDIT'),
  profile('PROFILE');

  const IssueArea(this.prefix);
  final String prefix;
}

class AppIssue implements Exception {
  const AppIssue(this.code, this.summary, this.why, this.next);

  final String code;
  final String summary;
  final String why;
  final String next;

  String get display => '$code · $summary $why $next';

  @override
  String toString() => display;

  static AppIssue fishHttp(int status) => switch (status) {
    400 || 422 => AppIssue(
      'FISH-$status',
      'Fish Audio could not make that voice reply.',
      'The request was rejected, possibly because the voice ID or selected model is unavailable.',
      'Check the voice ID in Settings and try a short voice test.',
    ),
    401 => const AppIssue(
      'FISH-401',
      'Fish Audio rejected the API key.',
      'The saved key is missing, expired, or invalid.',
      'Replace it in Voice settings.',
    ),
    402 => const AppIssue(
      'FISH-402',
      'Fish Audio could not bill this voice request.',
      'The account may be out of credits or require a billing change.',
      'Check the Fish Audio account or switch to a device voice.',
    ),
    403 => const AppIssue(
      'FISH-403',
      'Fish Audio denied access.',
      'This account may not have access to the selected voice or model.',
      'Check the account and choose an accessible voice.',
    ),
    404 => const AppIssue(
      'FISH-404',
      'Fish Audio could not find that voice.',
      'The saved voice ID may have changed or been removed.',
      'Choose another Fish voice in Settings.',
    ),
    429 => const AppIssue(
      'FISH-429',
      'Fish Audio is limiting requests.',
      'The account or service has reached a request limit.',
      'Wait a little, then try again.',
    ),
    >= 500 => AppIssue(
      'FISH-$status',
      'Fish Audio is unavailable right now.',
      'Its server returned an error.',
      'Try again later or switch to a device voice.',
    ),
    _ => AppIssue(
      'FISH-$status',
      'Fish Audio did not accept the request.',
      'Its server returned HTTP $status.',
      'Check your voice settings and try again.',
    ),
  };

  static AppIssue from(Object error, {IssueArea area = IssueArea.app}) {
    if (error is AppIssue) return error;
    if (error is TimeoutException) {
      return AppIssue(
        '${area.prefix}-408',
        'The request took too long.',
        area == IssueArea.fish
            ? 'Fish Audio did not finish sending speech in time.'
            : 'The operation did not finish in time.',
        'Check your connection and try again.',
      );
    }
    if (error is SocketException || error is HandshakeException) {
      return AppIssue(
        '${area.prefix}-503',
        'Could not connect.',
        'The network connection or secure connection failed.',
        'Check internet access and try again.',
      );
    }
    if (error is PlatformException) {
      final code = error.code.toLowerCase();
      final details = (error.message ?? '').toLowerCase();
      if (code == 'darwinaudioerror' || details.contains('audio session')) {
        return const AppIssue(
          'VOICE-201',
          'The voice could not play on this iPhone.',
          'iOS could not configure its audio session. The speech request may have succeeded, but playback did not start.',
          'End another recording or call, reconnect headphones if needed, and retry.',
        );
      }
      if (code.contains('permission') || details.contains('permission')) {
        return AppIssue(
          '${area.prefix}-403',
          'Access was denied.',
          'The phone did not grant access for this action.',
          'Allow access in system Settings, then try again.',
        );
      }
      if (code == 'model_invalid' || code.contains('model_load')) {
        return const AppIssue(
          'EDIT-422',
          'The image model could not load.',
          'Its files may be incomplete or the phone may not have enough memory.',
          'Check the installed model and close other apps before retrying.',
        );
      }
      return AppIssue(
        '${area.prefix}-502',
        'The phone could not complete this action.',
        'A device feature returned an error.',
        'Try again; if it repeats, report this code.',
      );
    }
    if (error is FileSystemException) {
      return AppIssue(
        '${area.prefix}-507',
        'Could not read or save a file.',
        'The file may be missing, inaccessible, or storage may be full.',
        'Check free space and select the file again.',
      );
    }
    if (error is FormatException) {
      return AppIssue(
        '${area.prefix}-422',
        'This file or response is not valid.',
        'It does not have the expected format.',
        'Choose a compatible file or download it again.',
      );
    }
    final detail = error.toString().toLowerCase();
    if (detail.contains('checksum') || detail.contains('sha-256')) {
      return AppIssue(
        '${area.prefix}-460',
        'The downloaded file did not pass verification.',
        'Its contents differ from the expected model file.',
        'Delete the partial download and try again.',
      );
    }
    if (detail.contains('no space left') ||
        detail.contains('insufficient storage')) {
      return AppIssue(
        '${area.prefix}-507',
        'There is not enough free storage.',
        'The phone could not save the file.',
        'Free space on the phone, then retry.',
      );
    }
    if (detail.contains('connection reset') ||
        detail.contains('connection closed') ||
        detail.contains('network is unreachable')) {
      return AppIssue(
        '${area.prefix}-503',
        'The connection stopped.',
        'The download or request lost its network connection.',
        'Reconnect and retry.',
      );
    }
    final httpStatus = RegExp(r'http(?:exception:)?\s+(\d{3})')
        .firstMatch(detail);
    if (httpStatus != null) {
      final status = int.parse(httpStatus.group(1)!);
      return AppIssue(
        '${area.prefix}-$status',
        'The download server rejected the request.',
        'It returned HTTP $status.',
        status >= 500
            ? 'Try again later.'
            : 'Check the download source and try again.',
      );
    }
    if (detail.contains('download ended early')) {
      return AppIssue(
        '${area.prefix}-206',
        'The download stopped before finishing.',
        'The received file is incomplete.',
        'Tap download again to resume.',
      );
    }
    if (detail.contains('incomplete') || detail.contains('missing the files')) {
      return AppIssue(
        '${area.prefix}-422',
        'The installed files are incomplete.',
        'A required model file is missing.',
        'Run the install again.',
      );
    }
    if (detail.contains('cancelled') || detail.contains('canceled')) {
      return AppIssue(
        '${area.prefix}-499',
        'The action was cancelled.',
        'It stopped before finishing.',
        'Start it again when ready.',
      );
    }
    if (area == IssueArea.microphone && detail.contains('permission')) {
      return const AppIssue(
        'MIC-403',
        'Microphone access is off.',
        'The phone did not allow recording.',
        'Enable microphone access in system Settings.',
      );
    }
    if (area == IssueArea.microphone &&
        (detail.contains('no speech detected') ||
            detail.contains('no microphone recording'))) {
      return const AppIssue(
        'MIC-204',
        'No speech was captured.',
        'The recording was silent or did not save.',
        'Check the microphone and speak again.',
      );
    }
    if (area == IssueArea.voice && detail.contains('set up speech')) {
      return const AppIssue(
        'VOICE-101',
        'Voice is not set up.',
        'No speech service is available for this chat.',
        'Open Voice settings and choose a voice.',
      );
    }
    if (area == IssueArea.model &&
        (detail.contains('llama.cpp context') ||
            detail.contains('out of memory') ||
            detail.contains('failed to load model'))) {
      return const AppIssue(
        'MODEL-507',
        'The model could not load.',
        'The phone could not prepare the model; low memory or an incomplete file may be responsible.',
        'Close other apps, choose Quick mode or download the model again.',
      );
    }
    if (area == IssueArea.model &&
        (detail.contains('mtmd context') ||
            detail.contains('projector') ||
            detail.contains('mmproj'))) {
      return const AppIssue(
        'MODEL-422',
        'The vision model could not open this image.',
        'Its vision projector may be missing, mismatched, or incompatible.',
        'Check the model and matching projector in Models.',
      );
    }
    if (area == IssueArea.voice &&
        (detail.contains('offline tts') ||
            detail.contains('speech synthesis'))) {
      return const AppIssue(
        'VOICE-501',
        'The device voice could not be created.',
        'The speech model failed to load or produce audio.',
        'Check the offline voice pack or choose another voice.',
      );
    }
    return AppIssue(
      '${area.prefix}-900',
      'This action could not finish.',
      'The app received an unexpected error.',
      'Try again; if it repeats, report this code.',
    );
  }
}
