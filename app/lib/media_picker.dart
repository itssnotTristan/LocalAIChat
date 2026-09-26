import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// On iOS, Photos uses PHPicker and only exposes the chosen item. Files uses
/// the system document picker. Neither requires a blanket library permission.
Future<String?> pickLocalMedia(
  BuildContext context, {
  required bool video,
}) async {
  if (!Platform.isIOS) {
    final picked = await FilePicker.platform.pickFiles(
      type: video ? FileType.video : FileType.image,
    );
    return picked?.files.single.path;
  }
  final source = await showModalBottomSheet<String>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(
              video ? 'Choose video from Photos' : 'Choose photo from Photos',
            ),
            subtitle: const Text(
              'Only the item you select is shared with FluxLira',
            ),
            onTap: () => Navigator.pop(sheetContext, 'photos'),
          ),
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text('Browse Files'),
            onTap: () => Navigator.pop(sheetContext, 'files'),
          ),
        ],
      ),
    ),
  );
  if (source == 'photos') {
    return const MethodChannel('local_ai_chat/photo_picker')
        .invokeMethod<String>('pick', {'type': video ? 'video' : 'image'});
  }
  if (source == 'files') {
    final picked = await FilePicker.platform.pickFiles(
      type: video ? FileType.video : FileType.image,
    );
    return picked?.files.single.path;
  }
  return null;
}
