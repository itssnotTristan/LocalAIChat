import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'glass_design.dart';
import 'image_studio_engine.dart';
import 'image_edit_request.dart';
import 'image_studio_install.dart';
import 'image_studio_models.dart';
import 'background_model_download.dart';

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
  late final ImageStudioModels modelStore = ImageStudioModels(widget.root);
  final BackgroundModelDownloads backgroundDownloads =
      BackgroundModelDownloads();
  Timer? imageDownloadPoll;
  bool imageArchiveReady = false;
  String imageDownloadStatus = '';
  List<InstalledImageModel> models = [];
  String? selectedModelId;
  String? source;
  String? output;
  String status = 'Choose a photo and describe your edit.';
  bool installing = false;
  bool editing = false;
  double strength = 0.30;
  int steps = 20;
  int seed = -1;

  @override
  void initState() {
    super.initState();
    refreshModels();
    if (Platform.isIOS) {
      unawaited(pollImageDownload());
      imageDownloadPoll = Timer.periodic(
        const Duration(seconds: 4),
        (_) => unawaited(pollImageDownload()),
      );
    }
  }

  Future<void> pollImageDownload() async {
    try {
      final transfers = await backgroundDownloads.statuses();
      final matching = transfers
          .where(
            (item) => item.id == BackgroundModelDownloads.imageArchiveTaskId,
          )
          .firstOrNull;
      if (!mounted) return;
      setState(() {
        imageArchiveReady = matching?.state == 'downloaded';
        imageDownloadStatus = switch (matching?.state) {
          'downloading' =>
            'Image model downloading in background · ${(matching!.received / 1048576).round()} MiB',
          'downloaded' => 'Image model downloaded. Tap Finish install.',
          'failed' => 'Image download failed: ${matching!.error}',
          _ => '',
        };
      });
    } catch (_) {
      // The model picker still works if a background status check fails.
    }
  }

  Future<void> queueImageDownload() async {
    try {
      await backgroundDownloads.queueImageArchive(widget.root);
      await pollImageDownload();
      if (mounted)
        setState(
          () => status = 'Image model download started. You can leave the app.',
        );
    } catch (error) {
      if (mounted) setState(() => status = 'Image download failed: $error');
    }
  }

  Future<void> refreshModels() async {
    final available = await modelStore.installed();
    final selected = await modelStore.selected();
    if (mounted) {
      setState(() {
        models = available;
        selectedModelId = selected?.id;
      });
    }
  }

  @override
  void dispose() {
    imageDownloadPoll?.cancel();
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
      await modelStore.select(ImageStudioModels.builtInId);
      await refreshModels();
      if (Platform.isIOS) {
        await backgroundDownloads.forgetId(
          BackgroundModelDownloads.imageArchiveTaskId,
        );
        if (mounted)
          setState(() {
            imageArchiveReady = false;
            imageDownloadStatus = '';
          });
      }
      if (mounted) setState(() => status = 'Image model ready on this device.');
    } catch (error) {
      if (mounted) setState(() => status = 'Install paused: $error');
    } finally {
      if (mounted) setState(() => installing = false);
    }
  }

  Future<void> importModel() async {
    if (installing || editing) return;
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
      withData: false,
    );
    final item = picked?.files.single;
    if (item?.path == null) return;
    setState(() {
      installing = true;
      status = 'Checking the imported image model…';
    });
    try {
      await modelStore.importZip(
        item!.path!,
        item.name.replaceFirst(RegExp(r'\.zip$', caseSensitive: false), ''),
        (message) {
          if (mounted) setState(() => status = message);
        },
      );
      await refreshModels();
      if (mounted)
        setState(() => status = 'Imported model ready on this iPhone.');
    } catch (error) {
      if (mounted) setState(() => status = 'Model import failed: $error');
    } finally {
      if (mounted) setState(() => installing = false);
    }
  }

  Future<void> chooseModel(String id) async {
    if (installing || editing) return;
    try {
      await modelStore.select(id);
      await refreshModels();
      if (mounted) setState(() => status = 'Image model changed.');
    } catch (error) {
      if (mounted) setState(() => status = 'Could not change model: $error');
    }
  }

  Future<void> renameModel() async {
    final model = models
        .where((item) => item.id == selectedModelId)
        .firstOrNull;
    if (model == null || installing || editing) return;
    var editedName = model.name;
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename image model'),
        content: TextFormField(
          initialValue: model.name,
          onChanged: (value) => editedName = value,
          autofocus: true,
          maxLength: 60,
          decoration: const InputDecoration(labelText: 'Model name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, editedName),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null) return;
    try {
      await modelStore.rename(model.id, name);
      await refreshModels();
    } catch (error) {
      if (mounted) setState(() => status = 'Could not rename model: $error');
    }
  }

  Future<void> deleteModel() async {
    final model = models
        .where((item) => item.id == selectedModelId)
        .firstOrNull;
    if (model == null || installing || editing) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${model.name}?'),
        content: const Text(
          'This removes this model from the app. Your original photos and edited results stay saved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete model'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => installing = true);
    try {
      await modelStore.delete(model.id);
      await refreshModels();
      if (mounted) setState(() => status = 'Deleted ${model.name}.');
    } catch (error) {
      if (mounted) setState(() => status = 'Could not delete model: $error');
    } finally {
      if (mounted) setState(() => installing = false);
    }
  }

  Future<void> makeEdit() async {
    final input = source;
    if (input == null || editing || installing) return;
    final model = await modelStore.selected();
    if (model == null) {
      if (mounted)
        setState(
          () => status = 'Install or import an iPhone image model first.',
        );
      return;
    }
    if (prompt.text.trim().isEmpty) {
      setState(() => status = 'Describe the edit you want first.');
      return;
    }
    final unsupported = unsupportedImageEdit(prompt.text);
    if (unsupported != null) {
      setState(() => status = unsupported);
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('This edit is not supported'),
          content: Text(unsupported),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      editing = true;
      output = null;
      status = 'Starting local image edit…';
    });
    try {
      final result = await engine.edit(
        inputPath: input,
        modelDirectory: model.directory,
        prompt: prompt.text,
        strength: strength,
        steps: steps,
        seed: seed < 0 ? math.Random.secure().nextInt(0x7fffffff) : seed,
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

  Future<void> discardOutput() async {
    final result = output;
    if (result == null) return;
    final file = File(result);
    if (await file.exists()) {
      final root = await Directory('${widget.root}/outputs').absolute
          .resolveSymbolicLinks();
      final resolved = await file.absolute.resolveSymbolicLinks();
      if (resolved.startsWith('$root${Platform.pathSeparator}')) {
        await file.delete();
      }
    }
    if (mounted) {
      setState(() {
        output = null;
        status = 'Discarded the edit. Your original photo is unchanged.';
      });
    }
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
                        if (imageDownloadStatus.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(imageDownloadStatus),
                        ],
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: installing
                                  ? null
                                  : Platform.isIOS &&
                                        !imageArchiveReady &&
                                        !models.any((model) => model.isBuiltIn)
                                  ? queueImageDownload
                                  : installModel,
                              icon: const Icon(Icons.download_outlined),
                              label: Text(
                                installing
                                    ? 'Installing…'
                                    : imageArchiveReady
                                    ? 'Finish image model install'
                                    : models.any((model) => model.isBuiltIn)
                                    ? 'Check Realistic Vision model'
                                    : 'Download image model in background',
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: installing || editing
                                  ? null
                                  : importModel,
                              icon: const Icon(Icons.file_upload_outlined),
                              label: const Text('Import Core ML ZIP'),
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
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          key: ValueKey(selectedModelId),
                          initialValue: selectedModelId,
                          decoration: const InputDecoration(
                            labelText: 'Image editing model',
                            border: OutlineInputBorder(),
                          ),
                          hint: const Text('Install or import a model'),
                          items: models
                              .map(
                                (model) => DropdownMenuItem(
                                  value: model.id,
                                  child: Text(
                                    model.name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: installing || editing
                              ? null
                              : (id) {
                                  if (id != null) chooseModel(id);
                                },
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            TextButton.icon(
                              onPressed:
                                  selectedModelId == null ||
                                      installing ||
                                      editing
                                  ? null
                                  : renameModel,
                              icon: const Icon(Icons.edit_outlined),
                              label: const Text('Rename'),
                            ),
                            TextButton.icon(
                              onPressed:
                                  selectedModelId == null ||
                                      installing ||
                                      editing
                                  ? null
                                  : deleteModel,
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Delete model'),
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
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'Describe the edit',
                            hintText: 'Make the lighting warmer and change the background to a garden',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          isBackgroundReplacement(prompt.text)
                              ? 'Background mode selects the whole subject before generating scenery. Check the silhouette before saving.'
                              : 'This model redraws the whole photo. Higher strength can change faces, clothing, and pose.',
                        ),
                        if (!isBackgroundReplacement(prompt.text)) ...[
                          const SizedBox(height: 12),
                          Text('Redraw amount · ${(strength * 100).round()}%'),
                          Slider(
                            value: strength,
                            min: 0.20,
                            max: 0.85,
                            onChanged: editing
                                ? null
                                : (value) => setState(() => strength = value),
                          ),
                        ],
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
                              TextButton.icon(
                                onPressed: discardOutput,
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('Discard edit'),
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
