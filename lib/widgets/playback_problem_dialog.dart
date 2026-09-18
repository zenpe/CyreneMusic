import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../services/playback/playback_problem.dart';
import '../utils/theme_manager.dart';

Future<PlaybackRecoveryAction?> showPlaybackProblemDialog(
  BuildContext context,
  PlaybackProblem problem,
) {
  final themeManager = ThemeManager();
  final title = _titleFor(problem.kind);
  final message = '${problem.message}\n《${problem.track.name}》';
  final actions = problem.orderedRecoveryActions;

  if (themeManager.isDesktopFluentUI) {
    return fluent.showDialog<PlaybackRecoveryAction>(
      context: context,
      builder: (dialogContext) => fluent.ContentDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          fluent.Button(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('关闭'),
          ),
          ...actions.map(
            (action) => fluent.FilledButton(
              onPressed: () => Navigator.pop(dialogContext, action),
              child: Text(_labelFor(action)),
            ),
          ),
        ],
      ),
    );
  }

  final isCupertino =
      (Platform.isIOS || Platform.isAndroid) &&
      themeManager.isCupertinoFramework;
  if (isCupertino) {
    return showCupertinoDialog<PlaybackRecoveryAction>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('关闭'),
          ),
          ...actions.map(
            (action) => CupertinoDialogAction(
              isDefaultAction: action == PlaybackRecoveryAction.retry,
              onPressed: () => Navigator.pop(dialogContext, action),
              child: Text(_labelFor(action)),
            ),
          ),
        ],
      ),
    );
  }

  return showDialog<PlaybackRecoveryAction>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('关闭'),
        ),
        ...actions.map(
          (action) => action == PlaybackRecoveryAction.retry
              ? FilledButton.icon(
                  onPressed: () => Navigator.pop(dialogContext, action),
                  icon: const Icon(Icons.refresh),
                  label: Text(_labelFor(action)),
                )
              : TextButton(
                  onPressed: () => Navigator.pop(dialogContext, action),
                  child: Text(_labelFor(action)),
                ),
        ),
      ],
    ),
  );
}

String _titleFor(PlaybackProblemKind kind) {
  switch (kind) {
    case PlaybackProblemKind.sourceNotConfigured:
      return '需要配置音源';
    case PlaybackProblemKind.sourceInvalid:
      return '音源不可用';
    case PlaybackProblemKind.networkTimeout:
      return '连接超时';
    case PlaybackProblemKind.localFileMissing:
      return '文件不存在';
    case PlaybackProblemKind.unsupportedFormat:
      return '格式不支持';
    case PlaybackProblemKind.accessDenied:
    case PlaybackProblemKind.resourceUnavailable:
    case PlaybackProblemKind.engineFailure:
    case PlaybackProblemKind.unknown:
      return '播放失败';
  }
}

String _labelFor(PlaybackRecoveryAction action) {
  switch (action) {
    case PlaybackRecoveryAction.retry:
      return '重试';
    case PlaybackRecoveryAction.switchSource:
      return '切换音源';
    case PlaybackRecoveryAction.reimportSource:
      return '重新导入';
    case PlaybackRecoveryAction.openSourceSettings:
      return '音源设置';
  }
}
