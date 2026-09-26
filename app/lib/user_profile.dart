class UserProfile {
  const UserProfile({
    this.setupComplete = false,
    this.age,
    this.gender = 'Prefer not to say',
    this.pronouns = 'Prefer not to say',
  });

  final bool setupComplete;
  final int? age;
  final String gender;
  final String pronouns;

  bool get isAdult => age != null && age! >= 18;

  Map<String, dynamic> toJson() => {
    'setupComplete': setupComplete,
    'age': age,
    'gender': gender,
    'pronouns': pronouns,
  };

  factory UserProfile.fromJson(Map<String, dynamic>? data) {
    if (data == null) return const UserProfile();
    final value = data['age'];
    final parsedAge = value is int && value >= 1 && value <= 120 ? value : null;
    return UserProfile(
      setupComplete: data['setupComplete'] == true,
      age: parsedAge,
      gender: (data['gender'] as String? ?? 'Prefer not to say').trim(),
      pronouns: (data['pronouns'] as String? ?? 'Prefer not to say').trim(),
    );
  }

  String get modelInstructions {
    final facts = <String>[];
    if (age != null)
      facts.add('The user reported that they are $age years old');
    if (gender.isNotEmpty && gender != 'Prefer not to say') {
      facts.add('their gender is $gender');
    }
    if (pronouns.isNotEmpty && pronouns != 'Prefer not to say') {
      facts.add('their pronouns are $pronouns');
    }
    if (facts.isEmpty) return '';
    return 'User-provided profile: ${facts.join('; ')}. Use these details only when relevant. Address the user with their stated pronouns; do not guess any unstated identity details or repeat profile details unnecessarily. Newer corrections from the user take priority.';
  }
}
