/// 将字节数格式化为人类可读的文件大小字符串。
String formatFileSize(
  int bytes, {
  int fractionDigits = 2,
  bool trimTrailingZeros = false,
}) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${_formatFileSizeValue(bytes / 1024, fractionDigits, trimTrailingZeros)} KB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return '${_formatFileSizeValue(bytes / (1024 * 1024), fractionDigits, trimTrailingZeros)} MB';
  }
  return '${_formatFileSizeValue(bytes / (1024 * 1024 * 1024), fractionDigits, trimTrailingZeros)} GB';
}

String _formatFileSizeValue(
  num value,
  int fractionDigits,
  bool trimTrailingZeros,
) {
  final formatted = value.toStringAsFixed(fractionDigits);
  if (!trimTrailingZeros) {
    return formatted;
  }
  return formatted
      .replaceFirst(RegExp(r'([.]\d*?[1-9])0+$'), r'$1')
      .replaceFirst(RegExp(r'\.0+$'), '');
}
