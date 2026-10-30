import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import '../services/url_service.dart';

enum ServerEditorStyle { material, fluent, cupertino }

/// The same validation contract in every theme, including pre-login settings.
class ServerAddressEditor extends StatefulWidget {
  const ServerAddressEditor({super.key, required this.style});
  final ServerEditorStyle style;
  @override
  State<ServerAddressEditor> createState() => _ServerAddressEditorState();
}

class _ServerAddressEditorState extends State<ServerAddressEditor> {
  final controller = TextEditingController(text: UrlService().customBaseUrl);
  String? error;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void save() {
    final url = controller.text.trim();
    if (url.isEmpty || !UrlService.isValidUrl(url)) {
      setState(() {
        error = url.isEmpty ? '请输入服务器地址' : '请输入有效的 http:// 或 https:// 地址';
      });
      return;
    }
    UrlService().useCustomSource(url);
    Navigator.of(context).pop();
  }

  void edited(String _) {
    if (error != null) {
      setState(() {
        error = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cupertino = widget.style == ServerEditorStyle.cupertino;
    final isFluent = widget.style == ServerEditorStyle.fluent;
    final field = isFluent
        ? fluent.TextBox(
            controller: controller,
            placeholder: UrlService.defaultCustomBaseUrl,
            onChanged: edited,
            onSubmitted: (_) => save(),
          )
        : cupertino
        ? CupertinoTextField(
            controller: controller,
            placeholder: UrlService.defaultCustomBaseUrl,
            keyboardType: TextInputType.url,
            autocorrect: false,
            onChanged: edited,
            onSubmitted: (_) => save(),
          )
        : TextField(
            controller: controller,
            keyboardType: TextInputType.url,
            autocorrect: false,
            onChanged: edited,
            onSubmitted: (_) => save(),
            decoration: InputDecoration(
              labelText: '服务器地址',
              hintText: UrlService.defaultCustomBaseUrl,
              border: const OutlineInputBorder(),
            ),
          );
    final content = SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          field,
          const SizedBox(height: 8),
          const Text('填写兼容 Cyrene API 的服务器地址，更换服务器后需重新登录。'),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  error!,
                  style: TextStyle(
                    color: cupertino
                        ? CupertinoColors.systemRed.resolveFrom(context)
                        : isFluent
                        ? fluent.FluentTheme.of(
                            context,
                          ).resources.systemFillColorCritical
                        : Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    void cancel() => Navigator.of(context).pop();
    if (isFluent) {
      return fluent.ContentDialog(
        title: const Text('自定义服务器'),
        content: content,
        actions: [
          fluent.Button(onPressed: cancel, child: const Text('取消')),
          fluent.FilledButton(onPressed: save, child: const Text('保存')),
        ],
      );
    }
    if (cupertino) {
      return CupertinoAlertDialog(
        title: const Text('自定义服务器'),
        content: content,
        actions: [
          CupertinoDialogAction(onPressed: cancel, child: const Text('取消')),
          CupertinoDialogAction(onPressed: save, child: const Text('保存')),
        ],
      );
    }
    return AlertDialog(
      title: const Text('自定义服务器'),
      content: SizedBox(width: 420, child: content),
      actions: [
        TextButton(onPressed: cancel, child: const Text('取消')),
        FilledButton(onPressed: save, child: const Text('保存')),
      ],
    );
  }
}
