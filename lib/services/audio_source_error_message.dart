/// Keep script stacks, response documents and obfuscated code out of UI labels.
String audioSourceErrorMessage(Object error) {
  var message = error.toString().trim();
  final prefix = RegExp(
    r'^(?:Exception|TimeoutException|FormatException|StateError|Bad state|Error):\s*',
  );
  while (prefix.hasMatch(message)) {
    message = message.replaceFirst(prefix, '').trim();
  }
  if (message.contains('InternalError: out of memory')) {
    return '音源脚本占用内存过多，已中止，请更换音源';
  }
  if (message.contains('SyntaxError') ||
      message.contains('Unexpected token') ||
      message.contains('JSON at position')) {
    return '音源脚本或接口返回内容格式异常，请重试或更换音源';
  }
  if (RegExp(
        r'<(?:!doctype|html|body)\b',
        caseSensitive: false,
      ).hasMatch(message) ||
      message.contains('\uFFFD') ||
      RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]').hasMatch(message)) {
    return '音源返回内容异常，请重试或更换音源';
  }
  message = message.split(RegExp(r'[\r\n]')).first.trim();
  if (message.length > 200) {
    return '音源加载失败，请重试或更换音源；可在开发者日志中查看原因';
  }
  return message;
}
