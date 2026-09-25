import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_chat/video_duration.dart';

void main() {
  test('reads duration from a real two-second MP4 container', () async {
    final duration = await VideoDuration.readMp4(
      'test/fixtures/red_then_green.mp4',
    );
    expect(duration, const Duration(seconds: 2));
  });
}
