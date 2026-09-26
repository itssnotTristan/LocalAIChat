import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_chat/media_reply_prompt.dart';

void main() {
  test('media replies default to answering the user conversationally', () {
    expect(mediaReplyStyleFromName(null), MediaReplyStyle.conversational);
    final prompt = mediaReplyPrompt(
      style: MediaReplyStyle.conversational,
      isVideo: true,
    );
    expect(prompt, contains('actual question'));
    expect(prompt, contains('reaction or opinion'));
    expect(prompt, contains('selected chat personality'));
    expect(prompt, contains('do not claim the frames prove anything unseen'));
  });

  test('descriptive mode requests a scene summary', () {
    final prompt = mediaReplyPrompt(
      style: MediaReplyStyle.descriptive,
      isVideo: false,
    );
    expect(prompt, contains('Describe the main visible action'));
  });
}
