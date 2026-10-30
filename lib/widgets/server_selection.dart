import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;

import '../pages/settings_page/server_settings_page.dart';
import '../services/url_service.dart';
import '../utils/theme_manager.dart';

/// A quiet recovery entry that remains available before authentication.
class ServerSelection extends StatelessWidget {
  final bool fluentStyle;
  const ServerSelection({super.key, this.fluentStyle = false});

  @override
  Widget build(BuildContext context) {
    final cupertino = !fluentStyle && ThemeManager().isCupertinoFramework;
    return AnimatedBuilder(
      animation: UrlService(),
      builder: (context, _) {
        final urls = UrlService();
        final label = urls.isUsingOfficialSource
            ? '官方服务器'
            : Uri.tryParse(urls.baseUrl)?.authority ?? urls.baseUrl;
        Future<void> openSettings() async {
          FocusScope.of(context).unfocus();
          final themes = InheritedTheme.capture(
            from: context,
            to: Navigator.of(context).context,
          );
          Widget page(BuildContext _) =>
              themes.wrap(ServerSettingsPage(fluentStyle: fluentStyle));
          await Navigator.of(context).push<void>(
            cupertino
                ? CupertinoPageRoute<void>(builder: page)
                : MaterialPageRoute<void>(builder: page),
          );
        }

        final button = fluentStyle
            ? fluent.HyperlinkButton(
                onPressed: openSettings,
                child: const Text('更换'),
              )
            : cupertino
            ? CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                minimumSize: const Size(44, 44),
                onPressed: openSettings,
                child: const Text('更换', style: TextStyle(fontSize: 14)),
              )
            : TextButton(onPressed: openSettings, child: const Text('更换'));
        final color = fluentStyle
            ? fluent.FluentTheme.of(context).typography.caption?.color
            : cupertino
            ? CupertinoColors.secondaryLabel.resolveFrom(context)
            : Theme.of(context).colorScheme.onSurfaceVariant;
        return Row(
          children: [
            Icon(
              cupertino ? CupertinoIcons.globe : Icons.dns_outlined,
              size: 16,
              color: color,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Semantics(
                label: '当前服务器：${urls.baseUrl}',
                child: Text(
                  '当前服务器：$label',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: color),
                ),
              ),
            ),
            const SizedBox(width: 4),
            button,
          ],
        );
      },
    );
  }
}
