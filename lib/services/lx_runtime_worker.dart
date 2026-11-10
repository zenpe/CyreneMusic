import 'dart:async';
import 'dart:isolate';

import 'lx_http_bridge.dart';
import 'lx_runtime_interface.dart';
import 'lx_script_engine.dart';
import 'resolution_request.dart';
import 'structured_log_service.dart';

/// Owns every FFI handle. Only Dart data crosses the port.
void runLxRuntimeWorker((SendPort, String, Duration, Duration) bootstrap) {
  final (output, fetchPolyfill, initializationTurn, executionTurn) = bootstrap;
  final input = ReceivePort();
  final engine = LxScriptEngine(
    fetchPolyfill: fetchPolyfill,
    initializationTurn: initializationTurn,
    executionTurn: executionTurn,
  );
  StructuredLogService.sink = (line) => output.send(LxWorkerLog(line));
  final owners = <int, ResolutionRequest>{};
  Future<void> pending = Future.value();
  var closing = false;
  input.listen((dynamic message) {
    if (message is LxWorkerCancel) {
      final owner = owners[message.id];
      owner?.failure = message.failure;
      owner?.cancel();
      return;
    }
    if (message is LxWorkerStop) {
      if (closing) return;
      closing = true;
      for (final owner in owners.values) {
        owner.cancel();
      }
      unawaited(
        pending.whenComplete(() async {
          await engine.dispose();
          LxHttpBridge.close();
          input.close();
          Isolate.exit();
        }),
      );
      return;
    }
    if (message is! LxWorkerCommand || closing) return;
    final command = message;
    // Cancellation bypasses this queue so HTTP waits remain interruptible.
    final owner = ResolutionRequest();
    owners[command.id] = owner;
    pending = pending.then((_) async {
      Object? value;
      Object? error;
      var cancelled = false;
      try {
        owner.check();
        switch (command.operation) {
          case LxWorkerOperation.initialize:
            await engine.initialize();
          case LxWorkerOperation.load:
            value = await owner.run(() => engine.loadScript(command.script!));
          case LxWorkerOperation.resolve:
            value = await owner.run(
              () => engine.getMusicUrl(
                source: command.source!,
                songId: command.songId,
                quality: command.quality!,
                musicInfo: command.musicInfo,
                timeout: command.deadline!.difference(DateTime.now()),
              ),
            );
        }
      } on ResolutionCancelled {
        cancelled = true;
      } catch (caught) {
        error = caught.toString();
      } finally {
        owners.remove(command.id);
        // An interrupted context is reconstructed before the next resolution;
        // the configured source remains selected and validated.
        output.send(
          LxWorkerResult(
            command.id,
            value,
            error,
            cancelled,
            engine.isInitialized,
            command.operation == LxWorkerOperation.resolve
                ? null
                : engine.currentScript,
            owner.failure ?? engine.lastFailure,
            owner.lastHttpResponse,
            hasConfiguredScript: engine.hasConfiguredScript,
          ),
        );
      }
    });
  });
  output.send(input.sendPort);
}

enum LxWorkerOperation { initialize, load, resolve }

class LxWorkerCommand {
  const LxWorkerCommand(
    this.id,
    this.operation, {
    this.script,
    this.source,
    this.songId,
    this.quality,
    this.musicInfo,
    this.deadline,
  });
  final int id;
  final LxWorkerOperation operation;
  final String? script, source, quality;
  final Object? songId;
  final Map<String, dynamic>? musicInfo;
  final DateTime? deadline;
}

class LxWorkerCancel {
  const LxWorkerCancel(this.id, this.failure);
  final int id;
  final LxRuntimeFailure? failure;
}

class LxWorkerStop {
  const LxWorkerStop();
}

class LxWorkerLog {
  const LxWorkerLog(this.line);
  final String line;
}

class LxWorkerResult {
  const LxWorkerResult(
    this.id,
    this.value,
    this.error,
    this.cancelled,
    this.initialized,
    this.script,
    this.failure,
    this.httpResponse, {
    required this.hasConfiguredScript,
  });
  final int id;
  final Object? value, error;
  final bool cancelled, initialized;
  final bool hasConfiguredScript;
  final LxScriptInfo? script;
  final LxRuntimeFailure? failure;
  final ({int status, String bodyType, int? businessCode})? httpResponse;
}
