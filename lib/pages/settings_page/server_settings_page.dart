import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;

import '../../utils/theme_manager.dart';
import 'network_settings.dart';

/// Reuses the settings UI, exposing only controls needed before login.
class ServerSettingsPage extends StatelessWidget {
  final bool fluentStyle;
  const ServerSettingsPage({super.key, this.fluentStyle = false});

  @override
  Widget build(BuildContext context) {
    final content = SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 24),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  NetworkSettings(serverOnly: true),
                  Padding(
                    padding: EdgeInsets.fromLTRB(28, 16, 28, 8),
                    child: Text('使用所选服务器上的账号登录，更换服务器后需重新登录。'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    if (fluentStyle) {
      return fluent.ScaffoldPage(
        header: fluent.PageHeader(
          title: const Text('服务器设置'),
          leading: fluent.IconButton(
            icon: const Icon(fluent.FluentIcons.back),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        content: content,
      );
    }
    if (ThemeManager().isCupertinoFramework) {
      return CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(middle: Text('服务器设置')),
        child: SafeArea(child: content),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('服务器设置')),
      body: content,
    );
  }
}
