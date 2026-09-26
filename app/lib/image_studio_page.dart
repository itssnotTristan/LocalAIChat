import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'glass_design.dart';
import 'image_studio_engine.dart';
import 'image_studio_install.dart';

class ImageStudioPage extends StatefulWidget {
  const ImageStudioPage({required this.root, required this.design, super.key});

  final String root;
  final GlassDesign design;

  @override
  State<ImageStudioPage> createState() => _ImageStudioPageState();
}

class _ImageStudioPageState extends State<ImageStudioPage> {
  final prompt = TextEditingController();
  late final ImageStudioEngine engine = ImageStudioEngine(root: widget.root);
  late final ImageStudioInstaller installer = ImageStudioInstaller(widget.root);
  String? source;
  String? output;
  String status = 'Choose a photo and describe your edit.';
  bool installing = false;
  bool editing = false;
  double strength = 0.45;
  int steps = 20;
  int seed = -1;

  @override
  void dispose() {
    engine.cancel();
    installer.cancel();
    prompt.dispose();
    super.dispose();
  }

  Future<void> pickPhoto() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = picked?.files.single.path;
    if (path == null) return;
    try {
      final extension = path.split('.').last.toLowerCase();
      if (Platform.isWindows &&
          !['png', 'jpg', 'jpeg', 'webp'].contains(extension)) {
        throw StateError('Choose a PNG, JPEG, or WebP photo on Windows.');
      }
      final folder = Directory('${widget.root}/sources');
      await folder.create(recursive: true);
      final copied =
          '${folder.path}/source_${DateTime.now().microsecondsSinceEpoch}.$extension';
      await File(path).copy(copied);
      var ready = copied;
      if (Platform.isIOS) {
        ready =
            await const MethodChannel('local_ai_chat/media')
                .invokeMethod<String>('prepareImage', {
                  'source': copied,
                  'destination': '$copied.jpg',
                  'maxSide': '768',
                }) ??
            (throw StateError('Could not prepare the photo for editing.'));
      }
      if (mounted) {
        setState(() {
          source = ready;
          output = null;
          status = 'Photo ready. Describe what to change.';
        });
      }
    } catch (error) {
      if (mounted) setState(() => status = '$error');
    }
  }

  Future<void> installModel() async {
    if (installing || editing) return;
    setState(() {
      installing = true;
      status = 'Preparing local image model…';
    });
    try {
      await installer.install((message) {
        if (mounted) setState(() => status = message);
      });
      if (mounted) setState(() => status = 'Image model ready on this device.');
    } catch (error) {
      if (mounted) setState(() => status = 'Install paused: $error');
    } finally {
      if (mounted) setState(() => installing = false);
    }
  }

  Future<void> makeEdit() async {
    final input = source;
    if (input == null || editing || installing) return;
    if (prompt.text.trim().isEmpty) {
      setState(() => status = 'Describe the edit you want first.');
      return;
    }
    setState(() {
      editing = true;
      output = null;
      status = 'Starting local image edit…';
    });
    try {
      final result = await engine.edit(
        inputPath: input,
        prompt: prompt.text,
        strength: strength,
        steps: steps,
        seed: seed < 0 ? math.Random.secure().nextInt(0x7fffffff) : seed,
        width: 512,
        height: 512,
        onStatus: (message) {
          if (mounted) setState(() => status = message);
        },
      );
      if (mounted) {
        setState(() {
          output = result;
          status = 'Edit saved privately on this device.';
        });
      }
    } catch (error) {
      if (mounted) setState(() => status = 'Edit failed: $error');
    } finally {
      if (mounted) setState(() => editing = false);
    }
  }

  Future<void> saveCopy() async {
    final result = output;
    if (result == null) return;
    final bytes = Platform.isIOS ? await File(result).readAsBytes() : null;
    final destination = await FilePicker.platform.saveFile(
      dialogTitle: 'Save edited photo',
      fileName: 'LocalAIChat-edit.png',
      type: FileType.custom,
      allowedExtensions: ['png'],
      bytes: bytes,
    );
    if (destination == null) return;
    if (Platform.isWindows) await File(result).copy(destination);
    if (mounted) setState(() => status = 'Saved edited photo.');
  }

  @override
  Widget build(BuildContext context) {
    final design = widget.design;
    return GlassDesign(
      themeName: design.themeName,
      customColor: design.customColor,
      starColor: design.starColor,
      starBackgroundColor: design.starBackgroundColor,
      auroraColor: design.auroraColor,
      motion: design.motion,
      speed: design.speed,
      backgroundStyle: design.backgroundStyle,
      child: Stack(
        children: [
          const Positioned.fill(child: GlassBackground()),
          Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              title: const Text('Image Studio'),
            ),
            body: SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  GlassSurface(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Edit a photo on this device',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(status),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: installing ? null : installModel,
                              icon: const Icon(Icons.download_outlined),
                              label: Text(
                                installing
                                    ? 'Installing…'
                                    : 'Install image model',
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: editing ? null : pickPhoto,
                              icon: const Icon(
                                Icons.add_photo_alternate_outlined,
                              ),
                              label: const Text('Choose photo'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (source != null) ...[
                    GlassSurface(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Original'),
                          const SizedBox(height: 8),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 370),
                            child: Center(
                              child: Image.file(
                                File(source!),
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  GlassSurface(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: prompt,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'Describe the edit',
                            hintText: 'Make the lighting warmer and change the background to a garden',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text('Change strength · ${(strength * 100).round()}%'),
                        Slider(
                          value: strength,
                          min: 0.20,
                          max: 0.85,
                          onChanged: editing
                              ? null
                              : (value) => setState(() => strength = value),
                        ),
                        Text('Quality steps · $steps'),
                        Slider(
                          value: steps.toDouble(),
                          min: 8,
                          max: 40,
                          divisions: 32,
                          onChanged: editing
                              ? null
                              : (value) =>
                                    setState(() => steps = value.round()),
                        ),
                        Wrap(
                          spacing: 8,
                          children: [
                            FilledButton.icon(
                              onPressed: source == null || editing || installing
                                  ? null
                                  : makeEdit,
                              icon: const Icon(Icons.auto_fix_high),
                              label: const Text('Make edit'),
                            ),
                            if (editing)
                              OutlinedButton.icon(
                                onPressed: engine.cancel,
                                icon: const Icon(Icons.stop),
                                label: const Text('Stop'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (output != null) ...[
                    const SizedBox(height: 14),
                    GlassSurface(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Edited result',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 440),
                            child: Center(
                              child: InteractiveViewer(
                                child: Image.file(
                                  File(output!),
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            children: [
                              FilledButton.icon(
                                onPressed: saveCopy,
                                icon: const Icon(Icons.save_alt),
                                label: const Text('Save copy'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () => Navigator.pop(context, output),
                                icon: const Icon(Icons.chat_bubble_outline),
                                label: const Text('Use in chat'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
