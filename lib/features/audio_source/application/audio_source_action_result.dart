/// 音源写操作结果。
class AudioSourceActionResult {
  const AudioSourceActionResult._({
    required this.isSuccess,
    this.errorMessage,
  });

  final bool isSuccess;
  final String? errorMessage;

  factory AudioSourceActionResult.success() {
    return const AudioSourceActionResult._(isSuccess: true);
  }

  factory AudioSourceActionResult.failure(String message) {
    return AudioSourceActionResult._(
      isSuccess: false,
      errorMessage: message,
    );
  }
}

