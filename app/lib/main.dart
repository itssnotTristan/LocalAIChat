import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lib_llama_cpp/lib_llama_cpp.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'glass_design.dart';
import 'color_picker.dart';
import 'chat_context.dart';
import 'fish_voice.dart';
import 'speech_service.dart';
import 'self_test.dart';
import 'gguf_info.dart';
import 'media_viewer.dart';
import 'model_download.dart';
import 'reply_quality.dart';
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
  if (args.isNotEmpty && args.first == '--probe-vision') {
    await runVisionProbe(args);
    exit(0);
  }
  if (args.isNotEmpty && args.first == '--probe-video') {
    await runVideoProbe(args);
    exit(0);
  }
  if (args.isNotEmpty && args.first == '--probe-playback') {
    await runPlaybackProbe(args);
    exit(0);
  }
  if (args.isNotEmpty && args.first == '--probe-stop') {
    await runStopProbe(args);
    exit(0);
  }
  if (args.isNotEmpty && args.first == '--self-test-voices') {
    await runVoiceSelfTest(args);
    exit(0);
  }
  if (args.isNotEmpty && args.first == '--self-test-personality') {
    await runPersonalitySelfTest(args);
    exit(0);
  }
  if (args.isNotEmpty && args.first == '--self-test-keychain') {
    await runKeychainSelfTest(args);
    exit(0);
  }
  // iOS Flutter launch arguments are not reliably forwarded to Dart by the
  // simulator. A marker in this app's own support directory gives CI a stable
  // way to exercise the same native keychain plugin before showing the UI.
  if (Platform.isIOS) {
    final support = await getApplicationSupportDirectory();
    final marker = File('${support.path}/run-keychain-self-test');
    if (await marker.exists()) {
      await marker.delete();
      await runKeychainSelfTest([
        '--self-test-keychain',
        '${support.path}/keychain-test.json',
      ]);
      exit(0);
    }
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
  ChatEntry(
    this.role,
    this.text, [
    List<MediaFrame>? frames,
    this.videoPath,
    this.playbackPath,
  ]) : frames = frames ?? [];
  String role;
  String text;
  List<MediaFrame> frames;
  String? videoPath;
  String? playbackPath;
  Map<String, dynamic> toJson() => {
    'role': role,
    'text': text,
    'frames': frames.map((frame) => frame.toJson()).toList(),
    'videoPath': videoPath,
    'playbackPath': playbackPath,
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
    data['videoPath'] as String?,
    data['playbackPath'] as String?,
  );
}

/// Keep ordinary chat context but exclude captions inferred from old media.
List<ChatEntry> textHistorySinceMedia(List<ChatEntry> history) {
  final lastMedia = history.lastIndexWhere((item) => item.frames.isNotEmpty);
  final first = lastMedia < 0 ? 0 : (lastMedia + 2).clamp(0, history.length);
  final textHistory = history.sublist(first);
  return textHistory.length > 6
      ? textHistory.sublist(textHistory.length - 6)
      : textHistory;
}

bool isMediaFollowup(String text) {
  if (RegExp(
    r'^(?:no|actually|correction)\b',
    caseSensitive: false,
  ).hasMatch(text.trim()))
    return true;
  return RegExp(
    r'\b(?:look again|recheck|review the footage|the (?:video|image|photo|clip|frame)|what(?:\x27s| is) happening|that(?:\x27s| is) (?:my|her|him))\b',
    caseSensitive: false,
  ).hasMatch(text);
}

class Conversation {
  Conversation(
    this.id,
    this.title, [
    List<ChatEntry>? entries,
    this.personality = 'Default',
    this.customPersonality = '',
    this.memory = '',
  ]) : entries = entries ?? [];
  String id;
  String title;
  List<ChatEntry> entries;
  String personality;
  String customPersonality;
  String memory;
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'entries': entries.map((entry) => entry.toJson()).toList(),
    'personality': personality,
    'customPersonality': customPersonality,
    'memory': memory,
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
    data['personality'] as String? ?? 'Default',
    data['customPersonality'] as String? ?? '',
    data['memory'] as String? ?? '',
  );
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const autoModelPath = '__auto__';
  static const defaultInstructions =
      'You are a private local assistant. Answer the latest user message directly and naturally. Do not simply repeat the user’s words. Treat a user correction as newer information. Only claim to see images or video when media is attached to this message.';
  final draft = TextEditingController();
  final models = <LocalModel>[];
  final chats = <Conversation>[];
  final attachments = <MediaFrame>[];
  Directory? dataDir;
  String? modelPath;
  String? chatId;
  String status = 'Loading local data…';
  String instructions = defaultInstructions;
  bool busy = false;
  bool cancelled = false;
  LlamaCancellationController? activeGeneration;
  int frameCount = 4;
  int maxTokens = 400;
  String themeName = 'Aurora';
  Color customColor = const Color(0xFF55C8FF);
  Color starColor = const Color(0xFFB6DCFF);
  Color starBackgroundColor = const Color(0xFF091326);
  Color auroraColor = const Color(0xFF58F6BA);
  String backgroundStyle = 'Waves';
  bool motion = true;
  double motionSpeed = 1.0;
  SpeechService? speech;
  String? speechRoot;
  bool voiceRecording = false;
  bool voiceWorking = false;
  bool autoSpeak = true;
  int selectedVoice = 5;
  String voiceSource = 'Offline';
  String fishVoiceId = '';
  bool fishHasKey = false;
  bool callActive = false;
  bool callMuted = false;
  final ValueNotifier<String> callStatus = ValueNotifier('Ready to call');
  int callEpoch = 0;
  bool callSendNow = false;
  int voiceEpoch = 0;
  final ModelDownloader downloader = ModelDownloader();
  bool downloading = false;
  final SpeechDownloader speechDownloader = SpeechDownloader();
  bool downloadingSpeech = false;
  bool samplingVideo = false;
  String? currentVideoPath;
  String? currentVideoPlaybackPath;
  int? currentVideoDurationMs;
  Future<void> _saveQueue = Future<void>.value();

  Conversation get chat => chats.firstWhere((item) => item.id == chatId);
  LocalModel? get selectedModel {
    if (attachments.isNotEmpty) {
      for (final model in models) {
        if (model.path == modelPath && model.vision) return model;
      }
      for (final model in models) {
        if (model.vision && model.name.contains('Qwen3 VL')) return model;
      }
      for (final model in models) {
        if (model.vision && model.name.contains('Qwen3.5')) return model;
      }
      for (final model in models) {
        if (model.vision) return model;
      }
    }
    if (modelPath == autoModelPath) {
      if (attachments.isNotEmpty) {
        for (final model in models) {
          if (model.vision && model.name.contains('Qwen3 VL')) return model;
        }
        for (final model in models) {
          if (model.vision && model.name.contains('Qwen3.5')) return model;
        }
        for (final model in models) {
          if (model.vision) return model;
        }
      } else {
        for (final model in models) {
          if (!model.vision && model.name.contains('Nymphaea')) return model;
        }
        for (final model in models) {
          if (model.vision && model.name.contains('Qwen3.5')) return model;
        }
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
    callEpoch++;
    callStatus.dispose();
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

  Future<void> downloadDetailedVisionModel() async {
    if (downloading || dataDir == null) return;
    final directory = dataDir!.path + Platform.pathSeparator + 'models';
    setState(() {
      downloading = true;
      status = 'Downloading detailed vision model (about 3 GB)…';
    });
    var lastShownMiB = -1;
    try {
      final files = await downloader.downloadDetailedVision(directory, (
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
          LocalModel(
            'Qwen3.5 4B Uncensored · vision',
            files.model,
            files.projector,
          ),
        );
      }
      modelPath = autoModelPath;
      setState(
        () => status =
            'Detailed vision model and projector passed SHA-256 checks.',
      );
      await save();
    } catch (error) {
      if (mounted) showProblem('Model download failed: $error');
    } finally {
      if (mounted) setState(() => downloading = false);
    }
  }

  Future<void> downloadRoleplayModel() async {
    if (downloading || dataDir == null) return;
    final directory = dataDir!.path + Platform.pathSeparator + 'models';
    setState(() {
      downloading = true;
      status = 'Downloading adult roleplay model (about 2.5 GB)…';
    });
    var lastShownMiB = -1;
    try {
      final path = await downloader.downloadRoleplay(directory, (
        name,
        received,
        total,
      ) {
        final currentMiB = received ~/ 1048576;
        if (currentMiB == lastShownMiB || !mounted) return;
        lastShownMiB = currentMiB;
        setState(
          () => status =
              '${name.startsWith('Verifying ') ? '' : 'Downloading '}$name · $currentMiB MiB' +
              (total == null ? '' : ' / ${total ~/ 1048576} MiB'),
        );
      });
      if (!models.any((item) => item.path == path)) {
        models.add(LocalModel('Nymphaea 4B · adult roleplay', path));
      }
      modelPath = path;
      setState(() => status = 'Roleplay model passed SHA-256 verification.');
      await save();
    } catch (error) {
      if (mounted) showProblem('Roleplay model download failed: $error');
    } finally {
      if (mounted) setState(() => downloading = false);
    }
  }

  Future<void> downloadAdultVisionModel() async {
    if (downloading || dataDir == null) return;
    final directory = '${dataDir!.path}${Platform.pathSeparator}models';
    setState(() {
      downloading = true;
      status =
          'Downloading adult-capable vision model and projector (about 3 GB)…';
    });
    var lastProgress = '';
    try {
      final files = await downloader.downloadAdultVision(directory, (
        name,
        received,
        total,
      ) {
        final progress =
            '$name · ${received ~/ 1048576} MiB'
            '${total == null ? '' : ' / ${total ~/ 1048576} MiB'}';
        if (progress == lastProgress || !mounted) return;
        lastProgress = progress;
        setState(
          () => status = name.startsWith('Verifying ')
              ? progress
              : 'Downloading $progress',
        );
      });
      if (!models.any((item) => item.path == files.model)) {
        models.add(
          LocalModel(
            'Qwen3 VL 4B Abliterated · vision',
            files.model,
            files.projector,
          ),
        );
      }
      modelPath = files.model;
      if (mounted)
        setState(
          () => status = 'Adult vision model passed SHA-256 verification.',
        );
      await save();
    } catch (error) {
      if (mounted) showProblem('Vision model download failed: $error');
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
          final savedPlayback = data['currentVideoPlaybackPath'] as String?;
          currentVideoPlaybackPath =
              savedPlayback != null && await File(savedPlayback).exists()
              ? savedPlayback
              : savedVideoPath;
          currentVideoDurationMs = data['currentVideoDurationMs'] as int?;
        }
        instructions = data['instructions'] as String? ?? instructions;
        if (routingVersion < 3 &&
            (instructions ==
                    'You are a private, helpful local assistant. Answer directly and honestly.' ||
                instructions ==
                    'You are a private local assistant. Answer the latest user message directly. Describe only details visible in attached images or video frames, including adult nudity when visible. Do not invent unseen anatomy, actions, or a story. Treat a user correction as newer information and do not repeat an earlier mistaken answer.')) {
          instructions = defaultInstructions;
        }
        final savedFrameCount = data['frameCount'] as int?;
        // Older versions defaulted to eight large frames. Four smaller frames
        // cover a short clip on an iPhone without making every send take minutes.
        frameCount =
            (routingVersion < 2 && savedFrameCount == 8
                    ? 4
                    : (savedFrameCount ?? 4))
                .clamp(4, 12)
                .toInt();
        maxTokens = data['maxTokens'] as int? ?? 400;
        themeName = data['themeName'] as String? ?? 'Aurora';
        if (!GlassPalette.presets.containsKey(themeName)) themeName = 'Aurora';
        customColor = Color(data['customColor'] as int? ?? 0xFF55C8FF);
        starColor = Color(data['starColor'] as int? ?? 0xFFB6DCFF);
        starBackgroundColor = Color(
          data['starBackgroundColor'] as int? ?? 0xFF091326,
        );
        auroraColor = Color(data['auroraColor'] as int? ?? 0xFF58F6BA);
        backgroundStyle = data['backgroundStyle'] as String? ?? 'Waves';
        motion = data['motion'] as bool? ?? true;
        motionSpeed = (data['motionSpeed'] as num?)?.toDouble() ?? 1.0;
        speechRoot = data['speechRoot'] as String?;
        autoSpeak = data['autoSpeak'] as bool? ?? true;
        selectedVoice = data['selectedVoice'] as int? ?? 5;
        if (!SpeechService.voices.any((item) => item.id == selectedVoice))
          selectedVoice = 5;
        voiceSource = data['voiceSource'] as String? ?? 'Offline';
        fishVoiceId = data['fishVoiceId'] as String? ?? '';
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
        for (final base in [
          '$executableDir/models/qwen35-4b-uncensored',
          'D:/LocalAIChat/models/qwen35-4b-uncensored',
        ]) {
          final path = '$base/${ModelDownloader.detailedVisionName}';
          final projector = '$base/${ModelDownloader.detailedProjectorName}';
          if (await File(path).exists() &&
              await File(projector).exists() &&
              !models.any((item) => item.path == path)) {
            models.add(
              LocalModel('Qwen3.5 4B Uncensored · vision', path, projector),
            );
            break;
          }
        }
        for (final base in [
          '$executableDir/models/qwen3-vl-4b-abliterated',
          'D:/LocalAIChat/models/qwen3-vl-4b-abliterated',
        ]) {
          final path = '$base/${ModelDownloader.adultVisionName}';
          final projector = '$base/${ModelDownloader.adultProjectorName}';
          if (await File(path).exists() &&
              await File(projector).exists() &&
              !models.any((item) => item.path == path)) {
            models.add(
              LocalModel('Qwen3 VL 4B Abliterated · vision', path, projector),
            );
            break;
          }
        }
        for (final base in [
          '$executableDir/models/qwen3-4b-nymphaea-rp',
          'D:/LocalAIChat/models/qwen3-4b-nymphaea-rp',
        ]) {
          final path = '$base/${ModelDownloader.roleplayName}';
          if (await File(path).exists() &&
              !models.any((item) => item.path == path)) {
            models.add(LocalModel('Nymphaea 4B · adult roleplay', path));
            break;
          }
        }
        // A portable ZIP may be extracted to a new folder on upgrade. Keep
        // existing model selections working when the old folder is removed.
        for (final item in models) {
          if (await File(item.path).exists()) continue;
          final oldPath = item.path;
          final filename = oldPath.split(RegExp(r'[/\\]')).last;
          for (final folder in [
            'smolvlm2-500m',
            'qwen25-1.5b-abliterated',
            'qwen35-4b-uncensored',
            'qwen3-vl-4b-abliterated',
            'qwen3-4b-nymphaea-rp',
          ]) {
            final candidate = '$executableDir/models/$folder/$filename';
            if (await File(candidate).exists()) {
              item.path = candidate;
              if (modelPath == oldPath) modelPath = candidate;
              final projector = item.projector;
              if (projector != null) {
                final projectorName = projector.split(RegExp(r'[/\\]')).last;
                final newProjector =
                    '$executableDir/models/$folder/$projectorName';
                if (await File(newProjector).exists())
                  item.projector = newProjector;
              }
              break;
            }
          }
        }
      }
      if (routingVersion == 0 &&
          models.any((item) => item.vision) &&
          models.any((item) => !item.vision)) {
        modelPath = autoModelPath;
      }
      if (speechRoot == null ||
          (Platform.isWindows && !await SpeechService.hasModels(speechRoot!))) {
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
      try {
        fishHasKey = await FishVoice.hasKey;
      } catch (_) {
        fishHasKey = false;
      }
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
        'routingVersion': 3,
        'chatId': chatId,
        'draft': draft.text,
        'draftFrames': attachments.map((frame) => frame.toJson()).toList(),
        'currentVideoPath': currentVideoPath,
        'currentVideoPlaybackPath': currentVideoPlaybackPath,
        'currentVideoDurationMs': currentVideoDurationMs,
        'instructions': instructions,
        'frameCount': frameCount,
        'maxTokens': maxTokens,
        'themeName': themeName,
        'customColor': customColor.toARGB32(),
        'starColor': starColor.toARGB32(),
        'starBackgroundColor': starBackgroundColor.toARGB32(),
        'auroraColor': auroraColor.toARGB32(),
        'backgroundStyle': backgroundStyle,
        'motion': motion,
        'motionSpeed': motionSpeed,
        'speechRoot': speechRoot,
        'autoSpeak': autoSpeak,
        'selectedVoice': selectedVoice,
        'voiceSource': voiceSource,
        'fishVoiceId': fishVoiceId,
      }),
    );
    if (await file.exists()) await file.delete();
    await temp.rename(file.path);
  }

  void createChat({bool saveNow = true}) {
    if (busy || callActive) return;
    final discarded = [
      for (final frame in attachments) frame.path,
      if (currentVideoPath != null) currentVideoPath!,
      if (currentVideoPlaybackPath != null) currentVideoPlaybackPath!,
    ];
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    chats.insert(0, Conversation(id, 'New chat'));
    chatId = id;
    draft.clear();
    attachments.clear();
    currentVideoPath = null;
    currentVideoPlaybackPath = null;
    currentVideoDurationMs = null;
    if (mounted) setState(() {});
    if (saveNow) {
      unawaited(save().then((_) => deleteUnreferencedMedia(discarded)));
    }
  }

  Future<bool> confirmDelete(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> deleteConversation(Conversation item) async {
    if (busy || callActive) return;
    if (!await confirmDelete(
      'Delete conversation?',
      'This deletes its messages and saved memory from this device.',
    ))
      return;
    final paths = item.entries
        .expand(
          (entry) => [
            for (final frame in entry.frames) frame.path,
            if (entry.videoPath != null) entry.videoPath!,
            if (entry.playbackPath != null) entry.playbackPath!,
          ],
        )
        .toList();
    setState(() {
      chats.remove(item);
      if (chats.isEmpty) {
        final id = DateTime.now().microsecondsSinceEpoch.toString();
        chats.add(Conversation(id, 'New chat'));
      }
      if (chatId == item.id) chatId = chats.first.id;
    });
    await save();
    await deleteUnreferencedMedia(paths);
  }

  Future<void> deleteMessage(ChatEntry entry) async {
    if (busy || callActive) return;
    if (!await confirmDelete(
      'Delete message?',
      'This removes the message from this conversation.',
    ))
      return;
    final paths = [
      for (final frame in entry.frames) frame.path,
      if (entry.videoPath != null) entry.videoPath!,
      if (entry.playbackPath != null) entry.playbackPath!,
    ];
    setState(() {
      chat.entries.remove(entry);
      if (entry.role == 'user') {
        final remembered = ChatContext.explicitMemory(entry.text);
        if (remembered != null) {
          chat.memory = ChatContext.removeMemory(chat.memory, remembered);
        }
      }
    });
    await save();
    await deleteUnreferencedMedia(paths);
  }

  Future<void> deleteUnreferencedMedia(List<String> paths) async {
    if (dataDir == null) return;
    final referenced = {
      for (final item in chats)
        for (final entry in item.entries) ...[
          for (final frame in entry.frames) frame.path,
          if (entry.videoPath != null) entry.videoPath!,
          if (entry.playbackPath != null) entry.playbackPath!,
        ],
      for (final frame in attachments) frame.path,
      if (currentVideoPath != null) currentVideoPath!,
      if (currentVideoPlaybackPath != null) currentVideoPlaybackPath!,
    };
    for (final path in paths.toSet()) {
      final ownedMedia =
          ['media', 'frames'].any(
            (folder) => path.startsWith(
              '${dataDir!.path}${Platform.pathSeparator}$folder${Platform.pathSeparator}',
            ),
          ) ||
          (Platform.isWindows &&
              path
                  .replaceAll('/', '\\')
                  .toLowerCase()
                  .startsWith('d:\\localaichat\\media\\'));
      if (!ownedMedia || referenced.contains(path)) continue;
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
  }

  Future<void> showChatOptions() async {
    if (chats.isEmpty || busy || callActive) return;
    final current = chat;
    var personality = current.personality;
    final custom = TextEditingController(text: current.customPersonality);
    final memory = TextEditingController(text: current.memory);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, update) => AlertDialog(
          title: const Text('This conversation'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue:
                        ChatContext.personalities.containsKey(personality)
                        ? personality
                        : 'Default',
                    decoration: const InputDecoration(labelText: 'Personality'),
                    items: ChatContext.personalities.keys
                        .map(
                          (name) =>
                              DropdownMenuItem(value: name, child: Text(name)),
                        )
                        .toList(),
                    onChanged: (value) =>
                        update(() => personality = value ?? personality),
                  ),
                  if (personality == 'Custom')
                    TextField(
                      controller: custom,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'How should the AI act?',
                      ),
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: memory,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Saved memory',
                      helperText: 'Facts here are sent with every message in this chat.',
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'You can also say “remember that …” or “correction: …” in chat.',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                setState(() {
                  current.personality = personality;
                  current.customPersonality = custom.text.trim();
                  current.memory = memory.text.trim();
                });
                unawaited(save());
                Navigator.pop(dialogContext);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    custom.dispose();
    memory.dispose();
  }

  Future<String> copyIntoApp(String path, String folder) async {
    final dir = Directory(
      Platform.isWindows &&
              folder == 'media' &&
              await Directory('D:/LocalAIChat').exists()
          ? 'D:/LocalAIChat/media'
          : dataDir!.path + Platform.pathSeparator + folder,
    );
    await dir.create(recursive: true);
    final name = path.split(RegExp(r'[/\\]')).last;
    final destination =
        '${dir.path}${Platform.pathSeparator}'
        '${DateTime.now().microsecondsSinceEpoch}_$name';
    if (Platform.isIOS) {
      final temporary = await getTemporaryDirectory();
      final appRoot = dataDir!.parent.parent.path;
      final pickedCache =
          path.startsWith('${temporary.path}/') ||
          path.startsWith('$appRoot/Library/Caches/');
      if (pickedCache) {
        try {
          return (await File(path).rename(destination)).path;
        } on FileSystemException {
          // Some document providers require a copy even for cached picker files.
        }
      }
    }
    return (await File(path).copy(destination)).path;
  }

  Future<void> importModel({required bool projector}) async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    final path = result?.files.single.path;
    if (path == null) return;
    try {
      if (!path.toLowerCase().endsWith('.gguf')) {
        throw const FormatException('Choose a .gguf model or projector file.');
      }
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
      var ready = owned;
      if (Platform.isIOS) {
        final destination = '$owned.jpg';
        try {
          ready =
              await const MethodChannel('local_ai_chat/media')
                  .invokeMethod<String>('prepareImage', {
                    'source': owned,
                    'destination': destination,
                  }) ??
              (throw StateError('The image converter returned no file.'));
          await File(owned).delete();
        } catch (_) {
          await File(owned).delete();
          rethrow;
        }
      }
      setState(() => attachments.add(MediaFrame(ready)));
      await save();
    } catch (error) {
      showProblem('Image import failed: $error');
    }
  }

  Future<void> attachVideo() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.video);
    final path = result?.files.single.path;
    if (path == null) return;
    if (samplingVideo || dataDir == null) return;
    if (currentVideoPath != null) {
      showProblem('Remove the current video before attaching another one.');
      return;
    }
    setState(() {
      samplingVideo = true;
      status = 'Saving video on this device…';
    });
    String? ownedVideo;
    String? playbackVideo;
    try {
      ownedVideo = await copyIntoApp(path, 'media');
      final duration = (await VideoDuration.read(ownedVideo)).inMilliseconds;
      if (duration <= 0) throw StateError('Video duration is unavailable.');
      if (mounted) setState(() => status = 'Preparing local video playback…');
      playbackVideo = await VideoSampler.prepareWindowsPlayback(
        source: ownedVideo,
        destination: '$ownedVideo.playback.mp4',
      );
      if (mounted) setState(() => status = 'Scanning video on this device…');
      final frames = await VideoSampler.sample(
        video: ownedVideo,
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
        currentVideoPath = ownedVideo;
        currentVideoPlaybackPath = playbackVideo;
        currentVideoDurationMs = duration;
        status =
            'Video ready. The AI will inspect ${frames.length} selected frames.';
      });
      await save();
    } catch (error) {
      for (final candidate in [playbackVideo, ownedVideo]) {
        if (candidate == null) continue;
        final file = File(candidate);
        if (await file.exists()) await file.delete();
      }
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

  Future<void> removeDraftVideo() async {
    final discarded = [
      if (currentVideoPath != null) currentVideoPath!,
      if (currentVideoPlaybackPath != null) currentVideoPlaybackPath!,
      for (final frame in attachments)
        if (frame.timeMs != null) frame.path,
    ];
    setState(() {
      attachments.removeWhere((frame) => frame.timeMs != null);
      currentVideoPath = null;
      currentVideoPlaybackPath = null;
      currentVideoDurationMs = null;
    });
    await save();
    await deleteUnreferencedMedia(discarded);
  }

  void stopGeneration() {
    cancelled = true;
    activeGeneration?.cancel();
    voiceEpoch++;
    unawaited(speech?.stopSpeaking() ?? Future<void>.value());
    if (mounted) setState(() => status = 'Stopping…');
  }

  Future<void> send({bool speakOnComplete = true}) async {
    if (busy || samplingVideo) return;
    if (dataDir == null) {
      showProblem(
        'Local data is still loading. Try sending again in a moment.',
      );
      return;
    }
    final prompt = draft.text.trim();
    final lastMediaIndex = chat.entries.lastIndexWhere(
      (entry) => entry.role == 'user' && entry.frames.isNotEmpty,
    );
    final reuseFrames =
        attachments.isEmpty &&
        lastMediaIndex >= 0 &&
        chat.entries.length - lastMediaIndex <= 4 &&
        isMediaFollowup(prompt);
    final inferenceFrames = attachments.isNotEmpty
        ? List<MediaFrame>.of(attachments)
        : reuseFrames
        ? List<MediaFrame>.of(chat.entries[lastMediaIndex].frames)
        : <MediaFrame>[];
    final initiallySelectedModel = selectedModel;
    if (initiallySelectedModel == null) {
      showProblem('Choose or download a local model before sending.');
      return;
    }
    var model = initiallySelectedModel;
    if (inferenceFrames.isNotEmpty && !model.vision) {
      final adultVision = models.where(
        (candidate) => candidate.vision && candidate.name.contains('Qwen3 VL'),
      );
      final detailed = models.where(
        (candidate) => candidate.vision && candidate.name.contains('Qwen3.5'),
      );
      if (adultVision.isNotEmpty) {
        model = adultVision.first;
      } else if (detailed.isNotEmpty) {
        model = detailed.first;
      } else {
        for (final candidate in models) {
          if (candidate.vision) {
            model = candidate;
            break;
          }
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
    if (prompt.isEmpty && attachments.isEmpty) return;
    final question = ChatEntry(
      'user',
      prompt.isEmpty ? 'Describe these images.' : prompt,
      List.of(attachments),
      currentVideoPath,
      currentVideoPlaybackPath,
    );
    final remembered = ChatContext.explicitMemory(question.text);
    if (remembered != null) {
      chat.memory = ChatContext.addMemory(chat.memory, remembered);
    }
    final originalVideoPath = currentVideoPath;
    final originalVideoPlaybackPath = currentVideoPlaybackPath;
    final originalVideoDurationMs = currentVideoDurationMs;
    chat.entries.add(question);
    if (chat.title == 'New chat')
      chat.title = question.text.length > 38
          ? question.text.substring(0, 38)
          : question.text;
    draft.clear();
    attachments.clear();
    currentVideoPath = null;
    currentVideoPlaybackPath = null;
    currentVideoDurationMs = null;
    final reply = ChatEntry('assistant', '');
    chat.entries.add(reply);
    setState(() {
      busy = true;
      cancelled = false;
      status = 'Loading model locally…';
    });
    final cancellation = LlamaCancellationController();
    activeGeneration = cancellation;
    try {
      await save();
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
      // A text-only model cannot inspect previous media. Do not feed it an
      // earlier vision answer as if it were fresh visual evidence.
      final recent = textHistorySinceMedia(history);
      for (final item in inferenceFrames.isEmpty ? recent : <ChatEntry>[]) {
        final text = item.text.length > 900
            ? item.text.substring(0, 900)
            : item.text;
        input.add(
          LlamaResponseInputItem(
            role: item.role,
            content: [LlamaTextPart(text)],
          ),
        );
      }
      final parts = <LlamaContentPart>[LlamaTextPart(question.text)];
      final isVideo = inferenceFrames.any((frame) => frame.timeMs != null);
      if (isVideo) {
        parts.add(
          const LlamaTextPart(
            'Describe the main foreground action across these video frames in 2 or 3 concise sentences. State clearly visible adult nudity or sexual activity in plain terms. Focus on what the person is doing; mention the background only when needed to understand the action. Do not guess what a screen displays or infer unseen movement, anatomy, or dialogue. If the frames cannot establish an action, say so briefly.',
          ),
        );
      } else if (inferenceFrames.isNotEmpty) {
        parts.add(
          const LlamaTextPart(
            'Use only these attached images as visual evidence. State the main visible actions and any visible nudity plainly. Do not guess body parts that are covered, too small to see, or inside the body. Do not make a repetitive body-part list.',
          ),
        );
      }
      for (final frame in inferenceFrames) {
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
        engine: LibLlamaCpp(cancellation: cancellation),
        models: {
          'active': LlamaModelConfig(
            modelPath: model.path,
            mmprojPath: model.projector,
            contextSize: model.vision ? 4096 : 2048,
            gpuLayerCount: 0,
          ),
        },
      );
      setState(() => status = 'Generating on this device…');
      var rawReply = '';
      var stoppedForLoop = false;
      await for (final event in client.responses.stream(
        model: 'active',
        input: input,
        instructions:
            ChatContext.instructions(
              global: instructions,
              personality: chat.personality,
              customPersonality: chat.customPersonality,
              memory: chat.memory,
            ) +
            (model.name.toLowerCase().contains('qwen3') ? '\n/no_think' : ''),
        maxOutputTokens: model.vision && inferenceFrames.isNotEmpty
            ? maxTokens.clamp(80, isVideo ? 160 : 260)
            : maxTokens,
        temperature: 0.65,
        topP: 0.90,
      )) {
        if (cancelled) break;
        if (event is LlamaResponseOutputTextDelta) {
          rawReply += event.delta;
          final visible = visibleReply(rawReply);
          final repeatedFrom = repetitiveSentenceRunStart(visible);
          if (mounted) {
            setState(
              () => reply.text = repeatedFrom == null
                  ? visible
                  : visible.substring(0, repeatedFrom).trimRight(),
            );
          }
          if (repeatedFrom != null || isRepeatingReply(visible)) {
            stoppedForLoop = true;
            cancellation.cancel();
            break;
          }
        } else if (event is LlamaResponseFailed) {
          throw StateError(event.error.message);
        }
      }
      if (!cancelled &&
          !stoppedForLoop &&
          inferenceFrames.isEmpty &&
          (isEchoedReply(reply.text, question.text) ||
              isDetachedMediaReply(reply.text, question.text))) {
        final better = models
            .where(
              (candidate) =>
                  !candidate.vision && candidate.name.contains('Nymphaea'),
            )
            .firstOrNull;
        final retryModel = better ?? model;
        if (mounted) {
          setState(() {
            reply.text = '';
            status = 'Retrying a direct answer…';
          });
        }
        final retryClient = LlamaOpenAIClient(
          engine: LibLlamaCpp(cancellation: cancellation),
          models: {
            'retry': LlamaModelConfig(
              modelPath: retryModel.path,
              contextSize: 2048,
              gpuLayerCount: 0,
            ),
          },
        );
        var retryRaw = '';
        await for (final event in retryClient.responses.stream(
          model: 'retry',
          input: input,
          instructions:
              '${ChatContext.instructions(global: instructions, personality: chat.personality, customPersonality: chat.customPersonality, memory: chat.memory)}\nThis turn has no attached media. Answer the user’s question conversationally and directly. Do not echo the question or describe an image or frame.\n/no_think',
          maxOutputTokens: maxTokens,
          temperature: 0.7,
          topP: 0.9,
        )) {
          if (cancelled) break;
          if (event is LlamaResponseOutputTextDelta) {
            retryRaw += event.delta;
            if (mounted) setState(() => reply.text = visibleReply(retryRaw));
          } else if (event is LlamaResponseFailed) {
            throw StateError(event.error.message);
          }
        }
        if (!cancelled &&
            (isEchoedReply(reply.text, question.text) ||
                isDetachedMediaReply(reply.text, question.text))) {
          reply.text =
              'I could not answer that clearly. Please try another model.';
        } else if (!cancelled && retryModel.path != model.path) {
          modelPath = retryModel.path;
        }
      }
      if (reply.text.isEmpty)
        reply.text = cancelled
            ? '[Stopped]'
            : stoppedForLoop
            ? '[The model repeated itself. Try another model or fewer frames.]'
            : '[No response]';
      if (mounted) {
        setState(
          () => status = cancelled
              ? 'Stopped'
              : stoppedForLoop
              ? 'Stopped a repetitive reply.'
              : 'Ready',
        );
      }
      if (!cancelled &&
          speakOnComplete &&
          autoSpeak &&
          reply.text.isNotEmpty &&
          !reply.text.startsWith('[')) {
        final epoch = voiceEpoch;
        try {
          final service = speech;
          if (service == null) {
            throw StateError('Set up speech in Voice settings.');
          }
          if (mounted) setState(() => status = 'Preparing voice reply…');
          final audioPath = await synthesizeReply(reply.text);
          if (cancelled || epoch != voiceEpoch) {
            final file = File(audioPath);
            if (await file.exists()) await file.delete();
          } else {
            if (mounted) setState(() => status = 'Speaking…');
            await service.playFile(audioPath);
            if (mounted && !cancelled) setState(() => status = 'Ready');
          }
        } catch (error) {
          if (mounted && !cancelled) {
            setState(() => status = 'Voice failed: $error');
          }
        }
      }
    } catch (error) {
      if (cancelled) {
        if (reply.text.isEmpty) reply.text = '[Stopped]';
        if (mounted) setState(() => status = 'Stopped');
        return;
      }
      chat.entries.remove(reply);
      chat.entries.remove(question);
      if (draft.text.trim().isEmpty) draft.text = question.text;
      attachments.insertAll(0, question.frames);
      currentVideoPath = originalVideoPath;
      currentVideoPlaybackPath = originalVideoPlaybackPath;
      currentVideoDurationMs = originalVideoDurationMs;
      final message = error.toString().contains('Failed to load model:')
          ? 'Could not load ${model.name}. Close other apps and retry; if it keeps failing, remove and download or import that model again. Your draft is saved.'
          : 'Local generation failed: $error';
      showProblem(message);
    } finally {
      if (identical(activeGeneration, cancellation)) activeGeneration = null;
      if (mounted) setState(() => busy = false);
      await save();
    }
  }

  Future<void> toggleVoice() async {
    final service = speech;
    if (service == null || dataDir == null) return;
    if (voiceWorking && !voiceRecording) {
      stopGeneration();
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
        await send(speakOnComplete: false);
        if (epoch != voiceEpoch || !autoSpeak) return;
        final reply = chat.entries.isEmpty ? '' : chat.entries.last.text;
        if (reply.isEmpty || reply.startsWith('[')) return;
        setState(() => status = 'Preparing local speech…');
        final wav = await synthesizeReply(reply);
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

  Future<String> synthesizeReply(String reply) async {
    final extension = voiceSource == 'Fish Audio' ? 'mp3' : 'wav';
    final output =
        '${dataDir!.path}${Platform.pathSeparator}reply_${DateTime.now().microsecondsSinceEpoch}.$extension';
    if (voiceSource == 'Fish Audio') {
      return FishVoice.synthesize(
        FishVoice.performanceText(reply, chat.personality),
        fishVoiceId,
        output,
      );
    }
    return speech!.synthesize(reply, output, voiceId: selectedVoice);
  }

  Future<void> endVoiceCall() async {
    callEpoch++;
    callActive = false;
    stopGeneration();
    final service = speech;
    if (service != null) {
      if (service.recording) {
        try {
          await service.stopRecording();
        } catch (_) {}
      }
      await service.stopSpeaking();
    }
    if (mounted) setState(() => status = 'Call ended.');
  }

  Future<void> runVoiceCall(int epoch) async {
    final service = speech;
    if (service == null || dataDir == null) return;
    final recordings = Directory(
      '${dataDir!.path}${Platform.pathSeparator}recordings',
    );
    await recordings.create(recursive: true);
    while (mounted && callActive && epoch == callEpoch) {
      if (callMuted) {
        callStatus.value = 'Microphone muted';
        await Future.delayed(const Duration(milliseconds: 200));
        continue;
      }
      try {
        callStatus.value = 'Listening…';
        final path =
            '${recordings.path}${Platform.pathSeparator}call_${DateTime.now().microsecondsSinceEpoch}.wav';
        await service.startRecording(path);
        final started = DateTime.now();
        DateTime? lastVoice;
        var voiceHits = 0;
        while (callActive && epoch == callEpoch && !callMuted) {
          await Future.delayed(const Duration(milliseconds: 200));
          final level = await service.microphoneLevel();
          if (level > -37) {
            voiceHits++;
            lastVoice = DateTime.now();
          }
          final elapsed = DateTime.now().difference(started);
          if (callSendNow ||
              elapsed > const Duration(seconds: 30) ||
              (voiceHits >= 2 &&
                  lastVoice != null &&
                  DateTime.now().difference(lastVoice) >
                      const Duration(milliseconds: 1200)) ||
              (voiceHits == 0 && elapsed > const Duration(seconds: 9)))
            break;
        }
        final manuallySent = callSendNow;
        callSendNow = false;
        if (!callActive ||
            epoch != callEpoch ||
            callMuted ||
            (voiceHits < 2 && !manuallySent)) {
          if (service.recording) await service.stopRecording();
          continue;
        }
        callStatus.value = 'Transcribing on this device…';
        final transcript = await service.stopAndTranscribe();
        if (transcript.trim().isEmpty || !callActive || epoch != callEpoch)
          continue;
        draft.text = transcript.trim();
        callStatus.value = 'You: ${transcript.trim()}';
        final before = chat.entries.length;
        await send(speakOnComplete: false);
        if (!callActive || epoch != callEpoch || chat.entries.length <= before)
          continue;
        final answer = chat.entries.last;
        if (answer.role != 'assistant' ||
            answer.text.isEmpty ||
            answer.text.startsWith('['))
          continue;
        callStatus.value = voiceSource == 'Fish Audio'
            ? 'Preparing Fish Audio voice…'
            : 'Preparing ${SpeechService.voices.firstWhere((item) => item.id == selectedVoice).name}…';
        final wav = await synthesizeReply(answer.text);
        if (!callActive || epoch != callEpoch) {
          final file = File(wav);
          if (await file.exists()) await file.delete();
          continue;
        }
        callStatus.value = 'Speaking…';
        await service.playFile(wav);
      } catch (error) {
        if (service.recording) {
          try {
            await service.stopRecording();
          } catch (_) {}
        }
        if (!callActive || epoch != callEpoch) break;
        callStatus.value = 'Call error: $error';
        await Future.delayed(const Duration(seconds: 2));
      }
    }
  }

  Future<void> showVoiceCall() async {
    final service = speech;
    if (service == null || dataDir == null || busy || voiceRecording) return;
    if (!await service.modelsReady) {
      showProblem('Download the five offline voices in Settings first.');
      return;
    }
    if (selectedModel == null) {
      showProblem('Choose a local chat model before calling.');
      return;
    }
    if (voiceSource == 'Fish Audio' &&
        (!await FishVoice.hasKey || fishVoiceId.trim().isEmpty)) {
      showProblem('Add a Fish Audio key and voice ID in Voice settings first.');
      return;
    }
    callEpoch++;
    final epoch = callEpoch;
    callMuted = false;
    callActive = true;
    callStatus.value = 'Starting local call…';
    unawaited(runVoiceCall(epoch));
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => GlassDesign(
        themeName: themeName,
        customColor: customColor,
        starColor: starColor,
        starBackgroundColor: starBackgroundColor,
        auroraColor: auroraColor,
        motion: motion,
        speed: motionSpeed,
        backgroundStyle: backgroundStyle,
        child: StatefulBuilder(
          builder: (dialogContext, update) => Dialog(
            backgroundColor: Colors.transparent,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: GlassSurface(
                padding: const EdgeInsets.all(25),
                radius: 30,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Local voice call',
                      style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      width: 118,
                      height: 118,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            GlassPalette.resolve(themeName, customColor).accent,
                            Colors.transparent,
                          ],
                        ),
                      ),
                      child: const Icon(Icons.graphic_eq, size: 58),
                    ),
                    const SizedBox(height: 18),
                    ValueListenableBuilder<String>(
                      valueListenable: callStatus,
                      builder: (context, value, _) =>
                          Text(value, textAlign: TextAlign.center),
                    ),
                    const SizedBox(height: 18),
                    if (voiceSource == 'Offline')
                      DropdownButton<int>(
                        value: selectedVoice,
                        items: SpeechService.voices
                            .map(
                              (item) => DropdownMenuItem(
                                value: item.id,
                                child: Text('${item.name} · ${item.gender}'),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          update(() => selectedVoice = value);
                          unawaited(save());
                        },
                      ),
                    const SizedBox(height: 12),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 12,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => update(() => callMuted = !callMuted),
                          icon: Icon(callMuted ? Icons.mic_off : Icons.mic),
                          label: Text(callMuted ? 'Unmute' : 'Mute'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => callSendNow = true,
                          icon: const Icon(Icons.send),
                          label: const Text('Send now'),
                        ),
                        FilledButton.icon(
                          onPressed: () => Navigator.pop(dialogContext),
                          icon: const Icon(Icons.call_end),
                          label: const Text('End call'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await endVoiceCall();
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
              height: MediaQuery.sizeOf(context).height * 0.78,
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
                      OutlinedButton.icon(
                        onPressed: downloading
                            ? null
                            : () async {
                                await downloadDetailedVisionModel();
                                update(() {});
                              },
                        icon: const Icon(Icons.visibility_outlined),
                        label: const Text('Get detailed vision model · 3 GB'),
                      ),
                      OutlinedButton.icon(
                        onPressed: downloading
                            ? null
                            : () async {
                                await downloadAdultVisionModel();
                                update(() {});
                              },
                        icon: const Icon(Icons.visibility),
                        label: const Text('Get adult-capable vision · 3 GB'),
                      ),
                      OutlinedButton.icon(
                        onPressed: downloading
                            ? null
                            : () async {
                                await downloadRoleplayModel();
                                update(() {});
                              },
                        icon: const Icon(Icons.theater_comedy_outlined),
                        label: const Text('Get adult roleplay model · 2.5 GB'),
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
    var selectedCustom = customColor;
    var selectedStar = starColor;
    var selectedStarBackground = starBackgroundColor;
    var selectedAurora = auroraColor;
    final colorController = TextEditingController(
      text: customColor.toARGB32().toRadixString(16).substring(2).toUpperCase(),
    );
    final starColorController = TextEditingController(
      text: starColor.toARGB32().toRadixString(16).substring(2).toUpperCase(),
    );
    final starBackgroundController = TextEditingController(
      text: starBackgroundColor
          .toARGB32()
          .toRadixString(16)
          .substring(2)
          .toUpperCase(),
    );
    final auroraColorController = TextEditingController(
      text: auroraColor.toARGB32().toRadixString(16).substring(2).toUpperCase(),
    );
    var count = frameCount;
    var limit = maxTokens;
    var selectedTheme = themeName;
    var selectedStyle = backgroundStyle;
    var animated = motion;
    var speed = motionSpeed;
    var spokenReplies = autoSpeak;
    var voice = selectedVoice;
    var source = voiceSource;
    final fishIdController = TextEditingController(text: fishVoiceId);
    final fishKeyController = TextEditingController();
    var keySaved = fishHasKey;
    var fishTestStatus = '';
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
                  ExpansionTile(
                    title: const Text('Chat and video'),
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
                        onChanged: (value) =>
                            update(() => count = value.round()),
                      ),
                      Text('Maximum output tokens: ' + limit.toString()),
                      Slider(
                        value: limit.toDouble(),
                        min: 100,
                        max: 1000,
                        divisions: 9,
                        onChanged: (value) =>
                            update(() => limit = value.round()),
                      ),
                    ],
                  ),
                  ExpansionTile(
                    title: const Text('Appearance'),
                    subtitle: Text('$selectedTheme · $selectedStyle'),
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: selectedTheme,
                        decoration: const InputDecoration(
                          labelText: 'Appearance',
                        ),
                        items: GlassPalette.presets.keys
                            .map(
                              (name) => DropdownMenuItem(
                                value: name,
                                child: Text(name),
                              ),
                            )
                            .toList(),
                        onChanged: (value) => update(() {
                          selectedTheme = value ?? selectedTheme;
                          if (selectedTheme == 'Chat Dark')
                            selectedStyle = 'Quiet';
                          if (selectedTheme != 'Chat Dark' &&
                              selectedStyle == 'Quiet') {
                            selectedStyle = 'Waves';
                          }
                        }),
                      ),
                      if (selectedTheme == 'Custom') ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: selectedCustom,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 10),
                            IconButton(
                              tooltip: 'Pick any custom color',
                              icon: const Icon(Icons.colorize),
                              onPressed: () async {
                                final chosen = await pickCustomColor(
                                  context,
                                  selectedCustom,
                                );
                                if (chosen != null)
                                  update(() {
                                    selectedCustom = chosen;
                                    colorController.text = chosen
                                        .toARGB32()
                                        .toRadixString(16)
                                        .substring(2)
                                        .toUpperCase();
                                  });
                              },
                            ),
                            Expanded(
                              child: TextField(
                                controller: colorController,
                                decoration: const InputDecoration(
                                  labelText: 'Custom color (hex)',
                                  prefixText: '#',
                                ),
                                maxLength: 6,
                                onChanged: (value) {
                                  if (RegExp(r'^[0-9a-fA-F]{6}$')
                                      .hasMatch(value)) {
                                    update(
                                      () => selectedCustom = Color(
                                        0xFF000000 |
                                            int.parse(value, radix: 16),
                                      ),
                                    );
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                        Text(
                          'Hue ${HSLColor.fromColor(selectedCustom).hue.round()}°',
                        ),
                        Slider(
                          value: HSLColor.fromColor(selectedCustom).hue,
                          min: 0,
                          max: 360,
                          onChanged: (value) => update(() {
                            selectedCustom = HSLColor.fromColor(selectedCustom)
                                .withHue(value)
                                .toColor();
                            colorController.text = selectedCustom
                                .toARGB32()
                                .toRadixString(16)
                                .substring(2)
                                .toUpperCase();
                          }),
                        ),
                        const Text('Brightness'),
                        Slider(
                          value: HSLColor.fromColor(selectedCustom).lightness,
                          min: 0.30,
                          max: 0.85,
                          onChanged: (value) => update(() {
                            selectedCustom = HSLColor.fromColor(selectedCustom)
                                .withLightness(value)
                                .toColor();
                            colorController.text = selectedCustom
                                .toARGB32()
                                .toRadixString(16)
                                .substring(2)
                                .toUpperCase();
                          }),
                        ),
                      ],
                      DropdownButtonFormField<String>(
                        initialValue: selectedStyle,
                        decoration: const InputDecoration(
                          labelText: 'Background',
                        ),
                        items:
                            [
                                  'Waves',
                                  'Ribbons',
                                  'Orbit',
                                  'Pulse',
                                  'Nebula',
                                  'Starfield',
                                  'Northern Lights',
                                  'Mesh',
                                  'Quiet',
                                ]
                                .map(
                                  (name) => DropdownMenuItem(
                                    value: name,
                                    child: Text(name),
                                  ),
                                )
                                .toList(),
                        onChanged: (value) => update(
                          () => selectedStyle = value ?? selectedStyle,
                        ),
                      ),
                      if (selectedStyle == 'Starfield' ||
                          selectedStyle == 'Northern Lights') ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: selectedStyle == 'Starfield'
                                    ? selectedStar
                                    : selectedAurora,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 10),
                            IconButton(
                              tooltip: 'Pick any color',
                              icon: const Icon(Icons.colorize),
                              onPressed: () async {
                                final isStar = selectedStyle == 'Starfield';
                                final chosen = await pickCustomColor(
                                  context,
                                  isStar ? selectedStar : selectedAurora,
                                );
                                if (chosen != null)
                                  update(() {
                                    if (isStar) {
                                      selectedStar = chosen;
                                      starColorController.text = chosen
                                          .toARGB32()
                                          .toRadixString(16)
                                          .substring(2)
                                          .toUpperCase();
                                    } else {
                                      selectedAurora = chosen;
                                      auroraColorController.text = chosen
                                          .toARGB32()
                                          .toRadixString(16)
                                          .substring(2)
                                          .toUpperCase();
                                    }
                                  });
                              },
                            ),
                            Expanded(
                              child: TextField(
                                controller: selectedStyle == 'Starfield'
                                    ? starColorController
                                    : auroraColorController,
                                decoration: InputDecoration(
                                  labelText: selectedStyle == 'Starfield'
                                      ? 'Star color (hex)'
                                      : 'Northern lights color (hex)',
                                  prefixText: '#',
                                ),
                                maxLength: 6,
                                onChanged: (value) {
                                  if (!RegExp(r'^[0-9a-fA-F]{6}$')
                                      .hasMatch(value))
                                    return;
                                  update(() {
                                    final chosen = Color(
                                      0xFF000000 | int.parse(value, radix: 16),
                                    );
                                    if (selectedStyle == 'Starfield') {
                                      selectedStar = chosen;
                                    } else {
                                      selectedAurora = chosen;
                                    }
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: HSLColor.fromColor(
                            selectedStyle == 'Starfield'
                                ? selectedStar
                                : selectedAurora,
                          ).hue,
                          min: 0,
                          max: 360,
                          label: 'Color hue',
                          onChanged: (value) => update(() {
                            if (selectedStyle == 'Starfield') {
                              selectedStar = HSLColor.fromColor(selectedStar)
                                  .withHue(value)
                                  .toColor();
                              starColorController.text = selectedStar
                                  .toARGB32()
                                  .toRadixString(16)
                                  .substring(2)
                                  .toUpperCase();
                            } else {
                              selectedAurora = HSLColor.fromColor(
                                selectedAurora,
                              ).withHue(value).toColor();
                              auroraColorController.text = selectedAurora
                                  .toARGB32()
                                  .toRadixString(16)
                                  .substring(2)
                                  .toUpperCase();
                            }
                          }),
                        ),
                      ],
                      if (selectedStyle == 'Starfield')
                        Row(
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: selectedStarBackground,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 10),
                            IconButton(
                              tooltip: 'Pick star background color',
                              icon: const Icon(Icons.colorize),
                              onPressed: () async {
                                final chosen = await pickCustomColor(
                                  context,
                                  selectedStarBackground,
                                );
                                if (chosen != null)
                                  update(() {
                                    selectedStarBackground = chosen;
                                    starBackgroundController.text = chosen
                                        .toARGB32()
                                        .toRadixString(16)
                                        .substring(2)
                                        .toUpperCase();
                                  });
                              },
                            ),
                            Expanded(
                              child: TextField(
                                controller: starBackgroundController,
                                maxLength: 6,
                                decoration: const InputDecoration(
                                  labelText: 'Star background (hex)',
                                  prefixText: '#',
                                ),
                                onChanged: (value) {
                                  if (RegExp(r'^[0-9a-fA-F]{6}$')
                                      .hasMatch(value)) {
                                    update(
                                      () => selectedStarBackground = Color(
                                        0xFF000000 |
                                            int.parse(value, radix: 16),
                                      ),
                                    );
                                  }
                                },
                              ),
                            ),
                          ],
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
                    ],
                  ),
                  ExpansionTile(
                    title: const Text('Voice'),
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: source,
                        decoration: const InputDecoration(
                          labelText: 'Voice source',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'Offline',
                            child: Text('Offline voices · private'),
                          ),
                          DropdownMenuItem(
                            value: 'Fish Audio',
                            child: Text('Fish Audio · online'),
                          ),
                        ],
                        onChanged: (value) =>
                            update(() => source = value ?? source),
                      ),
                      if (source == 'Offline')
                        DropdownButtonFormField<int>(
                          initialValue: voice,
                          decoration: const InputDecoration(
                            labelText: 'Offline voice',
                          ),
                          items: SpeechService.voices
                              .map(
                                (item) => DropdownMenuItem(
                                  value: item.id,
                                  child: Text('${item.name} · ${item.gender}'),
                                ),
                              )
                              .toList(),
                          onChanged: (value) =>
                              update(() => voice = value ?? voice),
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
                                if (previous != null)
                                  unawaited(previous.dispose());
                                unawaited(save());
                                Navigator.pop(context);
                                unawaited(downloadSpeechModels());
                              },
                        icon: const Icon(Icons.download),
                        label: const Text('Download 5 offline voices · 305 MB'),
                      ),
                      if (source == 'Fish Audio') ...[
                        const Text(
                          'Optional online voice: reply text is sent to Fish Audio for speech. Chat and transcription stay on this device.',
                        ),
                        TextButton.icon(
                          onPressed: () => launchUrl(
                            Uri.parse('https://fish.audio/app/api-keys/'),
                            mode: LaunchMode.externalApplication,
                          ),
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('Open Fish Audio API keys'),
                        ),
                        TextButton.icon(
                          onPressed: () => launchUrl(
                            Uri.parse('https://fish.audio/discovery/'),
                            mode: LaunchMode.externalApplication,
                          ),
                          icon: const Icon(Icons.record_voice_over),
                          label: const Text('Browse or create Fish voices'),
                        ),
                        TextField(
                          controller: fishIdController,
                          decoration: const InputDecoration(
                            labelText: 'Fish voice link or ID',
                            helperText:
                                'Paste a Fish voice page link or model ID',
                          ),
                        ),
                        TextField(
                          controller: fishKeyController,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: keySaved
                                ? 'Replace saved API key'
                                : 'Fish Audio API key',
                          ),
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Test this Fish voice'),
                          onPressed: () async {
                            if (dataDir == null || speech == null) return;
                            update(
                              () => fishTestStatus = 'Preparing voice sample…',
                            );
                            try {
                              if (fishKeyController.text.trim().isNotEmpty) {
                                await FishVoice.saveKey(fishKeyController.text);
                                update(() => keySaved = true);
                              }
                              final path =
                                  '${dataDir!.path}${Platform.pathSeparator}fish_voice_test.mp3';
                              await FishVoice.synthesize(
                                FishVoice.performanceText(
                                  'This is how I sound in this conversation.',
                                  chat.personality,
                                ),
                                fishIdController.text,
                                path,
                              );
                              update(
                                () => fishTestStatus = 'Playing voice sample…',
                              );
                              await speech!.playFile(path);
                              update(
                                () => fishTestStatus =
                                    'Voice played successfully.',
                              );
                            } catch (error) {
                              update(
                                () => fishTestStatus =
                                    'Voice test failed: $error',
                              );
                            }
                          },
                        ),
                        if (fishTestStatus.isNotEmpty) Text(fishTestStatus),
                        if (keySaved)
                          TextButton(
                            onPressed: () async {
                              await FishVoice.saveKey('');
                              update(() => keySaved = false);
                              fishHasKey = false;
                            },
                            child: const Text('Remove saved key'),
                          ),
                      ],
                      SwitchListTile(
                        title: const Text('Speak voice replies'),
                        value: spokenReplies,
                        onChanged: (value) =>
                            update(() => spokenReplies = value),
                      ),
                    ],
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
              onPressed: () async {
                if (fishKeyController.text.trim().isNotEmpty) {
                  try {
                    await FishVoice.saveKey(fishKeyController.text);
                    fishHasKey = true;
                  } catch (error) {
                    if (mounted)
                      showProblem(
                        'Could not save Fish Audio key securely: $error',
                      );
                    return;
                  }
                }
                instructions = promptController.text;
                frameCount = count;
                maxTokens = limit;
                setState(() {
                  themeName = selectedTheme;
                  customColor = selectedCustom;
                  starColor = selectedStar;
                  starBackgroundColor = selectedStarBackground;
                  auroraColor = selectedAurora;
                  backgroundStyle = selectedStyle;
                  motion = animated;
                  motionSpeed = speed;
                  speechRoot = speechController.text.trim();
                  autoSpeak = spokenReplies;
                  selectedVoice = voice;
                  voiceSource = source;
                  fishVoiceId = FishVoice.voiceIdFromInput(
                    fishIdController.text,
                  );
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
    colorController.dispose();
    starColorController.dispose();
    starBackgroundController.dispose();
    auroraColorController.dispose();
    fishIdController.dispose();
    fishKeyController.dispose();
  }

  Widget videoPreview(
    String playbackPath,
    String? posterPath, {
    double width = 230,
    double height = 170,
    bool compact = false,
  }) => InkWell(
    onTap: () => showLocalVideo(context, playbackPath),
    borderRadius: BorderRadius.circular(13),
    child: Container(
      width: width,
      height: height,
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (posterPath != null)
            Image.file(File(posterPath), fit: BoxFit.cover),
          Center(
            child: CircleAvatar(
              radius: compact ? 19 : 27,
              backgroundColor: Colors.black54,
              child: const Icon(
                Icons.play_arrow,
                color: Colors.white,
                size: 28,
              ),
            ),
          ),
          Positioned(
            bottom: 8,
            left: 10,
            child: Text(
              compact ? 'Video' : 'Video · tap to play',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                shadows: [Shadow(blurRadius: 5, color: Colors.black)],
              ),
            ),
          ),
        ],
      ),
    ),
  );

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
        highlight: entry.role == 'user',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  entry.role == 'user'
                      ? Icons.person_outline
                      : Icons.auto_awesome,
                  size: 14,
                  color: GlassPalette.resolve(themeName, customColor).accent,
                ),
                const SizedBox(width: 6),
                Text(
                  entry.role == 'user' ? 'You' : 'Local AI',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(width: 12),
                PopupMenuButton<String>(
                  tooltip: 'Message actions',
                  icon: const Icon(Icons.more_horiz, size: 18),
                  padding: EdgeInsets.zero,
                  onSelected: (value) {
                    if (value == 'delete') unawaited(deleteMessage(entry));
                    if (value == 'copy')
                      Clipboard.setData(ClipboardData(text: entry.text));
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'copy', child: Text('Copy text')),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete message'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 7),
            if (entry.videoPath != null)
              videoPreview(
                entry.playbackPath ?? entry.videoPath!,
                entry.frames
                    .where((frame) => frame.timeMs != null)
                    .firstOrNull
                    ?.path,
              ),
            for (final frame in entry.frames.where(
              (frame) => entry.videoPath == null || frame.timeMs == null,
            )) ...[
              if (frame.timeMs != null)
                Text(
                  'Frame at ' +
                      (frame.timeMs! / 1000).toStringAsFixed(1) +
                      ' s',
                ),
              InkWell(
                onTap: () => showLocalImage(context, frame.path),
                child: Image.file(
                  File(frame.path),
                  width: 230,
                  height: 160,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stack) =>
                      const Text('Media unavailable'),
                ),
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
    final palette = GlassPalette.resolve(themeName, customColor);
    final light = palette.text.computeLuminance() < 0.5;
    return GlassDesign(
      themeName: themeName,
      customColor: customColor,
      starColor: starColor,
      starBackgroundColor: starBackgroundColor,
      auroraColor: auroraColor,
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
                    tooltip: 'Conversation personality and memory',
                    onPressed: chats.isEmpty ? null : showChatOptions,
                    icon: const Icon(Icons.tune),
                  ),
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
                                  subtitle: item.personality == 'Default'
                                      ? null
                                      : Text(item.personality),
                                  selected: item.id == chatId,
                                  trailing: PopupMenuButton<String>(
                                    tooltip: 'Conversation actions',
                                    onSelected: (value) {
                                      if (value == 'delete')
                                        unawaited(deleteConversation(item));
                                    },
                                    itemBuilder: (context) => const [
                                      PopupMenuItem(
                                        value: 'delete',
                                        child: Text('Delete conversation'),
                                      ),
                                    ],
                                  ),
                                  onTap: busy || callActive
                                      ? null
                                      : () {
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
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
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
                      height: 86,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          if (currentVideoPath != null)
                            Stack(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: videoPreview(
                                    currentVideoPlaybackPath ??
                                        currentVideoPath!,
                                    attachments
                                        .where((frame) => frame.timeMs != null)
                                        .firstOrNull
                                        ?.path,
                                    width: 100,
                                    height: 76,
                                    compact: true,
                                  ),
                                ),
                                Positioned(
                                  right: 0,
                                  child: IconButton.filledTonal(
                                    tooltip: 'Remove video',
                                    iconSize: 14,
                                    onPressed: () =>
                                        unawaited(removeDraftVideo()),
                                    icon: const Icon(Icons.close),
                                  ),
                                ),
                              ],
                            ),
                          for (final frame in attachments.where(
                            (frame) => frame.timeMs == null,
                          ))
                            Stack(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: InkWell(
                                    onTap: () =>
                                        showLocalImage(context, frame.path),
                                    child: Image.file(
                                      File(frame.path),
                                      width: 100,
                                      height: 76,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                                Positioned(
                                  right: 0,
                                  child: IconButton.filledTonal(
                                    iconSize: 14,
                                    onPressed: () {
                                      setState(() => attachments.remove(frame));
                                      unawaited(save());
                                    },
                                    icon: const Icon(Icons.close),
                                  ),
                                ),
                              ],
                            ),
                        ],
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
                              tooltip: 'Call the AI',
                              onPressed: callActive || busy
                                  ? null
                                  : showVoiceCall,
                              icon: const Icon(Icons.call_outlined),
                            ),
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
                              onPressed: busy ? stopGeneration : () => send(),
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
