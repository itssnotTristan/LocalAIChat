import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:lib_llama_cpp/lib_llama_cpp.dart';
import 'package:path_provider/path_provider.dart';

import 'glass_design.dart';
import 'speech_service.dart';
import 'self_test.dart';
import 'gguf_info.dart';
import 'model_download.dart';
import 'speech_download.dart';
import 'video_duration.dart';
import 'video_sampler.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (args.isNotEmpty && args.first == '--self-test') {
    await runSelfTest(args);
    exit(0);
  }
  if (args.isNotEmpty && args.first == '--self-test-text') {
    await runTextSelfTest(args);
    exit(0);
  }
  runApp(const LocalChatApp());
}

class LocalChatApp extends StatelessWidget {
  const LocalChatApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Local AI Chat',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: Colors.deepPurple, useMaterial3: true),
    darkTheme: ThemeData(
      colorSchemeSeed: Colors.deepPurple,
      brightness: Brightness.dark,
      useMaterial3: true,
    ),
    themeMode: ThemeMode.dark,
    home: const ChatScreen(),
  );
}

class LocalModel {
  LocalModel(this.name, this.path, [this.projector]);
  String name;
  String path;
  String? projector;
  bool get vision => projector != null && projector!.isNotEmpty;
  Map<String, dynamic> toJson() => {
    'name': name,
    'path': path,
    'projector': projector,
  };
  factory LocalModel.fromJson(Map<String, dynamic> data) => LocalModel(
    data['name'] as String,
    data['path'] as String,
    data['projector'] as String?,
  );
}

class MediaFrame {
  MediaFrame(this.path, [this.timeMs]);
  String path;
  int? timeMs;
  Map<String, dynamic> toJson() => {'path': path, 'timeMs': timeMs};
  factory MediaFrame.fromJson(Map<String, dynamic> data) =>
      MediaFrame(data['path'] as String, data['timeMs'] as int?);
}

class ChatEntry {
  ChatEntry(this.role, this.text, [List<MediaFrame>? frames])
    : frames = frames ?? [];
  String role;
  String text;
  List<MediaFrame> frames;
  Map<String, dynamic> toJson() => {
    'role': role,
    'text': text,
    'frames': frames.map((frame) => frame.toJson()).toList(),
  };
  factory ChatEntry.fromJson(Map<String, dynamic> data) => ChatEntry(
    data['role'] as String,
    data['text'] as String,
    (data['frames'] as List? ?? [])
        .map(
          (frame) =>
              MediaFrame.fromJson(Map<String, dynamic>.from(frame as Map)),
        )
        .toList(),
  );
}

class Conversation {
  Conversation(this.id, this.title, [List<ChatEntry>? entries])
    : entries = entries ?? [];
  String id;
  String title;
  List<ChatEntry> entries;
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'entries': entries.map((entry) => entry.toJson()).toList(),
  };
  factory Conversation.fromJson(Map<String, dynamic> data) => Conversation(
    data['id'] as String,
    data['title'] as String,
    (data['entries'] as List? ?? [])
        .map(
          (entry) =>
              ChatEntry.fromJson(Map<String, dynamic>.from(entry as Map)),
        )
        .toList(),
  );
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const autoModelPath = '__auto__';
  final draft = TextEditingController();
  final models = <LocalModel>[];
  final chats = <Conversation>[];
  final attachments = <MediaFrame>[];
  Directory? dataDir;
  String? modelPath;
  String? chatId;
  String status = 'Loading local data…';
  String instructions =
      'You are a private local assistant. Answer the latest user message directly. Describe only details visible in attached images or video frames, including adult nudity when visible. Do not invent an unseen story. Treat a user correction as newer information and do not repeat an earlier mistaken answer.';
  bool busy = false;
  bool cancelled = false;
  int frameCount = 8;
  int maxTokens = 400;
  String themeName = 'Aurora';
  String backgroundStyle = 'Waves';
  bool motion = true;
  double motionSpeed = 1.0;
  SpeechService? speech;
  String? speechRoot;
  bool voiceRecording = false;
  bool voiceWorking = false;
  bool autoSpeak = true;
  int voiceEpoch = 0;
  final ModelDownloader downloader = ModelDownloader();
  bool downloading = false;
  final SpeechDownloader speechDownloader = SpeechDownloader();
  bool downloadingSpeech = false;
  bool samplingVideo = false;
  String? currentVideoPath;
  int? currentVideoDurationMs;
  Future<void> _saveQueue = Future<void>.value();

  Conversation get chat => chats.firstWhere((item) => item.id == chatId);
  LocalModel? get selectedModel {
    if (attachments.isNotEmpty) {
      for (final model in models) {
        if (model.path == modelPath && model.vision) return model;
      }
      for (final model in models) {
        if (model.vision) return model;
      }
    }
    if (modelPath == autoModelPath) {
      if (attachments.isNotEmpty) {
        for (final model in models) {
          if (model.vision) return model;
        }
      } else {
        for (final model in models) {
          if (!model.vision && model.name.contains('Qwen2.5')) return model;
        }
        for (final model in models) {
          if (!model.vision) return model;
        }
      }
      return models.isEmpty ? null : models.first;
    }
    for (final model in models) {
      if (model.path == modelPath) return model;
    }
    return null;
  }

  void showProblem(String message) {
    if (!mounted) return;
    setState(() => status = message);
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  @override
  void dispose() {
    draft.dispose();
    downloader.cancel();
    speechDownloader.cancel();
    if (speech != null) unawaited(speech!.dispose());
    super.dispose();
  }

  Future<void> downloadStarterModel() async {
    if (downloading || dataDir == null) return;
    final directory = dataDir!.path + Platform.pathSeparator + 'models';
    setState(() {
      downloading = true;
      status = 'Downloading starter vision model…';
    });
    var lastShownMiB = -1;
    try {
      final files = await downloader.downloadStarter(directory, (
        name,
        received,
        total,
      ) {
        final currentMiB = received ~/ 1048576;
        if (currentMiB == lastShownMiB || !mounted) return;
        lastShownMiB = currentMiB;
        setState(
          () => status =
              'Downloading $name · $currentMiB MiB' +
              (total == null ? '' : ' / ${total ~/ 1048576} MiB'),
        );
      });
      if (!models.any((item) => item.path == files.model)) {
        models.add(
          LocalModel('SmolVLM2 500M Video Q8', files.model, files.projector),
        );
      }
      modelPath = models.any((item) => !item.vision)
          ? autoModelPath
          : files.model;
      setState(
        () => status = 'Starter model and projector passed SHA-256 checks.',
      );
      await save();
    } catch (error) {
      if (mounted)
        setState(() => status = 'Model download: ' + error.toString());
    } finally {
      if (mounted) setState(() => downloading = false);
    }
  }

  Future<void> downloadAdultTextModel() async {
    if (downloading || dataDir == null) return;
    final directory = dataDir!.path + Platform.pathSeparator + 'models';
    setState(() {
      downloading = true;
      status = 'Downloading optional open-ended text model…';
    });
    var lastShownMiB = -1;
    try {
      final path = await downloader.downloadAdultText(directory, (
        name,
        received,
        total,
      ) {
        final currentMiB = received ~/ 1048576;
        if (currentMiB == lastShownMiB || !mounted) return;
        lastShownMiB = currentMiB;
        setState(
          () => status =
              'Downloading $name · $currentMiB MiB' +
              (total == null ? '' : ' / ${total ~/ 1048576} MiB'),
        );
      });
      if (!models.any((item) => item.path == path)) {
        models.add(LocalModel('Qwen2.5 1.5B · text', path));
      }
      modelPath = models.any((item) => item.vision) ? autoModelPath : path;
      setState(() => status = 'Text model passed SHA-256 verification.');
      await save();
    } catch (error) {
      if (mounted) setState(() => status = 'Model download: $error');
    } finally {
      if (mounted) setState(() => downloading = false);
    }
  }

  Future<void> downloadSpeechModels() async {
    final root = speechRoot;
    if (root == null || downloadingSpeech) return;
    setState(() {
      downloadingSpeech = true;
      status = 'Downloading offline speech models…';
    });
    var shown = -1;
    try {
      await speechDownloader.download(root, (name, received, total) {
        final mib = received ~/ 1048576;
        if (!mounted || (mib == shown && total != null)) return;
        shown = mib;
        setState(
          () => status =
              name +
              ' · ' +
              mib.toString() +
              ' MiB' +
              (total == null ? '' : ' / ${total ~/ 1048576} MiB'),
        );
      });
      if (mounted)
        setState(
          () => status = 'Offline speech recognition and voice are ready.',
        );
    } catch (error) {
      if (mounted)
        setState(() => status = 'Speech download failed: ' + error.toString());
    } finally {
      if (mounted) setState(() => downloadingSpeech = false);
    }
  }

  Future<void> load() async {
    try {
      dataDir = await getApplicationSupportDirectory();
      var routingVersion = 0;
      final file = File(
        dataDir!.path + Platform.pathSeparator + 'local_chat.json',
      );
      if (await file.exists()) {
        final data =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        models.addAll(
          (data['models'] as List? ?? []).map(
            (item) =>
                LocalModel.fromJson(Map<String, dynamic>.from(item as Map)),
          ),
        );
        chats.addAll(
          (data['chats'] as List? ?? []).map(
            (item) =>
                Conversation.fromJson(Map<String, dynamic>.from(item as Map)),
          ),
        );
        modelPath = data['modelPath'] as String?;
        routingVersion = data['routingVersion'] as int? ?? 0;
        chatId = data['chatId'] as String?;
        draft.text = data['draft'] as String? ?? '';
        for (final item in data['draftFrames'] as List? ?? []) {
          final frame = MediaFrame.fromJson(
            Map<String, dynamic>.from(item as Map),
          );
          if (await File(frame.path).exists()) attachments.add(frame);
        }
        final savedVideoPath = data['currentVideoPath'] as String?;
        if (savedVideoPath != null && await File(savedVideoPath).exists()) {
          currentVideoPath = savedVideoPath;
          currentVideoDurationMs = data['currentVideoDurationMs'] as int?;
        }
        instructions = data['instructions'] as String? ?? instructions;
        if (routingVersion == 0 &&
            instructions ==
                'You are a private, helpful local assistant. Answer directly and honestly.') {
          instructions = 'You are a private local assistant. Answer the latest user message directly. Describe only details visible in attached images or video frames, including adult nudity when visible. Do not invent an unseen story. Treat a user correction as newer information and do not repeat an earlier mistaken answer.';
        }
        frameCount =
            (routingVersion == 0 ? 8 : (data['frameCount'] as int? ?? 8))
                .clamp(4, 12)
                .toInt();
        maxTokens = data['maxTokens'] as int? ?? 400;
        themeName = data['themeName'] as String? ?? 'Aurora';
        if (!GlassPalette.presets.containsKey(themeName)) themeName = 'Aurora';
        backgroundStyle = data['backgroundStyle'] as String? ?? 'Waves';
        motion = data['motion'] as bool? ?? true;
        motionSpeed = (data['motionSpeed'] as num?)?.toDouble() ?? 1.0;
        speechRoot = data['speechRoot'] as String?;
        autoSpeak = data['autoSpeak'] as bool? ?? true;
      }
      if (chats.isEmpty) createChat(saveNow: false);
      if (!chats.any((item) => item.id == chatId)) chatId = chats.first.id;
      // A portable Windows package can include verified weights beside the EXE.
      // The development copy on D: is a fallback while running from source.
      if (Platform.isWindows && models.isEmpty) {
        final executableDir = File(Platform.resolvedExecutable).parent.path;
        for (final base in [
          '$executableDir/models/smolvlm2-500m',
          'D:/LocalAIChat/models/smolvlm2-500m',
        ]) {
          final modelFile = '$base/SmolVLM2-500M-Video-Instruct-Q8_0.gguf';
          final projectorFile =
              '$base/mmproj-SmolVLM2-500M-Video-Instruct-Q8_0.gguf';
          if (await File(modelFile).exists() &&
              await File(projectorFile).exists()) {
            models.add(
              LocalModel('SmolVLM2 500M Q8', modelFile, projectorFile),
            );
            modelPath = modelFile;
            break;
          }
        }
      }
      if (Platform.isWindows) {
        final executableDir = File(Platform.resolvedExecutable).parent.path;
        for (final base in [
          '$executableDir/models/qwen25-1.5b-abliterated',
          'D:/LocalAIChat/models/qwen25-1.5b-abliterated',
        ]) {
          final path = '$base/${ModelDownloader.adultTextName}';
          if (await File(path).exists() &&
              !models.any((item) => item.path == path)) {
            models.add(LocalModel('Qwen2.5 1.5B · text', path));
            break;
          }
        }
      }
      if (routingVersion == 0 &&
          models.any((item) => item.vision) &&
          models.any((item) => !item.vision)) {
        modelPath = autoModelPath;
      }
      if (speechRoot == null) {
        final executableDir = File(Platform.resolvedExecutable).parent.path;
        final packagedSpeech = '$executableDir/speech';
        speechRoot =
            Platform.isWindows && await SpeechService.hasModels(packagedSpeech)
            ? packagedSpeech
            : Platform.isWindows &&
                  await SpeechService.hasModels('D:/LocalAIChat/speech')
            ? 'D:/LocalAIChat/speech'
            : dataDir!.path + Platform.pathSeparator + 'speech';
      }
      speech = SpeechService(speechRoot!);
      if (mounted) {
        setState(
          () => status = models.isEmpty
              ? 'Get a local model to begin. Chat stays on this device.'
              : 'Ready. All chat inference stays on this device.',
        );
      }
      await save();
    } catch (error) {
      if (mounted)
        setState(
          () => status = 'Could not load local data: ' + error.toString(),
        );
    }
  }

  Future<void> save() {
    final next = _saveQueue.then((_) => _writeSave());
    _saveQueue = next.then((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  Future<void> _writeSave() async {
    if (dataDir == null) return;
    final file = File(
      dataDir!.path + Platform.pathSeparator + 'local_chat.json',
    );
    final temp = File(file.path + '.tmp');
    await temp.writeAsString(
      jsonEncode({
        'models': models.map((item) => item.toJson()).toList(),
        'chats': chats.map((item) => item.toJson()).toList(),
        'modelPath': modelPath,
        'routingVersion': 1,
        'chatId': chatId,
        'draft': draft.text,
        'draftFrames': attachments.map((frame) => frame.toJson()).toList(),
        'currentVideoPath': currentVideoPath,
        'currentVideoDurationMs': currentVideoDurationMs,
        'instructions': instructions,
        'frameCount': frameCount,
        'maxTokens': maxTokens,
        'themeName': themeName,
        'backgroundStyle': backgroundStyle,
        'motion': motion,
        'motionSpeed': motionSpeed,
        'speechRoot': speechRoot,
        'autoSpeak': autoSpeak,
      }),
    );
    if (await file.exists()) await file.delete();
    await temp.rename(file.path);
  }

  void createChat({bool saveNow = true}) {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    chats.insert(0, Conversation(id, 'New chat'));
    chatId = id;
    draft.clear();
    attachments.clear();
    if (mounted) setState(() {});
    if (saveNow) unawaited(save());
  }

  Future<String> copyIntoApp(String path, String folder) async {
    final dir = Directory(dataDir!.path + Platform.pathSeparator + folder);
    await dir.create(recursive: true);
    final name = path.split(RegExp(r'[/\\]')).last;
    return (await File(path).copy(
      dir.path +
          Platform.pathSeparator +
          DateTime.now().microsecondsSinceEpoch.toString() +
          '_' +
          name,
    )).path;
  }

  Future<void> importModel({required bool projector}) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['gguf'],
    );
    final path = result?.files.single.path;
    if (path == null) return;
    try {
      final info = await GgufInfo.read(path);
      if (projector && selectedModel == null) return;
      if (!projector && models.any((item) => item.path == path)) {
        setState(() => status = 'That model is already in the library.');
        return;
      }
      // Mobile picker paths can be temporary; keep imported weights in app storage.
      final owned = Platform.isWindows
          ? path
          : await copyIntoApp(path, 'models');
      if (projector) {
        selectedModel!.projector = owned;
      } else {
        models.add(LocalModel(info.name, owned));
        modelPath = owned;
      }
      setState(
        () => status =
            'Imported ' +
            info.name +
            ' · ' +
            info.architecture +
            ' · ' +
            (info.sizeBytes / 1048576).toStringAsFixed(0) +
            ' MiB.',
      );
      await save();
    } catch (error) {
      setState(() => status = 'Model import failed: ' + error.toString());
    }
  }

  Future<void> inspectModel(LocalModel model) async {
    try {
      final info = await GgufInfo.read(model.path);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(model.name),
          content: SelectableText(
            'Architecture: ${info.architecture}\n'
            'Quantization: ${info.quantization}\n'
            'Context metadata: ${info.contextLength ?? 'unknown'}\n'
            'Model size: ${(info.sizeBytes / 1048576).toStringAsFixed(1)} MiB\n'
            'Vision projector: ${model.projector ?? 'none'}\n'
            'Model path: ${model.path}\n\n'
            'Runtime support is confirmed only after real inference.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted)
        setState(() => status = 'Could not inspect GGUF: ' + error.toString());
    }
  }

  Future<void> renameModel(LocalModel model) async {
    final controller = TextEditingController(text: model.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename model'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    setState(() => model.name = name);
    await save();
  }

  Future<void> removeModel(LocalModel model) async {
    final ownedFolder =
        dataDir!.path +
        Platform.pathSeparator +
        'models' +
        Platform.pathSeparator;
    final owned = model.path.startsWith(ownedFolder);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove model?'),
        content: Text(
          owned
              ? 'This removes the model and its app-owned files from this device.'
              : 'This removes the model from the library. External GGUF files remain in place.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      models.remove(model);
      if (modelPath == model.path)
        modelPath = models.isEmpty ? null : models.first.path;
    });
    await save();
    if (owned) {
      final modelFile = File(model.path);
      if (await modelFile.exists()) await modelFile.delete();
      final projector = model.projector;
      if (projector != null && projector.startsWith(ownedFolder)) {
        final projectorFile = File(projector);
        if (await projectorFile.exists()) await projectorFile.delete();
      }
    }
  }

  Future<void> attachImage() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = result?.files.single.path;
    if (path == null) return;
    try {
      final owned = await copyIntoApp(path, 'media');
      setState(() => attachments.add(MediaFrame(owned)));
      await save();
    } catch (error) {
      setState(() => status = 'Image import failed: ' + error.toString());
    }
  }

  Future<void> attachVideo() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.video);
    final path = result?.files.single.path;
    if (path == null) return;
    if (samplingVideo || dataDir == null) return;
    setState(() {
      samplingVideo = true;
      status = 'Scanning video on this device…';
    });
    try {
      final duration = (await VideoDuration.read(path)).inMilliseconds;
      if (duration <= 0) throw StateError('Video duration is unavailable.');
      final frames = await VideoSampler.sample(
        video: path,
        durationMs: duration,
        frameLimit: frameCount,
        outputDir: Directory('${dataDir!.path}${Platform.pathSeparator}frames'),
        onProgress: (done, total) {
          if (mounted)
            setState(() => status = 'Scanning video $done / $total frames…');
        },
      );
      setState(() {
        attachments.addAll(
          frames.map((frame) => MediaFrame(frame.path, frame.timeMs)),
        );
        currentVideoPath = path;
        currentVideoDurationMs = duration;
        status =
            'Kept ${frames.length} changed and time-spaced frames. Add an exact moment below if needed.';
      });
      await save();
    } catch (error) {
      showProblem('Video import failed: $error');
    } finally {
      if (mounted) setState(() => samplingVideo = false);
    }
  }

  Future<void> addVideoMoment() async {
    final video = currentVideoPath;
    final duration = currentVideoDurationMs;
    if (video == null || duration == null || duration <= 0 || dataDir == null)
      return;
    var timeMs = duration ~/ 2;
    String? previewPath;
    var loading = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, update) {
          Future<void> preview() async {
            update(() => loading = true);
            try {
              final frame = await VideoSampler.extractAt(
                video: video,
                timeMs: timeMs,
                outputDir: Directory(
                  '${dataDir!.path}${Platform.pathSeparator}frames',
                ),
              );
              if (dialogContext.mounted) update(() => previewPath = frame.path);
            } catch (error) {
              if (dialogContext.mounted)
                showProblem('Frame preview failed: $error');
            } finally {
              if (dialogContext.mounted) update(() => loading = false);
            }
          }

          return AlertDialog(
            title: const Text('Add an exact video moment'),
            content: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${(timeMs / 1000).toStringAsFixed(2)} seconds'),
                  Slider(
                    min: 0,
                    max: duration.toDouble(),
                    value: timeMs.toDouble(),
                    onChanged: (value) => update(() => timeMs = value.round()),
                    onChangeEnd: (_) => unawaited(preview()),
                  ),
                  if (loading) const CircularProgressIndicator(),
                  if (previewPath != null)
                    Image.file(
                      File(previewPath!),
                      height: 220,
                      fit: BoxFit.contain,
                    ),
                  const Text(
                    'Move the slider, then tap Add frame. The frame stays on this device.',
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: loading
                    ? null
                    : () async {
                        try {
                          final frame = await VideoSampler.extractAt(
                            video: video,
                            timeMs: timeMs,
                            outputDir: Directory(
                              '${dataDir!.path}${Platform.pathSeparator}frames',
                            ),
                          );
                          if (!mounted) return;
                          setState(
                            () => attachments.add(
                              MediaFrame(frame.path, frame.timeMs),
                            ),
                          );
                          await save();
                          if (dialogContext.mounted)
                            Navigator.pop(dialogContext);
                        } catch (error) {
                          showProblem('Could not add frame: $error');
                        }
                      },
                child: const Text('Add frame'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> send() async {
    if (busy || samplingVideo) return;
    if (dataDir == null) {
      showProblem(
        'Local data is still loading. Try sending again in a moment.',
      );
      return;
    }
    final initiallySelectedModel = selectedModel;
    if (initiallySelectedModel == null) {
      showProblem('Choose or download a local model before sending.');
      return;
    }
    var model = initiallySelectedModel;
    if (attachments.isNotEmpty && !model.vision) {
      for (final candidate in models) {
        if (candidate.vision) {
          model = candidate;
          break;
        }
      }
      if (!model.vision) {
        showProblem(
          'Attached media needs a vision model and its matching projector. Your draft and frames are still here.',
        );
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Using ${model.name} to inspect attached media.'),
          ),
        );
      }
    }
    if (!await File(model.path).exists()) {
      showProblem('The selected model file is missing: ${model.path}');
      return;
    }
    if (model.vision && !await File(model.projector!).exists()) {
      showProblem(
        'The vision projector file is missing. Your draft and frames are still here.',
      );
      return;
    }
    final prompt = draft.text.trim();
    if (prompt.isEmpty && attachments.isEmpty) return;
    final question = ChatEntry(
      'user',
      prompt.isEmpty ? 'Describe these images.' : prompt,
      List.of(attachments),
    );
    final originalVideoPath = currentVideoPath;
    final originalVideoDurationMs = currentVideoDurationMs;
    chat.entries.add(question);
    if (chat.title == 'New chat')
      chat.title = question.text.length > 38
          ? question.text.substring(0, 38)
          : question.text;
    draft.clear();
    attachments.clear();
    currentVideoPath = null;
    currentVideoDurationMs = null;
    final reply = ChatEntry('assistant', '');
    chat.entries.add(reply);
    setState(() {
      busy = true;
      cancelled = false;
      status = 'Loading model locally…';
    });
    await save();
    try {
      final input = <LlamaResponseInputItem>[];
      final history = chat.entries
          .where(
            (item) =>
                item != reply &&
                item != question &&
                item.text.isNotEmpty &&
                item.text != '[Generation failed]',
          )
          .toList();
      final recent = history.length > 6
          ? history.sublist(history.length - 6)
          : history;
      for (final item in question.frames.isEmpty ? recent : <ChatEntry>[]) {
        final text = item.text.length > 900
            ? item.text.substring(0, 900)
            : item.text;
        input.add(
          LlamaResponseInputItem(
            role: item.role,
            content: [
              LlamaTextPart(
                item.frames.isEmpty
                    ? text
                    : '$text [Earlier media was attached; those frames are not part of this request.]',
              ),
            ],
          ),
        );
      }
      final parts = <LlamaContentPart>[LlamaTextPart(question.text)];
      for (final frame in question.frames) {
        if (frame.timeMs != null) {
          parts.add(
            LlamaTextPart(
              'Video frame at ' +
                  (frame.timeMs! / 1000).toStringAsFixed(1) +
                  ' seconds:',
            ),
          );
        }
        parts.add(LlamaImageFilePart(path: frame.path));
      }
      input.add(LlamaResponseInputItem(role: 'user', content: parts));
      final client = LlamaOpenAIClient(
        models: {
          'active': LlamaModelConfig(
            modelPath: model.path,
            mmprojPath: model.projector,
            contextSize: model.vision ? 8192 : 4096,
            gpuLayerCount: 0,
          ),
        },
      );
      setState(() => status = 'Generating on this device…');
      await for (final event in client.responses.stream(
        model: 'active',
        input: input,
        instructions: model.name.toLowerCase().contains('qwen3')
            ? '$instructions\n/no_think'
            : instructions,
        maxOutputTokens: maxTokens,
      )) {
        if (cancelled) break;
        if (event is LlamaResponseOutputTextDelta) {
          if (mounted) setState(() => reply.text += event.delta);
        } else if (event is LlamaResponseFailed) {
          throw StateError(event.error.message);
        }
      }
      if (reply.text.isEmpty)
        reply.text = cancelled ? '[Stopped]' : '[No response]';
      if (mounted) setState(() => status = cancelled ? 'Stopped' : 'Ready');
    } catch (error) {
      chat.entries.remove(reply);
      chat.entries.remove(question);
      if (draft.text.trim().isEmpty) draft.text = question.text;
      attachments.insertAll(0, question.frames);
      currentVideoPath = originalVideoPath;
      currentVideoDurationMs = originalVideoDurationMs;
      showProblem('Local generation failed: $error');
    } finally {
      if (mounted) setState(() => busy = false);
      await save();
    }
  }

  Future<void> toggleVoice() async {
    final service = speech;
    if (service == null || dataDir == null) return;
    if (voiceWorking && !voiceRecording) {
      voiceEpoch++;
      cancelled = true;
      await service.stopSpeaking();
      if (mounted)
        setState(() {
          voiceWorking = false;
          status = 'Voice reply interrupted.';
        });
      return;
    }
    if (voiceRecording) {
      final epoch = voiceEpoch;
      setState(() {
        voiceRecording = false;
        voiceWorking = true;
        status = 'Transcribing on this device…';
      });
      try {
        final transcript = await service.stopAndTranscribe();
        if (transcript.isEmpty) throw StateError('No speech detected.');
        if (epoch != voiceEpoch) return;
        draft.text = transcript;
        setState(() => status = 'Heard: ' + transcript);
        await save();
        await send();
        if (epoch != voiceEpoch || !autoSpeak) return;
        final reply = chat.entries.isEmpty ? '' : chat.entries.last.text;
        if (reply.isEmpty || reply.startsWith('[')) return;
        setState(() => status = 'Preparing local speech…');
        final output =
            dataDir!.path +
            Platform.pathSeparator +
            'reply_' +
            DateTime.now().microsecondsSinceEpoch.toString() +
            '.wav';
        final wav = await service.synthesize(reply, output);
        if (epoch != voiceEpoch) return;
        setState(() => status = 'Speaking. Tap the microphone to interrupt.');
        await service.playFile(wav);
        if (mounted && epoch == voiceEpoch) setState(() => status = 'Ready');
      } catch (error) {
        if (mounted)
          setState(() => status = 'Voice failed: ' + error.toString());
      } finally {
        if (mounted) setState(() => voiceWorking = false);
      }
      return;
    }
    if (!await service.modelsReady) {
      setState(
        () => status =
            'Offline speech models are missing. Set their folder in Settings.',
      );
      return;
    }
    voiceEpoch++;
    try {
      final directory = Directory(
        dataDir!.path + Platform.pathSeparator + 'recordings',
      );
      await directory.create(recursive: true);
      final output =
          directory.path +
          Platform.pathSeparator +
          'mic_' +
          DateTime.now().microsecondsSinceEpoch.toString() +
          '.wav';
      await service.startRecording(output);
      if (mounted)
        setState(() {
          voiceRecording = true;
          status = 'Listening on this device. Tap microphone to send.';
        });
    } catch (error) {
      if (mounted)
        setState(() => status = 'Microphone failed: ' + error.toString());
    }
  }

  Future<void> showModels() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              height: 410,
              child: Column(
                children: [
                  Text(
                    'Local models',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const Text(
                    'Import a GGUF model. Vision models also need their matching mmproj GGUF.',
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          await importModel(projector: false);
                          update(() {});
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Import model'),
                      ),
                      OutlinedButton.icon(
                        onPressed:
                            selectedModel == null || modelPath == autoModelPath
                            ? null
                            : () async {
                                await importModel(projector: true);
                                update(() {});
                              },
                        icon: const Icon(Icons.image),
                        label: const Text('Add projector'),
                      ),
                      OutlinedButton.icon(
                        onPressed: downloading
                            ? null
                            : () async {
                                await downloadStarterModel();
                                update(() {});
                              },
                        icon: const Icon(Icons.download),
                        label: const Text('Get starter vision model'),
                      ),
                      OutlinedButton.icon(
                        onPressed: downloading
                            ? null
                            : () async {
                                await downloadAdultTextModel();
                                update(() {});
                              },
                        icon: const Icon(Icons.download),
                        label: const Text('Get open-ended text model'),
                      ),
                      if (downloading)
                        TextButton(
                          onPressed: () {
                            downloader.cancel();
                            update(() {});
                          },
                          child: const Text('Cancel download'),
                        ),
                    ],
                  ),
                  Expanded(
                    child: ListView(
                      children: [
                        if (models.length > 1)
                          RadioListTile<String>(
                            title: const Text('Auto · text + vision'),
                            subtitle: const Text(
                              'Use the text model for chat and the vision model for attached media.',
                            ),
                            value: autoModelPath,
                            groupValue: modelPath,
                            onChanged: (value) {
                              setState(() => modelPath = value);
                              update(() {});
                              unawaited(save());
                            },
                          ),
                        ...models.map(
                          (model) => RadioListTile<String>(
                            title: Text(model.name),
                            subtitle: Text(
                              (model.vision
                                      ? 'Text + vision · '
                                      : 'Text only · ') +
                                  model.path,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            secondary: PopupMenuButton<String>(
                              tooltip: 'Model actions',
                              icon: const Icon(Icons.more_vert),
                              onSelected: (action) async {
                                if (action == 'inspect')
                                  await inspectModel(model);
                                if (action == 'rename')
                                  await renameModel(model);
                                if (action == 'remove')
                                  await removeModel(model);
                                update(() {});
                              },
                              itemBuilder: (context) => const [
                                PopupMenuItem(
                                  value: 'inspect',
                                  child: Text('Inspect GGUF'),
                                ),
                                PopupMenuItem(
                                  value: 'rename',
                                  child: Text('Rename'),
                                ),
                                PopupMenuItem(
                                  value: 'remove',
                                  child: Text('Remove'),
                                ),
                              ],
                            ),
                            value: model.path,
                            groupValue: modelPath,
                            onChanged: (value) {
                              setState(() => modelPath = value);
                              update(() {});
                              unawaited(save());
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> showSettings() async {
    final promptController = TextEditingController(text: instructions);
    final speechController = TextEditingController(text: speechRoot ?? '');
    var count = frameCount;
    var limit = maxTokens;
    var selectedTheme = themeName;
    var selectedStyle = backgroundStyle;
    var animated = motion;
    var speed = motionSpeed;
    var spokenReplies = autoSpeak;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Local settings'),
          content: SizedBox(
            width: 460,
            height: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: promptController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'System instructions',
                    ),
                  ),
                  Text('Video frames: ' + count.toString()),
                  Slider(
                    value: count.toDouble(),
                    min: 4,
                    max: 12,
                    divisions: 8,
                    onChanged: (value) => update(() => count = value.round()),
                  ),
                  Text('Maximum output tokens: ' + limit.toString()),
                  Slider(
                    value: limit.toDouble(),
                    min: 100,
                    max: 1000,
                    divisions: 9,
                    onChanged: (value) => update(() => limit = value.round()),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: selectedTheme,
                    decoration: const InputDecoration(labelText: 'Appearance'),
                    items: GlassPalette.presets.keys
                        .map(
                          (name) =>
                              DropdownMenuItem(value: name, child: Text(name)),
                        )
                        .toList(),
                    onChanged: (value) =>
                        update(() => selectedTheme = value ?? selectedTheme),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: selectedStyle,
                    decoration: const InputDecoration(labelText: 'Background'),
                    items: ['Waves', 'Ribbons', 'Orbit', 'Pulse']
                        .map(
                          (name) =>
                              DropdownMenuItem(value: name, child: Text(name)),
                        )
                        .toList(),
                    onChanged: (value) =>
                        update(() => selectedStyle = value ?? selectedStyle),
                  ),
                  SwitchListTile(
                    title: const Text('Motion'),
                    value: animated,
                    onChanged: (value) => update(() => animated = value),
                  ),
                  Text('Motion speed: ' + speed.toStringAsFixed(1) + '×'),
                  Slider(
                    value: speed,
                    min: 0.2,
                    max: 3.0,
                    divisions: 28,
                    onChanged: (value) => update(() => speed = value),
                  ),
                  TextField(
                    controller: speechController,
                    decoration: const InputDecoration(
                      labelText: 'Offline speech model folder',
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      final folder = await FilePicker.platform
                          .getDirectoryPath();
                      if (folder != null)
                        update(() => speechController.text = folder);
                    },
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Choose speech folder'),
                  ),
                  TextButton.icon(
                    onPressed: downloadingSpeech
                        ? null
                        : () {
                            speechRoot = speechController.text.trim();
                            if (speechRoot == null || speechRoot!.isEmpty)
                              return;
                            final previous = speech;
                            speech = SpeechService(speechRoot!);
                            if (previous != null) unawaited(previous.dispose());
                            unawaited(save());
                            Navigator.pop(context);
                            unawaited(downloadSpeechModels());
                          },
                    icon: const Icon(Icons.download),
                    label: const Text('Download offline voice models'),
                  ),
                  SwitchListTile(
                    title: const Text('Speak voice replies'),
                    value: spokenReplies,
                    onChanged: (value) => update(() => spokenReplies = value),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                instructions = promptController.text;
                frameCount = count;
                maxTokens = limit;
                setState(() {
                  themeName = selectedTheme;
                  backgroundStyle = selectedStyle;
                  motion = animated;
                  motionSpeed = speed;
                  speechRoot = speechController.text.trim();
                  autoSpeak = spokenReplies;
                  if (speechRoot != null && speechRoot!.isNotEmpty) {
                    final previous = speech;
                    speech = SpeechService(speechRoot!);
                    if (previous != null) unawaited(previous.dispose());
                  }
                });
                Navigator.pop(context);
                unawaited(save());
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    promptController.dispose();
    speechController.dispose();
  }

  Widget messageBubble(ChatEntry entry) => Align(
    alignment: entry.role == 'user'
        ? Alignment.centerRight
        : Alignment.centerLeft,
    child: Container(
      constraints: const BoxConstraints(maxWidth: 680),
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      child: GlassSurface(
        padding: const EdgeInsets.all(13),
        radius: 16,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final frame in entry.frames) ...[
              if (frame.timeMs != null)
                Text(
                  'Frame at ' +
                      (frame.timeMs! / 1000).toStringAsFixed(1) +
                      ' s',
                ),
              Image.file(
                File(frame.path),
                width: 230,
                height: 160,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stack) =>
                    const Text('Media unavailable'),
              ),
            ],
            SelectableText(entry.text.isEmpty ? '…' : entry.text),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final palette = GlassPalette.presets[themeName]!;
    final light = palette.text.computeLuminance() < 0.5;
    return GlassDesign(
      themeName: themeName,
      motion: motion,
      speed: motionSpeed,
      backgroundStyle: backgroundStyle,
      child: Theme(
        data: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: palette.accent,
            brightness: light ? Brightness.light : Brightness.dark,
          ),
          useMaterial3: true,
          scaffoldBackgroundColor: Colors.transparent,
        ),
        child: Stack(
          children: [
            const Positioned.fill(child: GlassBackground()),
            Scaffold(
              backgroundColor: Colors.transparent,
              appBar: AppBar(
                backgroundColor: Colors.transparent,
                title: Text(
                  chats.isEmpty ? 'LOCAL AI CHAT' : chat.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
                actions: [
                  IconButton(
                    tooltip: 'Models',
                    onPressed: showModels,
                    icon: const Icon(Icons.memory),
                  ),
                  IconButton(
                    tooltip: 'Settings',
                    onPressed: showSettings,
                    icon: const Icon(Icons.settings_outlined),
                  ),
                ],
              ),
              drawer: Drawer(
                child: SafeArea(
                  child: Column(
                    children: [
                      ListTile(
                        title: const Text('Conversations'),
                        trailing: IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: () {
                            createChat();
                            Navigator.pop(context);
                          },
                        ),
                      ),
                      Expanded(
                        child: ListView(
                          children: chats
                              .map(
                                (item) => ListTile(
                                  title: Text(item.title),
                                  selected: item.id == chatId,
                                  onTap: () {
                                    setState(() => chatId = item.id);
                                    Navigator.pop(context);
                                    unawaited(save());
                                  },
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              body: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    child: GlassSurface(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      radius: 16,
                      child: Row(
                        children: [
                          Icon(Icons.circle, color: palette.accent, size: 10),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              selectedModel == null
                                  ? 'IMPORT A LOCAL MODEL'
                                  : selectedModel!.name +
                                        (selectedModel!.vision
                                            ? ' · VISION READY'
                                            : ' · TEXT ONLY') +
                                        ' · ON DEVICE',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: showModels,
                            child: const Text('Models'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(5),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            status,
                            style: Theme.of(context).textTheme.bodySmall,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (downloadingSpeech)
                          TextButton(
                            onPressed: speechDownloader.cancel,
                            child: const Text('Cancel'),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: chats.isEmpty
                        ? const Center(child: CircularProgressIndicator())
                        : ListView.builder(
                            itemCount: chat.entries.length,
                            itemBuilder: (context, index) =>
                                messageBubble(chat.entries[index]),
                          ),
                  ),
                  if (currentVideoPath != null && attachments.isNotEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: samplingVideo ? null : addVideoMoment,
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                        label: const Text('Add exact video moment'),
                      ),
                    ),
                  if (attachments.isNotEmpty)
                    SizedBox(
                      height: 82,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: attachments
                            .map(
                              (frame) => Stack(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: Image.file(
                                      File(frame.path),
                                      width: 100,
                                      height: 76,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  Positioned(
                                    right: 0,
                                    child: IconButton.filledTonal(
                                      iconSize: 14,
                                      onPressed: () {
                                        setState(
                                          () => attachments.remove(frame),
                                        );
                                        unawaited(save());
                                      },
                                      icon: const Icon(Icons.close),
                                    ),
                                  ),
                                ],
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  if (busy || samplingVideo)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              status,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: GlassSurface(
                        padding: const EdgeInsets.all(8),
                        radius: 21,
                        child: Row(
                          children: [
                            PopupMenuButton<String>(
                              tooltip: 'Attach local media',
                              icon: const Icon(Icons.add_circle_outline),
                              onSelected: (value) => value == 'image'
                                  ? attachImage()
                                  : attachVideo(),
                              itemBuilder: (context) => const [
                                PopupMenuItem(
                                  value: 'image',
                                  child: Text('Image'),
                                ),
                                PopupMenuItem(
                                  value: 'video',
                                  child: Text('Video'),
                                ),
                              ],
                            ),
                            Expanded(
                              child: TextField(
                                controller: draft,
                                minLines: 1,
                                maxLines: 5,
                                onChanged: (_) => unawaited(save()),
                                decoration: const InputDecoration(
                                  hintText: 'Ask privately on this device…',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            IconButton(
                              tooltip: voiceRecording
                                  ? 'Stop and transcribe'
                                  : voiceWorking
                                  ? 'Interrupt voice reply'
                                  : 'Start local voice recording',
                              onPressed: toggleVoice,
                              icon: Icon(
                                voiceRecording
                                    ? Icons.stop_circle
                                    : voiceWorking
                                    ? Icons.hearing_disabled
                                    : Icons.mic,
                              ),
                            ),
                            IconButton.filled(
                              tooltip: busy ? 'Stop' : 'Send',
                              onPressed: busy
                                  ? () => setState(() => cancelled = true)
                                  : send,
                              icon: Icon(
                                busy ? Icons.stop : Icons.arrow_upward,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
