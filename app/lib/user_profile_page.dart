import 'dart:io';

import 'package:flutter/material.dart';

import 'user_profile.dart';

class UserProfilePage extends StatefulWidget {
  const UserProfilePage({
    super.key,
    required this.initial,
    required this.onSave,
    this.firstRun = false,
  });

  final UserProfile initial;
  final Future<void> Function(UserProfile) onSave;
  final bool firstRun;

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  late final TextEditingController ageController;
  late final TextEditingController customGenderController;
  late final TextEditingController customPronounsController;
  late String gender;
  late String pronouns;
  bool saving = false;
  String? error;

  static const genderChoices = [
    'Woman',
    'Man',
    'Nonbinary',
    'Self describe',
    'Prefer not to say',
  ];
  static const pronounChoices = [
    'she/her',
    'he/him',
    'they/them',
    'Self describe',
    'Prefer not to say',
  ];

  @override
  void initState() {
    super.initState();
    ageController = TextEditingController(
      text: widget.initial.age?.toString() ?? '',
    );
    gender = genderChoices.contains(widget.initial.gender)
        ? widget.initial.gender
        : 'Self describe';
    customGenderController = TextEditingController(
      text: gender == 'Self describe' ? widget.initial.gender : '',
    );
    pronouns = pronounChoices.contains(widget.initial.pronouns)
        ? widget.initial.pronouns
        : 'Self describe';
    customPronounsController = TextEditingController(
      text: pronouns == 'Self describe' ? widget.initial.pronouns : '',
    );
  }

  @override
  void dispose() {
    ageController.dispose();
    customGenderController.dispose();
    customPronounsController.dispose();
    super.dispose();
  }

  Future<void> saveProfile() async {
    final rawAge = ageController.text.trim();
    final age = rawAge.isEmpty ? null : int.tryParse(rawAge);
    if (rawAge.isNotEmpty && (age == null || age < 1 || age > 120)) {
      setState(() => error = 'Enter an age from 1 to 120, or leave it blank.');
      return;
    }
    final chosenGender = gender == 'Self describe'
        ? customGenderController.text.trim()
        : gender;
    final chosenPronouns = pronouns == 'Self describe'
        ? customPronounsController.text.trim()
        : pronouns;
    if (gender == 'Self describe' && chosenGender.isEmpty ||
        pronouns == 'Self describe' && chosenPronouns.isEmpty) {
      setState(
        () => error =
            'Fill in the custom identity fields or choose another option.',
      );
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.onSave(
        UserProfile(
          setupComplete: true,
          age: age,
          gender: chosenGender.length > 40
              ? chosenGender.substring(0, 40)
              : chosenGender,
          pronouns: chosenPronouns.length > 40
              ? chosenPronouns.substring(0, 40)
              : chosenPronouns,
        ),
      );
      if (mounted && !widget.firstRun) Navigator.of(context).pop();
    } catch (failure) {
      if (mounted)
        setState(() => error = 'Could not save your profile: $failure');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: widget.firstRun ? null : AppBar(title: const Text('Your profile')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 16),
              Icon(
                Icons.bolt,
                size: 56,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                widget.firstRun ? 'Welcome to FluxLira' : 'Your profile',
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                'These details stay on this device and help the AI address you correctly. You can change or delete them in Settings.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              TextField(
                controller: ageController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Age',
                  helperText: 'Optional. Adult-only features require a reported age of 18 or older.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: gender,
                decoration: const InputDecoration(
                  labelText: 'Gender',
                  border: OutlineInputBorder(),
                ),
                items: genderChoices
                    .map(
                      (choice) =>
                          DropdownMenuItem(value: choice, child: Text(choice)),
                    )
                    .toList(),
                onChanged: (value) => setState(() => gender = value ?? gender),
              ),
              if (gender == 'Self describe') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: customGenderController,
                  maxLength: 40,
                  decoration: const InputDecoration(
                    labelText: 'Your gender',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: pronouns,
                decoration: const InputDecoration(
                  labelText: 'Pronouns',
                  border: OutlineInputBorder(),
                ),
                items: pronounChoices
                    .map(
                      (choice) =>
                          DropdownMenuItem(value: choice, child: Text(choice)),
                    )
                    .toList(),
                onChanged: (value) =>
                    setState(() => pronouns = value ?? pronouns),
              ),
              if (pronouns == 'Self describe') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: customPronounsController,
                  maxLength: 40,
                  decoration: const InputDecoration(
                    labelText: 'Your pronouns',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Photos and videos'),
                subtitle: Text(
                  Platform.isAndroid
                      ? 'Choose photos and videos for chat with the Android system picker. Only selected files are shared with FluxLira.'
                      : 'Choose media for chats or Image Studio with the iOS photo picker. You choose what to share; no full-library access is needed.',
                ),
              ),
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: const Text('Models and files'),
                subtitle: Text(
                  Platform.isAndroid
                      ? 'Model downloads save inside FluxLira. Import your own GGUF model with the Android file picker; no storage permission is needed.'
                      : 'Downloads save in this app. To import your own model, choose it with the iOS Files picker. There is no blanket Files permission.',
                ),
              ),
              const SizedBox(height: 12),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              FilledButton(
                onPressed: saving ? null : saveProfile,
                child: Text(
                  saving
                      ? 'Saving…'
                      : widget.firstRun
                      ? 'Start using FluxLira'
                      : 'Save profile',
                ),
              ),
              if (!widget.firstRun)
                TextButton.icon(
                  onPressed: saving
                      ? null
                      : () async {
                          setState(() {
                            saving = true;
                            error = null;
                          });
                          try {
                            await widget.onSave(
                              const UserProfile(setupComplete: true),
                            );
                            if (context.mounted) Navigator.of(context).pop();
                          } catch (failure) {
                            if (mounted) {
                              setState(
                                () => error =
                                    'Could not delete your profile: $failure',
                              );
                            }
                          } finally {
                            if (mounted) setState(() => saving = false);
                          }
                        },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete profile details'),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
