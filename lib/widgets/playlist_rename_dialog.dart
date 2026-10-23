import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

enum PlaylistRenameStyle { material, cupertino, fluent }

class PlaylistRenameDialog extends StatefulWidget {
  const PlaylistRenameDialog({
    super.key,
    required this.name,
    required this.onSave,
    this.style = PlaylistRenameStyle.material,
  });

  final String name;
  final Future<bool> Function(String name) onSave;
  final PlaylistRenameStyle style;

  static Future<bool?> show(
    BuildContext context, {
    required String name,
    required Future<bool> Function(String name) onSave,
    required PlaylistRenameStyle style,
  }) {
    Widget builder(BuildContext context) =>
        PlaylistRenameDialog(name: name, onSave: onSave, style: style);
    return switch (style) {
      PlaylistRenameStyle.fluent => fluent.showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: builder,
      ),
      PlaylistRenameStyle.cupertino => showCupertinoDialog<bool>(
        context: context,
        builder: builder,
      ),
      PlaylistRenameStyle.material => showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: builder,
      ),
    };
  }

  @override
  State<PlaylistRenameDialog> createState() => _PlaylistRenameDialogState();
}

class _PlaylistRenameDialogState extends State<PlaylistRenameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.name,
  );
  bool _saving = false;
  bool _closing = false;
  String? _error;

  bool get _canSave =>
      !_saving &&
      !_closing &&
      _controller.text.trim().isNotEmpty &&
      _controller.text.trim() != widget.name;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _changed(String _) => setState(() => _error = null);

  Future<void> _save() async {
    if (!_canSave) return;
    final name = _controller.text.trim();
    setState(() {
      _saving = true;
      _error = null;
    });
    var succeeded = false;
    try {
      succeeded = await widget.onSave(name);
    } catch (_) {
      // Retain the input so the user can retry without typing again.
    }
    if (!mounted) return;
    if (succeeded) {
      // Let PopScope permit the successful programmatic close.
      setState(() {
        _saving = false;
        _closing = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop(true);
      });
    } else {
      setState(() {
        _saving = false;
        _error = '保存失败，请稍后重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _saving || _closing;
    final cancel = busy ? null : () => Navigator.of(context).pop(false);
    final save = _canSave ? _save : null;
    final field = switch (widget.style) {
      PlaylistRenameStyle.fluent => fluent.TextBox(
        controller: _controller,
        enabled: !busy,
        autofocus: true,
        placeholder: '歌单名称',
        onChanged: _changed,
        onSubmitted: (_) => _save(),
      ),
      PlaylistRenameStyle.cupertino => CupertinoTextField(
        controller: _controller,
        enabled: !busy,
        autofocus: true,
        placeholder: '歌单名称',
        onChanged: _changed,
        onSubmitted: (_) => _save(),
      ),
      PlaylistRenameStyle.material => TextField(
        controller: _controller,
        enabled: !busy,
        autofocus: true,
        decoration: const InputDecoration(labelText: '歌单名称'),
        onChanged: _changed,
        onSubmitted: (_) => _save(),
      ),
    };
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        field,
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _error!,
              style: const TextStyle(color: CupertinoColors.systemRed),
            ),
          ),
      ],
    );
    final label = Text(busy ? '保存中…' : '保存');
    final dialog = switch (widget.style) {
      PlaylistRenameStyle.fluent => fluent.ContentDialog(
        title: const Text('重命名歌单'),
        content: content,
        actions: [
          fluent.Button(onPressed: cancel, child: const Text('取消')),
          fluent.FilledButton(onPressed: save, child: label),
        ],
      ),
      PlaylistRenameStyle.cupertino => CupertinoAlertDialog(
        title: const Text('重命名歌单'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: content,
        ),
        actions: [
          CupertinoDialogAction(onPressed: cancel, child: const Text('取消')),
          CupertinoDialogAction(onPressed: save, child: label),
        ],
      ),
      PlaylistRenameStyle.material => AlertDialog(
        title: const Text('重命名歌单'),
        content: content,
        actions: [
          TextButton(onPressed: cancel, child: const Text('取消')),
          FilledButton(onPressed: save, child: label),
        ],
      ),
    };
    return PopScope(canPop: !_saving, child: dialog);
  }
}
