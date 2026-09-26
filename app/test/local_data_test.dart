import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_chat/main.dart';

void main() {
  test('conversation and timestamped media survive local JSON encoding', () {
    final conversation = Conversation('one', 'Video test', [
      ChatEntry(
        'user',
        'Describe this clip',
        [MediaFrame('frame.jpg', 1500)],
        'original.mov',
        'playback.mp4',
      ),
      ChatEntry('assistant', 'A red car appears.'),
    ]);
    final restored = Conversation.fromJson(conversation.toJson());
    expect(
      restored.entries
          .singleWhere((item) => item.role == 'user')
          .frames
          .single
          .timeMs,
      1500,
    );
    expect(restored.entries.last.text, 'A red car appears.');
    expect(restored.entries.first.videoPath, 'original.mov');
    expect(restored.entries.first.playbackPath, 'playback.mp4');
  });

  test('text history keeps user context but drops an old video caption', () {
    final history = [
      ChatEntry('user', 'How are you?'),
      ChatEntry('assistant', 'Good.'),
      ChatEntry('user', 'Describe this clip', [MediaFrame('frame.jpg', 1500)]),
      ChatEntry('assistant', 'A mistaken scene description.'),
      ChatEntry('user', 'My card is green.'),
      ChatEntry('assistant', 'Okay, green.'),
    ];
    expect(textHistorySinceMedia(history).map((entry) => entry.text), [
      'How are you?',
      'Good.',
      'Describe this clip',
      'My card is green.',
      'Okay, green.',
    ]);
  });

  test('follow-up can see the prior user message after an attachment', () {
    final history = [
      ChatEntry('user', 'My friend is asleep on the sofa.', [
        MediaFrame('a.jpg'),
      ]),
      ChatEntry('assistant', 'A room is visible.'),
      ChatEntry('user', 'Why is she there?'),
    ];
    final kept = textHistorySinceMedia(history);
    expect(kept.map((entry) => entry.text), [
      'My friend is asleep on the sofa.',
      'Why is she there?',
    ]);
  });
}
