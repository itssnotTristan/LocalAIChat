import 'dart:async';
import 'dart:isolate';

import 'package:lib_llama_cpp_platform_interface/lib_llama_cpp_platform_interface.dart';

import 'llama_command.dart';
import 'llama_response.dart';
import 'llama_state.dart';
import 'native_runtime.dart';

final class InferenceIsolate {
  InferenceIsolate._({
    required Isolate isolate,
    required SendPort commandPort,
    required StreamSubscription<Object?> subscription,
  }) : _isolate = isolate,
       _commandPort = commandPort,
       _subscription = subscription;

  final Isolate _isolate;
  final SendPort _commandPort;
  final StreamSubscription<Object?> _subscription;
  final Map<int, StreamController<LlamaResponse>> _pending = {};
  var _nextRequestId = 0;
  var _isClosed = false;
  final Completer<void> _shutdownAcknowledged = Completer<void>();

  static Future<InferenceIsolate> spawn({
    required LlamaCppLibraryDescriptor library,
    required LlamaState initialState,
  }) async {
    final ready = Completer<SendPort>();
    final receivePort = ReceivePort();
    late final StreamSubscription<Object?> subscription;
    late final InferenceIsolate actor;

    subscription = receivePort.listen((message) {
      if (message is _ShutdownAcknowledged) {
        if (!actor._shutdownAcknowledged.isCompleted) {
          actor._shutdownAcknowledged.complete();
        }
        return;
      }
      if (message is SendPort) {
        ready.complete(message);
        return;
      }

      if (message is _ResponseEnvelope) {
        final controller = actor._pending[message.requestId];
        if (controller == null) {
          return;
        }
        if (message.response != null) {
          controller.add(message.response!);
        }
        if (message.isDone) {
          actor._pending.remove(message.requestId);
          unawaited(controller.close());
        }
      }
    });

    final isolate = await Isolate.spawn(
      _runInferenceWorker,
      _StartMessage(
        replyPort: receivePort.sendPort,
        library: library,
        initialState: initialState,
      ),
      debugName: 'lib_llama_cpp_inference',
    );

    final commandPort = await ready.future;
    actor = InferenceIsolate._(
      isolate: isolate,
      commandPort: commandPort,
      subscription: subscription,
    );
    return actor;
  }

  Stream<LlamaResponse> dispatch(LlamaCommand command) {
    if (_isClosed) {
      return Stream<LlamaResponse>.value(
        const LlamaErrorResponse(message: 'Inference isolate is closed.'),
      );
    }

    final requestId = _nextRequestId++;
    final controller = StreamController<LlamaResponse>();
    _pending[requestId] = controller;
    _commandPort.send(_CommandEnvelope(requestId: requestId, command: command));
    return controller.stream;
  }

  Future<void> close() async {
    if (_isClosed) {
      return;
    }
    _isClosed = true;
    _commandPort.send(const _ShutdownMessage());
    for (final controller in _pending.values) {
      unawaited(controller.close());
    }
    _pending.clear();
    try {
      await _shutdownAcknowledged.future.timeout(const Duration(seconds: 8));
    } on TimeoutException {
      // A native generation can be stuck; keep the UI responsive in that case.
    } finally {
      await _subscription.cancel();
      _isolate.kill(priority: Isolate.immediate);
    }
  }

  /// Stop native generation immediately, including while it is between Dart
  /// tokens. The current model session is discarded after an interruption.
  void abort() {
    if (_isClosed) return;
    _isClosed = true;
    for (final controller in _pending.values) {
      unawaited(controller.close());
    }
    _pending.clear();
    _isolate.kill(priority: Isolate.immediate);
    unawaited(_subscription.cancel());
  }
}

final class _StartMessage {
  const _StartMessage({
    required this.replyPort,
    required this.library,
    required this.initialState,
  });

  final SendPort replyPort;
  final LlamaCppLibraryDescriptor library;
  final LlamaState initialState;
}

final class _CommandEnvelope {
  const _CommandEnvelope({required this.requestId, required this.command});

  final int requestId;
  final LlamaCommand command;
}

final class _ResponseEnvelope {
  const _ResponseEnvelope({
    required this.requestId,
    this.response,
    this.isDone = false,
  });

  final int requestId;
  final LlamaResponse? response;
  final bool isDone;
}

final class _ShutdownMessage {
  const _ShutdownMessage();
}

final class _ShutdownAcknowledged {
  const _ShutdownAcknowledged();
}

void _runInferenceWorker(_StartMessage start) {
  var state = start.initialState;
  NativeLlamaRuntime? runtime;
  String? startupError;
  try {
    runtime = NativeLlamaRuntime(library: start.library);
  } on NativeLlamaException catch (error) {
    startupError = error.message;
  } on Object catch (error) {
    startupError = 'Failed to initialize llama.cpp runtime: $error';
  }

  final receivePort = ReceivePort();
  start.replyPort.send(receivePort.sendPort);

  void send(int requestId, LlamaResponse response) {
    start.replyPort.send(
      _ResponseEnvelope(requestId: requestId, response: response),
    );
  }

  void done(int requestId) {
    start.replyPort.send(_ResponseEnvelope(requestId: requestId, isDone: true));
  }

  receivePort.listen((message) {
    if (message is _ShutdownMessage) {
      runtime?.close();
      start.replyPort.send(const _ShutdownAcknowledged());
      receivePort.close();
      return;
    }

    if (message is! _CommandEnvelope) {
      return;
    }

    final command = message.command;
    switch (command) {
      case LlamaLoadModelCommand():
        if (startupError != null || runtime == null) {
          send(message.requestId, LlamaErrorResponse(message: startupError!));
        } else {
          try {
            state = runtime.loadModel(command);
            send(message.requestId, LlamaStateChangedResponse(state: state));
          } on NativeLlamaException catch (error) {
            send(message.requestId, LlamaErrorResponse(message: error.message));
          } on Object catch (error) {
            send(
              message.requestId,
              LlamaErrorResponse(message: 'Failed to load model: $error'),
            );
          }
        }
      case LlamaGenerateCommand():
        if (!state.isModelLoaded || runtime == null) {
          send(
            message.requestId,
            const LlamaErrorResponse(
              message: 'Cannot generate before a model is loaded.',
            ),
          );
        } else {
          try {
            for (final response in runtime.generate(command)) {
              send(message.requestId, response);
            }
          } on NativeLlamaException catch (error) {
            send(message.requestId, LlamaErrorResponse(message: error.message));
          } on Object catch (error, trace) {
            send(
              message.requestId,
              LlamaErrorResponse(
                message:
                    'Generation failed: $error\n${trace.toString().split('\n').take(6).join('\n')}',
              ),
            );
          }
        }
      case LlamaGenerateMessagesCommand():
        if (!state.isModelLoaded || runtime == null) {
          send(
            message.requestId,
            const LlamaErrorResponse(
              message: 'Cannot generate before a model is loaded.',
            ),
          );
        } else {
          try {
            for (final response in runtime.generateMessages(command)) {
              send(message.requestId, response);
            }
          } on NativeLlamaException catch (error) {
            send(message.requestId, LlamaErrorResponse(message: error.message));
          } on Object catch (error, trace) {
            send(
              message.requestId,
              LlamaErrorResponse(
                message:
                    'Generation failed: $error\n${trace.toString().split('\n').take(6).join('\n')}',
              ),
            );
          }
        }
      case LlamaDisposeCommand():
        runtime?.disposeModel();
        state = const LlamaState.empty();
        send(message.requestId, LlamaStateChangedResponse(state: state));
        send(message.requestId, const LlamaDoneResponse());
    }

    done(message.requestId);
  });
}

void unawaited(Future<void> future) {}
