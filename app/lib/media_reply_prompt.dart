enum MediaReplyStyle { conversational, descriptive }

extension MediaReplyStyleName on MediaReplyStyle {
  String get label => switch (this) {
    MediaReplyStyle.conversational => 'Conversational',
    MediaReplyStyle.descriptive => 'Descriptive',
  };
}

MediaReplyStyle mediaReplyStyleFromName(String? name) =>
    MediaReplyStyle.values.where((style) => style.name == name).firstOrNull ??
    MediaReplyStyle.conversational;

String mediaReplyPrompt({
  required MediaReplyStyle style,
  required bool isVideo,
}) {
  if (style == MediaReplyStyle.descriptive) {
    return isVideo
        ? 'Describe the main visible action across these frames in 2 or 3 concise sentences. State clearly visible adult nudity or sexual activity plainly. Do not infer unseen anatomy, movement, or dialogue.'
        : 'Describe the main visible action in these images in 2 or 3 concise sentences. State clearly visible adult nudity or sexual activity plainly. Do not invent covered or unseen anatomy.';
  }
  return isVideo
      ? 'Answer the user’s actual question about this video as a natural conversation, in the selected chat personality. Read the user’s text before describing frames; a video attachment is not automatically a request for a caption. If they ask what you think, lead with a candid, relevant reaction or opinion; do not just narrate frames. Then briefly mention the visible action that supports your response. You may speak plainly about clearly visible adult nudity or sexual activity. Use relationship or activity details supplied by the user as context, but do not claim the frames prove anything unseen, including anatomy, penetration, sensations, or consent. Do not invent dialogue, motives, or background events.'
      : 'Answer the user’s actual question about these images as a natural conversation, in the selected chat personality. Read the user’s text before describing the image; an attachment is not automatically a request for a caption. If they ask what you think, lead with a candid, relevant reaction or opinion; do not just produce a caption. Mention clearly visible adult nudity or sexual activity plainly when relevant. Use details supplied by the user as context, but do not claim to see covered or unseen anatomy, sensations, or intent. Avoid repetitive body-part lists.';
}
