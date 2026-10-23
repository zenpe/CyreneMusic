import 'package:flutter/material.dart';
import '../features/audio_source/audio_source_feature.dart';
import '../widgets/terms_consent.dart';
import 'settings_page/audio_source_settings_page.dart';
import 'auth/auth_page.dart';

/// Resumes the first unmet prerequisite; AppGate owns state notifications.
class MobileSetupPage extends StatelessWidget {
  const MobileSetupPage({super.key});

  @override
  Widget build(BuildContext context) {
    final facade = AudioSourceFacade();
    if (!facade.isLoggedIn) {
      return const AuthPage(embedded: true);
    }
    if (!facade.termsAccepted) {
      return const Scaffold(body: SafeArea(child: AgreementConfirmation()));
    }
    return const AudioSourceSettingsContent();
  }
}
