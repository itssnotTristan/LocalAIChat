import 'dart:io';

import 'package:local_ai_chat/gguf_info.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run tools/inspect_gguf.dart MODEL.gguf');
    exitCode = 2;
    return;
  }
  final info = await GgufInfo.read(args.first);
  stdout.writeln('name: ${info.name}');
  stdout.writeln('architecture: ${info.architecture}');
  stdout.writeln('quantization: ${info.quantization}');
  stdout.writeln('context: ${info.contextLength ?? 'unknown'}');
  stdout.writeln('bytes: ${info.sizeBytes}');
}
