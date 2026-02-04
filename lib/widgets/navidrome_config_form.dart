import 'package:flutter/material.dart';
import '../services/navidrome_api.dart';
import '../services/navidrome_session_service.dart';
import '../services/persistent_storage_service.dart';

class NavidromeConfigForm extends StatefulWidget {
  final bool acceptTermsOnSave;
  final String saveLabel;
  final bool showClearButton;
  final VoidCallback? onSaved;
  final VoidCallback? onCleared;

  const NavidromeConfigForm({
    super.key,
    this.acceptTermsOnSave = false,
    this.saveLabel = '保存',
    this.showClearButton = false,
    this.onSaved,
    this.onCleared,
  });

  @override
  State<NavidromeConfigForm> createState() => _NavidromeConfigFormState();
}

class _NavidromeConfigFormState extends State<NavidromeConfigForm> {
  final _formKey = GlobalKey<FormState>();
  final _baseUrlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isBusy = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    final session = NavidromeSessionService();
    _baseUrlController.text = session.baseUrl;
    _usernameController.text = session.username;
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    final baseUrl = _baseUrlController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (!_validateInputs(baseUrl, username, password)) return;

    setState(() {
      _isBusy = true;
      _statusMessage = '正在测试连接...';
    });

    try {
      final api = NavidromeApi(
        baseUrl: baseUrl,
        username: username,
        password: password,
      );
      final ok = await api.ping();
      setState(() {
        _statusMessage = ok ? '连接成功' : '连接失败';
      });
    } catch (e) {
      setState(() {
        _statusMessage = '连接失败：$e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _saveConfig() async {
    final baseUrl = _baseUrlController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (!_validateInputs(baseUrl, username, password)) return;

    setState(() {
      _isBusy = true;
      _statusMessage = null;
    });

    try {
      await NavidromeSessionService().saveConfig(
        baseUrl: baseUrl,
        username: username,
        password: password,
      );
      if (widget.acceptTermsOnSave) {
        await PersistentStorageService().setBool('terms_accepted', true);
      }
      widget.onSaved?.call();
    } catch (e) {
      setState(() {
        _statusMessage = '保存失败：$e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  bool _validateInputs(String baseUrl, String username, String password) {
    if (!_formKey.currentState!.validate()) return false;
    if (!_isValidUrl(baseUrl)) {
      setState(() {
        _statusMessage = '服务器地址无效';
      });
      return false;
    }
    if (username.isEmpty || password.isEmpty) {
      setState(() {
        _statusMessage = '用户名和密码不能为空';
      });
      return false;
    }
    return true;
  }

  bool _isValidUrl(String input) {
    final uri = Uri.tryParse(input);
    return uri != null && uri.hasScheme && uri.host.isNotEmpty;
  }

  Future<void> _clearConfig() async {
    await NavidromeSessionService().clear();
    widget.onCleared?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextFormField(
            controller: _baseUrlController,
            decoration: const InputDecoration(
              labelText: '服务器地址',
              hintText: 'https://your-navidrome.example',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
            validator: (value) =>
                value == null || value.trim().isEmpty ? '必填' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _usernameController,
            decoration: const InputDecoration(
              labelText: '用户名',
              border: OutlineInputBorder(),
            ),
            validator: (value) =>
                value == null || value.trim().isEmpty ? '必填' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _passwordController,
            decoration: InputDecoration(
              labelText: '密码',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility : Icons.visibility_off,
                ),
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
              ),
            ),
            obscureText: _obscurePassword,
            validator: (value) =>
                value == null || value.isEmpty ? '必填' : null,
          ),
          const SizedBox(height: 16),
          if (_statusMessage != null)
            Text(
              _statusMessage!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isBusy ? null : _testConnection,
                  child: const Text('测试'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _isBusy ? null : _saveConfig,
                  child: _isBusy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(widget.saveLabel),
                ),
              ),
            ],
          ),
          if (widget.showClearButton) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: _clearConfig,
              child: const Text('清除登录信息'),
            ),
          ],
        ],
      ),
    );
  }
}
