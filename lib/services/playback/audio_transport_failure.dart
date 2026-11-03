/// Evidence from the audio transport, independent of the native player's text.
enum AudioTransportStage { upstream, connect, read, local }

class AudioTransportFailure implements Exception {
  final AudioTransportStage stage;
  final int? statusCode;
  final bool timedOut;

  const AudioTransportFailure(
    this.stage, {
    this.statusCode,
    this.timedOut = false,
  });

  @override
  String toString() =>
      'AudioTransportFailure(stage: ${stage.name}, status: $statusCode, timeout: $timedOut)';
}
