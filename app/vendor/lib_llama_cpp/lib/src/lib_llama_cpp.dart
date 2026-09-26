import 'dart:async';

import 'package:lib_llama_cpp_platform_interface/lib_llama_cpp_platform_interface.dart';

import 'inference_isolate.dart';
import 'llama_command.dart';
import 'llama_response.dart';
import 'llama_state.dart';

abstract interface class LlamaEngine {
  Stream<LlamaResponse> transform(
    Stream<LlamaCommand> commands, {
    LlamaState initialState = const LlamaState.empty(),
    LlamaCppLibraryRequest libraryRequest = const LlamaCppLibraryRequest(),
  });
}

/// Lets the UI interrupt a model load or decode even before the next token is
/// emitted. Each request should get its own controller.
final class LlamaCancellationController {
  final Completer<void> _cancelled = Completer<void>();
  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;
  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}

final class LibLlamaCpp implements LlamaEngine {
  const LibLlamaCpp({LibLlamaCppPlatform? platform, this.cancellation})
    : _platform = platform;

  final LibLlamaCppPlatform? _platform;
  final LlamaCancellationController? cancellation;

  @override
  Stream<LlamaResponse> transform(
    Stream<LlamaCommand> commands, {
    LlamaState initialState = const LlamaState.empty(),
    LlamaCppLibraryRequest libraryRequest = const LlamaCppLibraryRequest(),
  }) async* {
    final platform = _platform ?? LibLlamaCppPlatform.instance;
    late final LlamaCppLibraryDescriptor library;
    try {
      library = await platform.resolveLibrary(request: libraryRequest);
    } on Object catch (error) {
      yield LlamaErrorResponse(
        message: 'Failed to resolve llama.cpp library: $error',
      );
      return;
    }

    late final InferenceIsolate actor;
    try {
      actor = await InferenceIsolate.spawn(
        library: library,
        initialState: initialState,
      );
    } on Object catch (error) {
      yield LlamaErrorResponse(
        message: 'Failed to start llama.cpp inference isolate: $error',
      );
      return;
    }

    // The worker can be busy in native image processing or model loading.
    // Closing only the Dart stream would leave that work running.
    if (cancellation != null) {
      unawaited(cancellation!.whenCancelled.then((_) => actor.abort()));
      if (cancellation!.isCancelled) actor.abort();
    }

    yield LlamaReadyResponse(library: library);

    try {
      await for (final command in commands) {
        if (cancellation?.isCancelled ?? false) break;
        yield* actor.dispatch(command);
        if ((cancellation?.isCancelled ?? false) ||
            command is LlamaDisposeCommand) {
          break;
        }
      }
    } finally {
      await actor.close();
    }
  }
}
