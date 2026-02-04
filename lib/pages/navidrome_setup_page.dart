import 'package:flutter/material.dart';
import '../widgets/navidrome_config_form.dart';

class NavidromeSetupPage extends StatelessWidget {
  const NavidromeSetupPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Navidrome 配置')),
      body: NavidromeConfigForm(
        acceptTermsOnSave: true,
        saveLabel: '保存并进入',
        onSaved: () {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已保存，可以开始使用')),
          );
        },
      ),
    );
  }
}
