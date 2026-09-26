/// The installed Stable Diffusion image-to-image model redraws the whole
/// 512-pixel image. It cannot reliably perform targeted clothing removal.
String? unsupportedImageEdit(String prompt) {
  final request = prompt.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  final asksForNudity = RegExp(
    r'\b(nudify|undress|unclothe)\b|'
    r'\b(make|turn)\s+(me|her|him|them|the person|this person|the subject)\s+'
    r'(look\s+)?(completely\s+)?(nude|naked|topless)\b',
  ).hasMatch(request);
  final asksToRemoveClothing = RegExp(
    r'\b(remove|erase|delete|take off|strip off|strip)\b.{0,40}'
    r'\b(shirt|top|clothes|clothing|bra|bikini|pants|underwear|dress|shorts|jacket|hoodie)\b',
  ).hasMatch(request);
  if (!asksForNudity && !asksToRemoveClothing) return null;
  return 'This image editor cannot remove clothing from a person in a photo. '
      'Its current model redraws the whole image and can distort faces and bodies. '
      'Your original is unchanged. Try a lighting, color, or background edit instead.';
}

/// Background edits need a person mask. Ordinary img2img redraws the subject.
bool isBackgroundReplacement(String prompt) {
  final request = prompt.toLowerCase();
  return RegExp(r'\bbackground\b').hasMatch(request) ||
      RegExp(r'\b(?:put|place)\s+me\s+(?:in|into|at)\b').hasMatch(request) ||
      RegExp(r"\bmake\s+it\s+look\s+like\s+(?:i am|i'm|im)\b")
          .hasMatch(request);
}

/// Removes instructions that would make the background model draw a new person.
String backgroundScenePrompt(String prompt) {
  var scene = prompt.trim();
  final background = RegExp(
    r'\bbackground\b',
    caseSensitive: false,
  ).firstMatch(scene);
  if (background != null) {
    scene = scene.substring(background.end);
  } else {
    scene = scene.replaceFirst(
      RegExp(r'\b(?:put|place)\s+me\s+(?:in|into|at)\s+', caseSensitive: false),
      '',
    );
    scene = scene.replaceFirst(
      RegExp(
        r"^make\s+it\s+look\s+like\s+(?:i\s+am|i'm|im)\s+",
        caseSensitive: false,
      ),
      '',
    );
  }
  scene = scene.replaceFirst(
    RegExp(
      r"^\s*(?:(?:look\s+like|as\s+if)\s+)?(?:i\s+am|i'm|im)\s+",
      caseSensitive: false,
    ),
    '',
  );
  scene = scene.replaceFirst(
    RegExp(r'^\s*(?:to|into|with|as|of|in)\s+', caseSensitive: false),
    '',
  );
  scene = scene.replaceFirst(RegExp(r'[.!?]+$'), '').trim();
  if (scene.isEmpty) scene = 'a natural outdoor setting';
  if (RegExp(
    r'\b(forest|woods|woodland)\b',
    caseSensitive: false,
  ).hasMatch(scene)) {
    return 'Photorealistic outdoor woodland, $scene, trees and natural '
        'forest floor filling the entire frame, daylight, eye-level photograph';
  }
  return 'Photorealistic empty scenery, $scene, natural lighting, '
      'realistic environment';
}
