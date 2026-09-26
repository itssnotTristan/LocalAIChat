import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

Future<void> showLocalImage(BuildContext context, String path) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => _ImageViewer(path: path)));

Future<void> showLocalVideo(BuildContext context, String path) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => _VideoViewer(path: path)));

class _ImageViewer extends StatelessWidget {
  const _ImageViewer({required this.path});
  final String path;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: const Text('Photo'),
      leading: IconButton(
        tooltip: 'Close photo',
        icon: const Icon(Icons.close),
        onPressed: () => Navigator.pop(context),
      ),
    ),
    body: InteractiveViewer(
      minScale: 0.5,
      maxScale: 5,
      child: Center(
        child: Image.file(
          File(path),
          fit: BoxFit.contain,
          errorBuilder: (context, error, stack) => const Text(
            'Photo unavailable',
            style: TextStyle(color: Colors.white),
          ),
        ),
      ),
    ),
  );
}

class _VideoViewer extends StatefulWidget {
  const _VideoViewer({required this.path});
  final String path;

  @override
  State<_VideoViewer> createState() => _VideoViewerState();
}

class _VideoViewerState extends State<_VideoViewer> {
  late final VideoPlayerController controller;
  String? error;

  @override
  void initState() {
    super.initState();
    controller = VideoPlayerController.file(File(widget.path));
    controller.addListener(_refresh);
    _open();
  }

  Future<void> _open() async {
    try {
      await controller.initialize();
      if (!mounted) return;
      await controller.play();
      if (mounted) setState(() {});
    } catch (exception) {
      if (mounted)
        setState(() => error = 'Could not play this video: $exception');
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    controller.removeListener(_refresh);
    controller.dispose();
    super.dispose();
  }

  String _time(Duration value) {
    final minutes = value.inMinutes.toString().padLeft(2, '0');
    final seconds = (value.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final value = controller.value;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Video'),
        leading: IconButton(
          tooltip: 'Close video',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: error != null
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          error!,
                          style: const TextStyle(color: Colors.white),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : !value.isInitialized
                    ? const CircularProgressIndicator()
                    : AspectRatio(
                        aspectRatio: value.aspectRatio > 0
                            ? value.aspectRatio
                            : 16 / 9,
                        child: VideoPlayer(controller),
                      ),
              ),
            ),
            if (value.isInitialized)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
                child: Row(
                  children: [
                    IconButton.filledTonal(
                      tooltip: value.isPlaying ? 'Pause' : 'Play',
                      onPressed: () => value.isPlaying
                          ? controller.pause()
                          : controller.play(),
                      icon: Icon(
                        value.isPlaying ? Icons.pause : Icons.play_arrow,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Text(
                      _time(value.position),
                      style: const TextStyle(color: Colors.white),
                    ),
                    Expanded(
                      child: VideoProgressIndicator(
                        controller,
                        allowScrubbing: true,
                        colors: const VideoProgressColors(
                          playedColor: Color(0xFF75D5ED),
                          bufferedColor: Colors.white38,
                          backgroundColor: Colors.white24,
                        ),
                      ),
                    ),
                    Text(
                      _time(value.duration),
                      style: const TextStyle(color: Colors.white),
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
