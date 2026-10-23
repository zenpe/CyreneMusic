import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;

import '../services/persistent_storage_service.dart';
import '../utils/theme_manager.dart';
import 'user_agreement_content.dart';

/// Consent is local to this screen until the user submits it successfully.
class TermsConsentScope extends StatefulWidget {
  final Widget child;
  final bool? initiallyAccepted;
  final Future<void> Function()? saveAcceptance;

  const TermsConsentScope({
    super.key,
    required this.child,
    this.initiallyAccepted,
    this.saveAcceptance,
  });

  static Future<bool> ensureAccepted(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_ConsentBinding>();
    return scope?.state.ensureAccepted() ?? Future.value(false);
  }

  @override
  State<TermsConsentScope> createState() => _TermsConsentScopeState();
}

class _TermsConsentScopeState extends State<TermsConsentScope> {
  late bool _accepted;
  bool _checked = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _accepted =
        widget.initiallyAccepted ?? PersistentStorageService().termsAccepted;
  }

  Future<bool> ensureAccepted() async {
    if (_accepted) return true;
    if (_saving) return false;
    if (!_checked) {
      setState(() => _error = '请先阅读并同意使用协议');
      return false;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await (widget.saveAcceptance?.call() ??
          PersistentStorageService().setTermsAccepted(true));
      if (mounted) setState(() => _accepted = true);
      return true;
    } catch (_) {
      if (mounted) setState(() => _error = '协议确认保存失败，请重试');
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void changeChecked(bool? value) {
    setState(() {
      _checked = value ?? false;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) =>
      _ConsentBinding(state: this, child: widget.child);
}

class _ConsentBinding extends InheritedWidget {
  final _TermsConsentScopeState state;
  final bool checked;
  final bool accepted;
  final bool saving;
  final String? error;

  _ConsentBinding({required this.state, required super.child})
    : checked = state._checked,
      accepted = state._accepted,
      saving = state._saving,
      error = state._error;

  @override
  bool updateShouldNotify(_ConsentBinding oldWidget) =>
      checked != oldWidget.checked ||
      accepted != oldWidget.accepted ||
      saving != oldWidget.saving ||
      error != oldWidget.error;
}

class TermsConsentTile extends StatelessWidget {
  final bool fluentStyle;
  const TermsConsentTile({super.key, this.fluentStyle = false});

  @override
  Widget build(BuildContext context) {
    final binding = context
        .dependOnInheritedWidgetOfExactType<_ConsentBinding>()!;
    final state = binding.state;
    final cupertino = !fluentStyle && ThemeManager().isCupertinoFramework;
    final enabled = !binding.saving && !binding.accepted;
    final checkbox = fluentStyle
        ? fluent.Checkbox(
            checked: binding.accepted || binding.checked,
            onChanged: enabled ? state.changeChecked : null,
          )
        : cupertino
        ? CupertinoCheckbox(
            value: binding.accepted || binding.checked,
            onChanged: enabled ? state.changeChecked : null,
          )
        : Checkbox(
            value: binding.accepted || binding.checked,
            onChanged: enabled ? state.changeChecked : null,
          );
    void view() => showUserAgreement(context, fluentStyle: fluentStyle);
    final link = fluentStyle
        ? fluent.HyperlinkButton(onPressed: view, child: const Text('使用协议'))
        : cupertino
        ? CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            onPressed: view,
            child: const Text('使用协议'),
          )
        : TextButton(onPressed: view, child: const Text('使用协议'));
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              checkbox,
              Expanded(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [Text(binding.accepted ? '已确认' : '我已阅读并同意'), link],
                ),
              ),
            ],
          ),
          if (binding.error != null)
            Text(binding.error!, style: const TextStyle(color: Colors.red)),
        ],
      ),
    );
  }
}

Future<void> showUserAgreement(
  BuildContext context, {
  bool fluentStyle = false,
}) async {
  final body = SizedBox(
    width: 600,
    height: 420,
    child: SingleChildScrollView(
      child: Text(userAgreementSections.join('\n\n')),
    ),
  );
  if (fluentStyle) {
    await fluent.showDialog<void>(
      context: context,
      builder: (context) => fluent.ContentDialog(
        title: const Text('使用协议'),
        content: body,
        actions: [
          fluent.Button(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  } else if (ThemeManager().isCupertinoFramework) {
    await showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('使用协议'),
        content: body,
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  } else {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('使用协议'),
        content: body,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}

/// For restored sessions that have not explicitly accepted the agreement.
class AgreementConfirmation extends StatelessWidget {
  final bool fluentStyle;
  const AgreementConfirmation({super.key, this.fluentStyle = false});

  @override
  Widget build(BuildContext context) => TermsConsentScope(
    child: Builder(
      builder: (context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('确认使用协议', style: TextStyle(fontSize: 24)),
                const SizedBox(height: 24),
                TermsConsentTile(fluentStyle: fluentStyle),
                if (fluentStyle)
                  fluent.FilledButton(
                    onPressed: () => TermsConsentScope.ensureAccepted(context),
                    child: const Text('同意并继续'),
                  )
                else if (ThemeManager().isCupertinoFramework)
                  CupertinoButton.filled(
                    onPressed: () => TermsConsentScope.ensureAccepted(context),
                    child: const Text('同意并继续'),
                  )
                else
                  FilledButton(
                    onPressed: () => TermsConsentScope.ensureAccepted(context),
                    child: const Text('同意并继续'),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
