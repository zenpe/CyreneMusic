import 'package:cyrene_music/services/app_entry_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppEntryResolver.resolve', () {
    AppEntryRoute expectedRoute({
      required bool isConfigured,
      required bool isNavidromeActive,
      required bool isTermsAccepted,
      required bool isLocalMode,
    }) {
      if (isNavidromeActive) {
        return (isConfigured && isTermsAccepted)
            ? AppEntryRoute.navidromeMain
            : AppEntryRoute.navidromeSetup;
      }
      if ((isConfigured && isTermsAccepted) ||
          (isLocalMode && isTermsAccepted)) {
        return AppEntryRoute.regularMain;
      }
      return AppEntryRoute.regularSetup;
    }

    final bools = [false, true];
    for (final isConfigured in bools) {
      for (final isNavidromeActive in bools) {
        for (final isTermsAccepted in bools) {
          for (final isLocalMode in bools) {
            test(
              'configured=$isConfigured, navidrome=$isNavidromeActive, terms=$isTermsAccepted, local=$isLocalMode',
              () {
                final route = AppEntryResolver.resolve(
                  isConfigured: isConfigured,
                  isNavidromeActive: isNavidromeActive,
                  isTermsAccepted: isTermsAccepted,
                  isLocalMode: isLocalMode,
                );

                expect(
                  route,
                  expectedRoute(
                    isConfigured: isConfigured,
                    isNavidromeActive: isNavidromeActive,
                    isTermsAccepted: isTermsAccepted,
                    isLocalMode: isLocalMode,
                  ),
                );
              },
            );
          }
        }
      }
    }
  });
}
